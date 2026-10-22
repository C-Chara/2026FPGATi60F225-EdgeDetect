# 赛题四图像边缘检测：源码交接（2026-10-13）

## 先看这里

- 板卡：奥唯斯 VF-Ti60F225，OV5640 DVP 摄像头，DDR3 帧缓存，HDMI 720p 显示。Efinity 工程是 `Ti60_Demo.xml`（2026.1.132，Ti60F225/C4），顶层 `example_top.v`。
- 当前**实际编译链**：OV5640 RGB565 两字节/像素 → DDR（写 8 位、读 16 位）→ 灰度 → **3×3 中值滤波** → Sobel 梯度 → NMS → 一次扫描的局部双阈值弱边缘连接 → 同坐标连续两帧确认 → 彩色/灰度/黑底边缘叠加 → 圆形几何识别与中文标注 → HDMI。当前不是 Gaussian，也不是完整递归 Canny。
- 最新源码对应 `outflow/Ti60_Demo_median3_nms_temporal_confirm_20261011.bit`。已通过 Efinity 编译并于 2026-10-11 通过 JTAG 下载；用户实测**仍有明显抖动**。JTAG 配置断电丢失，启动 Flash 中可能仍是更早的版本，不能将上电画面当作此版证据。

## 关键源码索引

| 路径 | 作用 |
| --- | --- |
| `example_top.v` | 摄像头、DDR、LCD/HDMI 和当前边缘链的接线；关键逻辑约 900–1240 行。 |
| `src/cmos_i2c/I2C_OV5640_1280720_Config.v`、`src/Sensor_Image_XYCrop.v` | OV5640 初始化和 1280×720 裁剪。当前 `CAMERA_SYS_DIV=8'h21`，测试图关闭。 |
| `src/axi/axi4_ctrl.v`、`src/ddr_rw_ctrl.v`、`ip/DdrCtrl/`、`ip/*FIFO*/` | DDR AXI 与读写 FIFO。**XML 实际引用 `src/axi/axi4_ctrl.v`；`src/axi4_ctrl.v` 是另一个同名旧文件。** |
| `src/lcd_driver.v`、`src/lcd_para.v`、`src/hdmi_ip/` | 1280×720 HDMI 时序与 TMDS；`lcd_request` 比显示有效区提前一个像素。 |
| `src/edge/rgb565_gray.v`、`median3x3_video.v`、`sobel_stream.v`、`nms_stream.v` | 当前灰度、3×3 中值、Sobel 和非极大值抑制。 |
| `src/edge/hysteresis_stream.v` | 高低阈值和局部连接/补线；仅一次扫描的近邻连接。 |
| `src/edge/edge_frame_hold.v` | 帧 RAM；当前 `TEMPORAL_CONFIRM_ENABLE=1`，要求同一像素在连续两帧均被检出。此模式下旧的低释放阈值/局部峰值保持条件不参与最终输出。 |
| `src/edge/key_threshold.v`、`fps_osd.v`、`camera_fps.v` | K1 短按阈值 +1，长按约 0.8 秒切换显示模式；K2 阈值 -1；K3 是硬复位。初始高阈值 88，低阈值为一半，阈值在帧边界更新。 |
| `src/edge/rgb565_frame_align.v` | 原彩色画面与边缘处理延迟对齐。 |
| `src/edge/circle_geometry_detector.v`、`circle_label_osd.v`、`circle_font_rom.v` | 对稳定边缘做圆周几何检测并叠加“检测到圆形”。 |

`src/edge/gaussian_stream.v`、`median5x5_video.v` 是保留的对照实现，**当前顶层未实例化**。`src/edge/sobel_video.v` 是旧封装，同时 `include` 当前边缘模块以供工程编译；不要把其内部默认链路误认为当前顶层链路。`sim/` 包含仿真源码；`ip/` 包含工程引用的 IP 设置与生成文件。XML、外围约束、SDC 都已打包。

## 当前画面与问题

- 采集、DDR 和 HDMI 基本可用；实时画面及圆形识别能运行，阈值和三种显示模式可用。摄像头降速后早期竖纹和黑点已消除。
- 静止场景的主体轮廓大体清楚，但轮廓周围有零散小点来回跳动，边缘局部时有时无；阈值越低，跳点越明显。
- 冻结帧诊断时画面和轮廓不闪，恢复实时输入后又闪。这说明抖动依赖逐帧输入变化或其与阈值/NMS/连接逻辑的相互作用；**尚未证明单一根因**。
- 5×5 中值相较 3×3 改善不明显；NMS 使线变细但曾带来断点/闪烁；方向性平滑和细线连续性过滤上板后跳点几乎不变。最新“同坐标连续两帧确认”也未明显改善。像素位置在相邻帧发生轻微平移是一个待验证假设，不应当作已证实结论。

## 接续任务与约束

请先复核 `example_top.v` 中 NMS→`hysteresis_stream`→`edge_frame_hold` 的数据/有效位/坐标/帧地址对齐，重点判断是否存在抖动放大或跨帧地址错位；再针对真实输入中局部跳点提出并验证改法。保持当前摄像头寄存器、阈值默认值及步长、三种显示模式、DDR/HDMI 时序和圆形标注功能。此前用户明确要求先不要改摄像头设置或单纯反复调参数。优先做最小、可回退的改动，给出编译、仿真与上板对照结果。

## 打开与下载

在 Efinity 2026.1 打开 `Ti60_Demo.xml`；工程根目录是本说明所在目录。最新 `.bit` 仅供对照和 JTAG 临时下载。打包未包含 Efinity 安装程序、Icarus 可执行程序、历史调试快照和综合/布局布线工作目录；重新编译需要安装 Efinity 2026.1。`sim/run_checks.ps1` 原脚本指向未打包的 `tools/iverilog/`，在另一台电脑运行时需改用本机 Icarus 路径。

## 2026-10-13 接续修改（Claude）

以上内容描述的是 2026-10-11 的版本；`MANIFEST_SHA256.txt` 也仍是那一版的清单。本节之后的改动：

- **抖动结论**：数据/有效位/帧地址对齐无误（每行有效像素 1280→1278→1276，帧地址每个 VSYNC 复位）。抖动来自两处：① 显示 60 Hz、摄像头 30 fps，每个摄像头帧被读出两次，“同坐标连续两帧确认”因此隔一帧就完全不过滤；② 边缘落在两列像素之间时两个 Sobel 响应几乎相等，噪声让 NMS 每帧换一个赢家，单像素线左右跳。
- **新增 `src/edge/edge_temporal_sticky.v`**：上一帧的 NMS 赢家在梯度仍高于低阈值且接近梯度方向峰值时保留，旁边强度相近的新赢家被抑制。延迟 3 拍、不增加行延迟。`nms_stream` 多输出两侧邻居幅值。
- **高斯级接入**：`gaussian_stream` 接在中值之后，链路变为 中值→高斯→Sobel→NMS→双阈值连接。`rgb565_frame_align` 支持 4 行延迟。
- **顶层开关**（`example_top.v`）：`GAUSSIAN_ENABLE`、`TEMPORAL_STICKY_ENABLE`，都置 0 即回到 10-11 的链路。对齐量由开关自动计算（高斯 +1 行 +4 拍，时域级 +1 拍）。
- **显示模式 3**：分屏，左半原始灰度、右半二值边缘。K1 长按循环 0→1→2→3。
- **帧冻结**：K2 长按切换，停止向 DDR 写新帧，LED4 指示。K2 的阈值 -1 改为松手时生效。
- **产物**：`outflow/Ti60_Demo_median3_gauss_nms_sticky_20261013.bit`（默认开关）、`outflow/Ti60_Demo_median3_nms_sticky_20261013.bit`（不加高斯的对照）。两者 Efinity 编译通过，`clk_pixel` 建立裕量 3.5 ns / 4.0 ns，RAM 240 / 232（共 256）。
- **未做的验证**：本机没有 Verilog 仿真器，`sim/tb_edge_temporal_sticky.v` 和改过的 `key_threshold.v` 没有跑过仿真；新模块只用逐周期 Python 镜像对照过参考算法。均未上板。

"""60 fps colour: OV5640 RAW8 + raw_demosaic (Bayer 2x2, grey-world WB,
gamma). CAMERA_60FPS_RAW selects it; CAMERA_60FPS_Y8 stays available.
Test build: K1+K2 short steps the Bayer phase (OSD 'PHS n') instead of the
median demo."""
import io
import re
import sys

ROOT = sys.argv[1]


def load(path):
    raw = io.open(ROOT + '/' + path, newline='', encoding='latin-1').read()
    return raw.replace('\r\n', '\n'), '\r\n' in raw


def save(path, s, crlf):
    io.open(ROOT + '/' + path, 'w', newline='', encoding='latin-1').write(s.replace('\n', '\r\n') if crlf else s)


def sub(s, old, new, count=1):
    assert s.count(old) == count, (old[:80], s.count(old))
    return s.replace(old, new)


# ---------------------------------------------------------------- camera table
p = 'src/cmos_i2c/I2C_OV5640_1280720_Config.v'
s, crlf = load(p)
s = sub(s, "            FORMAT_Y8 = 1'b0\n",
        "            FORMAT_Y8 = 1'b0,\n"
        "            // 1: RAW8 Bayer output (ISP RAW), one byte per pixel.\n"
        "            FORMAT_RAW = 1'b0\n")
s = sub(s, "FORMAT_Y8 ? 24'h4300_10 : 24'h4300_61;\t// Y8 / RGB565",
        "FORMAT_RAW ? 24'h4300_f8 : FORMAT_Y8 ? 24'h4300_10 : 24'h4300_61;\t// RAW / Y8 / RGB565")
s = sub(s, "FORMAT_Y8 ? 24'h501f_00 : 24'h501f_01;\t// ISP YUV / ISP RGB",
        "FORMAT_RAW ? 24'h501f_03 : FORMAT_Y8 ? 24'h501f_00 : 24'h501f_01;\t// ISP RAW / ISP YUV / ISP RGB")
save(p, s, crlf)

# ---------------------------------------------------------------- fps_osd: optional PHS row instead of MED
p = 'src/edge/fps_osd.v'
s, crlf = load(p)
s = sub(s, "    parameter SHOW_FOCUS = 1'b1\n)(\n",
        "    parameter SHOW_FOCUS = 1'b1,\n"
        "    // 1: the MED line shows 'PHS n' (Bayer phase, colour test build).\n"
        "    parameter SHOW_PHASE = 1'b0\n)(\n")
s = sub(s, "    input wire recognition_on,\n", "    input wire recognition_on,\n    input wire [1:0] bayer_phase,\n")
s = sub(s, "                             (row == 5'd5) ? (median_on ? 4'd6 : 4'd7) :\n",
        "                             (row == 5'd5) ? ((SHOW_PHASE || median_on) ? 4'd6 : 4'd7) :\n")
s = sub(s, "            5'd5: case(letter)\n                0:symbol=G_M; 1:symbol=G_E; 2:symbol=G_D;\n",
        "            5'd5: if (SHOW_PHASE) case(letter)\n"
        "                0:symbol=G_P; 1:symbol=G_H; 2:symbol=G_S;\n"
        "                4:symbol={3'd0, bayer_phase};\n"
        "                default:symbol=G_BLANK;\n"
        "            endcase else case(letter)\n"
        "                0:symbol=G_M; 1:symbol=G_E; 2:symbol=G_D;\n")
save(p, s, crlf)

# ---------------------------------------------------------------- top
p = 'example_top.v'
s, crlf = load(p)
s = sub(s, "\tlocalparam CAMERA_60FPS_Y8 = 1'b1;\n"
        "\tlocalparam [7:0] CAMERA_SYS_DIV = CAMERA_60FPS_Y8 ? 8'h11 : 8'h21;\n",
        "\tlocalparam CAMERA_60FPS_Y8 = 1'b0;\n"
        "\t// 1: 60 fps colour. The OV5640 sends RAW8 Bayer (one byte per pixel,\n"
        "\t// same DVP rate as Y8); raw_demosaic rebuilds RGB (2x2 demosaic,\n"
        "\t// grey-world white balance, gamma) before the DDR.\n"
        "\tlocalparam CAMERA_60FPS_RAW = 1'b1;\n"
        "\t// Bayer order of the first pixel: 0 RGGB, 1 GRBG, 2 GBRG, 3 BGGR.\n"
        "\t// PHASE_FROM_KEYS: K1+K2 short steps it at run time (test build).\n"
        "\tlocalparam [1:0] BAYER_PHASE = 2'd3;\n"
        "\tlocalparam BAYER_PHASE_FROM_KEYS = 1'b1;\n"
        "\tlocalparam CAMERA_60FPS = CAMERA_60FPS_Y8 || CAMERA_60FPS_RAW;\n"
        "\tlocalparam [7:0] CAMERA_SYS_DIV = CAMERA_60FPS ? 8'h11 : 8'h21;\n")
s = sub(s, "\t\t.B50_STEP(CAMERA_60FPS_Y8 ? 10'd444", "\t\t.B50_STEP(CAMERA_60FPS ? 10'd444")
s = sub(s, "\t\t.B50_MAX_BANDS(CAMERA_60FPS_Y8 ? 8'd1", "\t\t.B50_MAX_BANDS(CAMERA_60FPS ? 8'd1")
s = sub(s, "\t\t.FORMAT_Y8(CAMERA_60FPS_Y8)) u_I2C_OV5640_1280720_Config",
        "\t\t.FORMAT_Y8(CAMERA_60FPS_Y8), .FORMAT_RAW(CAMERA_60FPS_RAW)) u_I2C_OV5640_1280720_Config")
s = sub(s, "(1280 * (CAMERA_60FPS_Y8 ? 1 : 2) / CSI_STRB_WIDTH)", "(1280 * (CAMERA_60FPS ? 1 : 2) / CSI_STRB_WIDTH)", 2)
s = sub(s, "\taxi4_ctrl #(.C_RD_END_ADDR(1280 * 2 * 720), .C_W_WIDTH(CAMERA_60FPS_Y8 ? 16 : CSI_DATA_WIDTH),",
        "\t// RAW8: Bayer -> RGB565 in the camera clock domain.\n"
        "\twire [1:0] bayer_phase_key;\n"
        "\t(* async_reg = \"true\" *) reg [1:0] bayer_phase_meta = 0, bayer_phase_sync = 0;\n"
        "\talways @(posedge w_cmos_pclk) begin\n"
        "\t\tbayer_phase_meta <= BAYER_PHASE_FROM_KEYS ? bayer_phase_key : BAYER_PHASE;\n"
        "\t\tbayer_phase_sync <= bayer_phase_meta;\n"
        "\tend\n"
        "\twire raw_de;\n"
        "\twire [15:0] raw_rgb565;\n"
        "\traw_demosaic #(.H_ACTIVE(1280)) u_raw_demosaic (\n"
        "\t\t.clk(w_cmos_pclk), .rst_n(rstn_sys), .frame_valid(cmos_frame_vsync),\n"
        "\t\t.de(cmos_frame_href), .raw(cmos_frame_Gray[7:0]), .phase(bayer_phase_sync),\n"
        "\t\t.gamma_on(1'b1), .de_out(raw_de), .rgb565(raw_rgb565), .gain_r(), .gain_b()\n"
        "\t);\n"
        "\twire cam_pixel_en = CAMERA_60FPS_RAW ? raw_de : cmos_frame_href;\n"
        "\twire [15:0] cam_pixel16 = CAMERA_60FPS_RAW ? raw_rgb565 : y8_rgb565;\n"
        "\taxi4_ctrl #(.C_RD_END_ADDR(1280 * 2 * 720), .C_W_WIDTH(CAMERA_60FPS ? 16 : CSI_DATA_WIDTH),")
s = sub(s, "\t\t.wframe_data_en (cmos_frame_href && !freeze_active),\n",
        "\t\t.wframe_data_en (cam_pixel_en && !freeze_active),\n")
s = sub(s, "\t\t.wframe_data    (CAMERA_60FPS_Y8 ? {48'd0, y8_rgb565} : cmos_frame_Gray),\n",
        "\t\t.wframe_data    (CAMERA_60FPS ? {48'd0, cam_pixel16} : cmos_frame_Gray),\n")
save(p, s, crlf)

s, crlf = load(p)
# median demo: in the phase test build the key combo only steps the phase
s = sub(s, "\t\t.median_on(median_on), .noise_on(noise_on),\n\t\t.focus_mode(focus_mode)",
        "\t\t.median_on(median_key_on), .noise_on(noise_key_on),\n\t\t.focus_mode(focus_mode)")
s = sub(s, "\twire median_on, noise_on, focus_mode;\n",
        "\twire median_on, noise_on, focus_mode;\n"
        "\twire median_key_on, noise_key_on;\n"
        "\t// Phase test build: every K1+K2 short press (it always changes the\n"
        "\t// median demo state) steps the Bayer phase; median stays on, no noise.\n"
        "\treg [1:0] demo_d = 0;\n"
        "\treg [1:0] bayer_phase_cnt = BAYER_PHASE;\n"
        "\talways @(posedge clk_pixel) begin\n"
        "\t\tdemo_d <= {median_key_on, noise_key_on};\n"
        "\t\tif (demo_d != {median_key_on, noise_key_on}) bayer_phase_cnt <= bayer_phase_cnt + 2'd1;\n"
        "\tend\n"
        "\tassign bayer_phase_key = bayer_phase_cnt;\n"
        "\tassign median_on = (CAMERA_60FPS_RAW && BAYER_PHASE_FROM_KEYS) ? 1'b1 : median_key_on;\n"
        "\tassign noise_on = (CAMERA_60FPS_RAW && BAYER_PHASE_FROM_KEYS) ? 1'b0 : noise_key_on;\n")
s = sub(s, "\tfps_osd #(.SHOW_FOCUS(FOCUS_CONTROL_ENABLE)) u_fps_osd (\n",
        "\tfps_osd #(.SHOW_FOCUS(FOCUS_CONTROL_ENABLE),\n"
        "\t\t.SHOW_PHASE(CAMERA_60FPS_RAW && BAYER_PHASE_FROM_KEYS)) u_fps_osd (\n")
s = sub(s, "\t\t.recognition_on(recognition_on),\n",
        "\t\t.recognition_on(recognition_on), .bayer_phase(bayer_phase_cnt),\n")
save(p, s, crlf)

x = io.open(ROOT + '/Ti60_Demo.xml', newline='').read()
nl = '\r\n' if '\r\n' in x else '\n'
anchor = '        <efx:design_file name="src/edge/shape_font_rom.v" version="default" library="default" />'
assert x.count(anchor) == 1
x = x.replace(anchor, anchor + nl +
              '        <efx:design_file name="src/edge/raw_demosaic.v" version="default" library="default" />' + nl +
              '        <efx:design_file name="src/edge/gamma_lut.v" version="default" library="default" />')
assert x.count('value="0x20261038"') == 1
x = x.replace('value="0x20261038"', 'value="0x20261039"')
io.open(ROOT + '/Ti60_Demo.xml', 'w', newline='').write(x)
print('ok')

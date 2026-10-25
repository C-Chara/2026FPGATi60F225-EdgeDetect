"""Optional 60 fps capture: OV5640 Y8 (luma only, one byte per pixel), sensor
clock doubled, PCLK unchanged in principle. Selected by CAMERA_60FPS_Y8 in
the top level; 0 keeps the 30 fps RGB565 build exactly as before."""
import io
import re
import sys

ROOT = sys.argv[1]


def load(path):
    raw = io.open(ROOT + '/' + path, newline='', encoding='latin-1').read()
    return raw.replace('\r\n', '\n'), '\r\n' in raw


def save(path, s, crlf):
    io.open(ROOT + '/' + path, 'w', newline='', encoding='latin-1').write(s.replace('\n', '\r\n') if crlf else s)


def sub(s, old, new):
    assert s.count(old) == 1, (old[:80], s.count(old))
    return s.replace(old, new)


# ---------------------------------------------------------------- camera table
p = 'src/cmos_i2c/I2C_OV5640_1280720_Config.v'
s, crlf = load(p)
s = sub(s, "            ISP_LOW_NOISE = 1'b0\n",
        "            ISP_LOW_NOISE = 1'b0,\n"
        "            // 1: Y8 output (luma only, one byte per pixel) instead of RGB565.\n"
        "            FORMAT_Y8 = 1'b0\n")
l56 = re.search(r'^56:.*$', s, re.M).group(0)
l57 = re.search(r'^57:.*$', s, re.M).group(0)
s = sub(s, l56, "56:     LUT_DATA    =   FORMAT_Y8 ? 24'h4300_10 : 24'h4300_61;\t// Y8 / RGB565")
s = sub(s, l57, "57:     LUT_DATA    =   FORMAT_Y8 ? 24'h501f_00 : 24'h501f_01;\t// ISP YUV / ISP RGB")
save(p, s, crlf)

# ---------------------------------------------------------------- top
p = 'example_top.v'
s, crlf = load(p)
s = sub(s, "\tlocalparam [7:0] CAMERA_SYS_DIV = 8'h21;\n",
        "\t// 1: experimental 60 fps capture. The OV5640 sends Y8 (gray, one byte per\n"
        "\t// pixel) and its system clock is doubled (0x3035 = 0x11), so the byte\n"
        "\t// rate on DVP stays near the proven 84 MHz. Gray is stored as RGB565\n"
        "\t// (R=G=B), so everything after the DDR is unchanged; the colour\n"
        "\t// overlay mode shows gray. 0: 30 fps RGB565 colour (release build).\n"
        "\tlocalparam CAMERA_60FPS_Y8 = 1'b1;\n"
        "\tlocalparam [7:0] CAMERA_SYS_DIV = CAMERA_60FPS_Y8 ? 8'h11 : 8'h21;\n")
s = sub(s, "\t\t.B50_STEP(!CAMERA_30FPS ? 10'd148 : CAMERA_SHORT_LINE ? 10'd263 : 10'd222),\n"
        "\t\t.B50_MAX_BANDS(!CAMERA_30FPS ? 8'd4 : CAMERA_SHORT_LINE ? 8'd2 : 8'd3),\n",
        "\t\t.B50_STEP(CAMERA_60FPS_Y8 ? 10'd444 : !CAMERA_30FPS ? 10'd148 : CAMERA_SHORT_LINE ? 10'd263 : 10'd222),\n"
        "\t\t.B50_MAX_BANDS(CAMERA_60FPS_Y8 ? 8'd1 : !CAMERA_30FPS ? 8'd4 : CAMERA_SHORT_LINE ? 8'd2 : 8'd3),\n")
s = sub(s, "\t\t.HTS(CAMERA_HTS), .ISP_LOW_NOISE(CAMERA_ISP_LOW_NOISE)) u_I2C_OV5640_1280720_Config",
        "\t\t.HTS(CAMERA_HTS), .ISP_LOW_NOISE(CAMERA_ISP_LOW_NOISE),\n"
        "\t\t.FORMAT_Y8(CAMERA_60FPS_Y8)) u_I2C_OV5640_1280720_Config")
s = sub(s, "\t\t//\tRGB width doubled. \n"
        "\t\t.IMAGE_HSIZE_SOURCE (1280 * 2 / CSI_STRB_WIDTH),\n"
        "\t\t.IMAGE_VSIZE_SOURCE (720\t ),\n"
        "\t\t.IMAGE_HSIZE_TARGET (1280 * 2 / CSI_STRB_WIDTH),\n",
        "\t\t//\tRGB565: two bytes per pixel; Y8: one.\n"
        "\t\t.IMAGE_HSIZE_SOURCE (1280 * (CAMERA_60FPS_Y8 ? 1 : 2) / CSI_STRB_WIDTH),\n"
        "\t\t.IMAGE_VSIZE_SOURCE (720\t ),\n"
        "\t\t.IMAGE_HSIZE_TARGET (1280 * (CAMERA_60FPS_Y8 ? 1 : 2) / CSI_STRB_WIDTH),\n")
s = sub(s, "\taxi4_ctrl #(.C_RD_END_ADDR(1280 * 2 * 720), .C_W_WIDTH(CSI_DATA_WIDTH), .C_R_WIDTH(16), .C_ID_LEN(4),\n",
        "\t// Y8: each byte is one gray pixel, written as RGB565 with R = G = B.\n"
        "\twire [7:0] y8_byte = cmos_frame_Gray[7:0];\n"
        "\twire [15:0] y8_rgb565 = {y8_byte[7:3], y8_byte[7:2], y8_byte[7:3]};\n"
        "\taxi4_ctrl #(.C_RD_END_ADDR(1280 * 2 * 720), .C_W_WIDTH(CAMERA_60FPS_Y8 ? 16 : CSI_DATA_WIDTH), .C_R_WIDTH(16), .C_ID_LEN(4),\n")
s = sub(s, "\t\t.wframe_data    (cmos_frame_Gray),\n",
        "\t\t.wframe_data    (CAMERA_60FPS_Y8 ? {48'd0, y8_rgb565} : cmos_frame_Gray),\n")
save(p, s, crlf)

x = io.open(ROOT + '/Ti60_Demo.xml', newline='').read()
assert x.count('value="0x20261037"') == 1
io.open(ROOT + '/Ti60_Demo.xml', 'w', newline='').write(x.replace('value="0x20261037"', 'value="0x20261038"'))
print('ok')

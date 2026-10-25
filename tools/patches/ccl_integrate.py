"""Put the new shape_detector/shape_overlay in the top level behind
SHAPE_DETECTOR (1 = connected components, 0 = previous geometry search)."""
import io
import sys

ROOT = sys.argv[1]
p = ROOT + '/example_top.v'
raw = io.open(p, newline='', encoding='latin-1').read()
crlf = '\r\n' in raw
s = raw.replace('\r\n', '\n')

start = s.index("\t// Recognize one near-frontal circular outline from the stable edge map.\n")
end_marker = "\t\t.rgb_out(circle_annotated_rgb)\n\t);\n"
end = s.index(end_marker, start) + len(end_marker)
old_block = s[start:end]
indented = ''.join('\t' + l if l.strip() else l for l in old_block.splitlines(True))

new_block = (
    "\t// Shape recognition, shown while recognition_on (K1+K2 long hold).\n"
    "\t// 1: connected components + moment invariants (shape_detector): every\n"
    "\t//    dark object on a light background is classified as circle,\n"
    "\t//    ellipse, square, rectangle or triangle at any rotation; up to 32\n"
    "\t//    objects, outlined in their class colour and named when <= 8.\n"
    "\t// 0: the earlier edge-grid search for one circle and one axis-aligned\n"
    "\t//    rectangle (circle_geometry_detector).\n"
    "\tlocalparam SHAPE_DETECTOR = 1'b1;\n"
    "\twire [23:0] shape_rgb;\n"
    "\twire shape_vs, shape_hs, shape_de;\n"
    "\tgenerate if (SHAPE_DETECTOR) begin: ccl_shapes\n"
    "\t\twire [5:0] shape_count;\n"
    "\t\twire [32*41-1:0] shape_objects;\n"
    "\t\tshape_detector u_shape_detector (\n"
    "\t\t\t.clk(clk_pixel), .rst_n(rstn_pixel), .vsync_n(filtered_vs),\n"
    "\t\t\t.de(filtered_valid), .gray(filtered_pixel),\n"
    "\t\t\t.obj_count(shape_count), .obj_data(shape_objects), .threshold()\n"
    "\t\t);\n"
    "\t\t// Three-clock overlay; the sync signals are delayed with it.\n"
    "\t\tshape_overlay u_shape_overlay (\n"
    "\t\t\t.clk(clk_pixel), .rst_n(rstn_pixel), .enable(recognition_on),\n"
    "\t\t\t.vs_in(lcd_vs), .hs_in(lcd_hs), .de_in(lcd_de),\n"
    "\t\t\t.rgb_in(FPS_OSD_ENABLE ? edge_fps_rgb : edge_rgb),\n"
    "\t\t\t.obj_count(shape_count), .obj_data(shape_objects),\n"
    "\t\t\t.vs_out(shape_vs), .hs_out(shape_hs), .de_out(shape_de), .rgb_out(shape_rgb)\n"
    "\t\t);\n"
    "\tend else begin: geometry_shapes\n"
    + indented +
    "\t\tassign shape_rgb = circle_annotated_rgb;\n"
    "\t\tassign shape_vs = lcd_vs;\n"
    "\t\tassign shape_hs = lcd_hs;\n"
    "\t\tassign shape_de = lcd_de;\n"
    "\tend endgenerate\n")
s = s[:start] + new_block + s[end:]


def sub(old, new):
    global s
    assert s.count(old) == 1, old[:70]
    s = s.replace(old, new)


sub("\twire hdmi_vs = lcd_vs;\n\twire hdmi_hs = lcd_hs;\n\twire hdmi_de = lcd_de;\n",
    "\twire hdmi_vs = shape_vs;\n\twire hdmi_hs = shape_hs;\n\twire hdmi_de = shape_de;\n")
sub("\t\tEDGE_ENABLE ? circle_annotated_rgb : {lcd_red, lcd_green, lcd_blue};\n",
    "\t\tEDGE_ENABLE ? shape_rgb : {lcd_red, lcd_green, lcd_blue};\n")
io.open(p, 'w', newline='', encoding='latin-1').write(s.replace('\n', '\r\n') if crlf else s)

x = io.open(ROOT + '/Ti60_Demo.xml', newline='').read()
nl = '\r\n' if '\r\n' in x else '\n'
anchor = '        <efx:design_file name="src/edge/edge_fragment_filter.v" version="default" library="default" />'
assert x.count(anchor) == 1
x = x.replace(anchor, anchor + nl +
              '        <efx:design_file name="src/edge/shape_detector.v" version="default" library="default" />' + nl +
              '        <efx:design_file name="src/edge/shape_overlay.v" version="default" library="default" />' + nl +
              '        <efx:design_file name="src/edge/shape_font_rom.v" version="default" library="default" />')
assert x.count('value="0x20261036"') == 1
x = x.replace('value="0x20261036"', 'value="0x20261037"')
io.open(ROOT + '/Ti60_Demo.xml', 'w', newline='').write(x)
print('ok')

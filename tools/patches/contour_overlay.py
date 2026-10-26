"""Shape overlay draws the object's own contour (edge pixels inside its box,
in the class colour, 2 px wide) instead of the bounding box. Bayer phase fixed
at 3, K1+K2 short back to the median demo."""
import io
import sys

ROOT = sys.argv[1]


def edit(path, pairs, enc='utf-8'):
    raw = io.open(ROOT + '/' + path, newline='', encoding=enc).read()
    crlf = '\r\n' in raw
    s = raw.replace('\r\n', '\n')
    for old, new in pairs:
        assert s.count(old) == 1, (path, old[:70], s.count(old))
        s = s.replace(old, new)
    io.open(ROOT + '/' + path, 'w', newline='', encoding=enc).write(s.replace('\n', '\r\n') if crlf else s)


edit('src/edge/shape_overlay.v', [
    ("// Draws the shape_detector results on the video: a 2-pixel outline around\n"
     "// every object in its class colour, and (when there are at most LABELS\n"
     "// objects) the class name above the box:\n",
     "// Draws the shape_detector results on the video: the object's own contour\n"
     "// (the edge pixels inside its box, widened to 2 pixels) in its class\n"
     "// colour, and (when there are at most LABELS objects) the class name above\n"
     "// the box:\n"),
    ("    input  wire [23:0] rgb_in,\n",
     "    input  wire [23:0] rgb_in,\n"
     "    input  wire        edge_in,                  // edge pixel, same clock as rgb_in\n"),
    ("            hit1[i] <= enable && i < obj_count &&\n"
     "                       x + 11'd2 >= bx0 && x <= bx1 + 11'd2 && y + 10'd2 >= by0 && y <= by1 + 10'd2 &&\n"
     "                       !(x >= bx0 + 11'd1 && x + 11'd1 <= bx1 && y >= by0 + 10'd1 && y + 10'd1 <= by1);\n",
     "            // inside the box, 4 pixels of margin for the edge line\n"
     "            hit1[i] <= enable && i < obj_count &&\n"
     "                       x + 11'd4 >= bx0 && x <= bx1 + 11'd4 && y + 10'd4 >= by0 && y <= by1 + 10'd4;\n"),
    ("        x1r <= x; y1r <= y;\n",
     "        x1r <= x; y1r <= y;\n"
     "        edge_prev <= edge_in;\n"
     "        edge1 <= edge_in || edge_prev;\n"),
    ("    reg        v1, h1, d1;\n",
     "    reg        v1, h1, d1;\n"
     "    reg        edge_prev, edge1, edge2;\n"),
    ("        v2 <= v1; h2 <= h1; d2 <= d1;\n",
     "        v2 <= v1; h2 <= h1; d2 <= d1;\n"
     "        edge2 <= edge1;\n"),
    ("                       out2 ? cls_rgb(ocls2) : rgb2;\n",
     "                       (out2 && edge2) ? cls_rgb(ocls2) : rgb2;\n"),
])

edit('example_top.v', [
    ("\tlocalparam BAYER_PHASE_FROM_KEYS = 1'b1;\n", "\tlocalparam BAYER_PHASE_FROM_KEYS = 1'b0;\n"),
    ("\t\t\t.rgb_in(FPS_OSD_ENABLE ? edge_fps_rgb : edge_rgb),\n"
     "\t\t\t.obj_count(shape_count), .obj_data(shape_objects),\n",
     "\t\t\t.rgb_in(FPS_OSD_ENABLE ? edge_fps_rgb : edge_rgb),\n"
     "\t\t\t.edge_in(final_edge && aligned_rgb_valid),\n"
     "\t\t\t.obj_count(shape_count), .obj_data(shape_objects),\n"),
], enc='latin-1')

x = io.open(ROOT + '/Ti60_Demo.xml', newline='').read()
assert x.count('value="0x2026103a"') == 1
io.open(ROOT + '/Ti60_Demo.xml', 'w', newline='').write(x.replace('value="0x2026103a"', 'value="0x2026103b"'))
print('ok')

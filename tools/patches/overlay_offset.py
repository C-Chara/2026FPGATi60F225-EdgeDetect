"""Shift the shape boxes into screen coordinates.

The display shows the colour image (and the edges) delayed by
ALIGN_ROW_DELAY rows and ALIGN_PIXEL_DELAY + 1 clocks; the detector counts
the median-filter output, whose pixel (r, c) is image pixel (r-1, c-1). So a
box at detector position p appears on screen at p + (ALIGN_PIXEL_DELAY,
ALIGN_ROW_DELAY - 1)."""
import io
import sys

ROOT = sys.argv[1]


def edit(path, pairs, enc='utf-8'):
    raw = io.open(ROOT + '/' + path, newline='', encoding=enc).read()
    crlf = '\r\n' in raw
    s = raw.replace('\r\n', '\n')
    for old, new, n in pairs:
        assert s.count(old) == n, (path, old[:70], s.count(old))
        s = s.replace(old, new)
    io.open(ROOT + '/' + path, 'w', newline='', encoding=enc).write(s.replace('\n', '\r\n') if crlf else s)


edit('src/edge/shape_overlay.v', [
    ("    parameter integer LABELS = 8\n)(\n",
     "    parameter integer LABELS = 8,\n"
     "    // Screen position of detector pixel (0, 0): the display delay of the\n"
     "    // colour image and edges relative to the detector's coordinates.\n"
     "    parameter integer X_OFF = 0,\n"
     "    parameter integer Y_OFF = 0\n)(\n", 1),
    ("            bx0 = {obj_data[i*41+28 +: 10], 1'b0};\n"
     "            bx1 = {obj_data[i*41+18 +: 10], 1'b1};\n"
     "            by0 = {obj_data[i*41+9 +: 9], 1'b0};\n"
     "            by1 = {obj_data[i*41 +: 9], 1'b1};\n",
     "            bx0 = {obj_data[i*41+28 +: 10], 1'b0} + X_OFF;\n"
     "            bx1 = {obj_data[i*41+18 +: 10], 1'b1} + X_OFF;\n"
     "            by0 = {obj_data[i*41+9 +: 9], 1'b0} + Y_OFF;\n"
     "            by1 = {obj_data[i*41 +: 9], 1'b1} + Y_OFF;\n", 1),
    ("            lx  = {obj_data[i*41+28 +: 10], 1'b0};\n"
     "            by0 = {obj_data[i*41+9 +: 9], 1'b0};\n"
     "            by1 = {obj_data[i*41 +: 9], 1'b1};\n",
     "            lx  = {obj_data[i*41+28 +: 10], 1'b0} + X_OFF;\n"
     "            by0 = {obj_data[i*41+9 +: 9], 1'b0} + Y_OFF;\n"
     "            by1 = {obj_data[i*41 +: 9], 1'b1} + Y_OFF;\n", 1),
    ("                flx = {obj_data[i*41+28 +: 10], 1'b0};\n"
     "                fby0 = {obj_data[i*41+9 +: 9], 1'b0};\n"
     "                fby1 = {obj_data[i*41 +: 9], 1'b1};\n",
     "                flx = {obj_data[i*41+28 +: 10], 1'b0} + X_OFF;\n"
     "                fby0 = {obj_data[i*41+9 +: 9], 1'b0} + Y_OFF;\n"
     "                fby1 = {obj_data[i*41 +: 9], 1'b1} + Y_OFF;\n", 1),
])

edit('example_top.v', [
    ("\t\tshape_overlay u_shape_overlay (\n",
     "\t\tshape_overlay #(.X_OFF(ALIGN_PIXEL_DELAY), .Y_OFF(ALIGN_ROW_DELAY - 1)) u_shape_overlay (\n", 1),
], enc='latin-1')

x = io.open(ROOT + '/Ti60_Demo.xml', newline='').read()
assert x.count('value="0x2026103b"') == 1
io.open(ROOT + '/Ti60_Demo.xml', 'w', newline='').write(x.replace('value="0x2026103b"', 'value="0x2026103d"'))
print('ok')

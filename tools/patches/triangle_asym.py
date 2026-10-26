"""Triangles must be asymmetric: centroid off the bounding-box centre by at
least ~4 % of the box in x or y (5/64 of the doubled offset). Centrally
symmetric shapes (e.g. two checkerboard squares joined at a corner) whose J
falls in the triangle band are rejected."""
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


edit('src/edge/shape_detector.v', [
    ("    reg [40:0] cbox;\n",
     "    reg [40:0] cbox;\n"
     "    // Triangle symmetry test: A*(x0+x1), A*(y0+y1), A*width, A*height\n"
     "    reg [63:0] t_bx, t_by, t_wx, t_wy;\n"),
    ("                        if (cstep == 5'd15) begin\n"
     "                            cwait <= 0;\n"
     "                            if (j2 <= K_ELLIPSE_MAX) cls <= rounder ? CLS_CIRCLE : CLS_ELLIPSE;\n"
     "                            else if (j2 >= K_RECT_MIN && j2 <= K_RECT_MAX) cls <= rounder ? CLS_SQUARE : CLS_RECT;\n"
     "                            else if (j2 >= K_TRI_MIN && j2 <= K_TRI_MAX) cls <= CLS_TRIANGLE;\n",
     "                        if (cstep == 5'd19) begin\n"
     "                            cwait <= 0;\n"
     "                            if (j2 <= K_ELLIPSE_MAX) cls <= rounder ? CLS_CIRCLE : CLS_ELLIPSE;\n"
     "                            else if (j2 >= K_RECT_MIN && j2 <= K_RECT_MAX) cls <= rounder ? CLS_SQUARE : CLS_RECT;\n"
     "                            else if (j2 >= K_TRI_MIN && j2 <= K_TRI_MAX && tri_asym) cls <= CLS_TRIANGLE;\n"),
    ("                            5'd14: begin op_a <= m20 + m02; op_b <= m20 + m02; mul_go <= 1; end\n",
     "                            5'd14: begin op_a <= m20 + m02; op_b <= m20 + m02; mul_go <= 1; end\n"
     "                            5'd15: begin op_a <= cA; op_b <= cbox[37:28] + cbox[27:18]; mul_go <= 1; end\n"
     "                            5'd16: begin op_a <= cA; op_b <= cbox[17:9] + cbox[8:0]; mul_go <= 1; end\n"
     "                            5'd17: begin op_a <= cA; op_b <= cbox[27:18] - cbox[37:28] + 10'd1; mul_go <= 1; end\n"
     "                            5'd18: begin op_a <= cA; op_b <= cbox[8:0] - cbox[17:9] + 9'd1; mul_go <= 1; end\n"),
    ("                            5'd14: qd <= r_mul;\n",
     "                            5'd14: qd <= r_mul;\n"
     "                            5'd15: t_bx <= r_mul;\n"
     "                            5'd16: t_by <= r_mul;\n"
     "                            5'd17: t_wx <= r_mul;\n"
     "                            5'd18: t_wy <= r_mul;\n"),
    ("    wire [33:0] thr_calc = (gray_sum * 34'd175) >> 26;\n",
     "    wire [33:0] thr_calc = (gray_sum * 34'd175) >> 26;\n"
     "    // |2*Sx - A*(x0+x1)| = 2*A*|centroid - box centre|; compare with 5/64*A*width\n"
     "    wire [63:0] two_sx = cSx << 1, two_sy = cSy << 1;\n"
     "    wire [63:0] off_x = (two_sx > t_bx) ? two_sx - t_bx : t_bx - two_sx;\n"
     "    wire [63:0] off_y = (two_sy > t_by) ? two_sy - t_by : t_by - two_sy;\n"
     "    wire        tri_asym = (off_x >= ((t_wx << 2) + t_wx) >> 6) ||\n"
     "                           (off_y >= ((t_wy << 2) + t_wy) >> 6);\n"),
])
edit('src/edge/shape_detector.v', [
    ("            cbox <= 0; cstep <= 0; cwait <= 0; cls <= 0;\n",
     "            cbox <= 0; cstep <= 0; cwait <= 0; cls <= 0;\n"
     "            t_bx <= 0; t_by <= 0; t_wx <= 0; t_wy <= 0;\n"),
])

edit('tools/models/shape_ccl_model.py', [
    ("    if aa * K_TRI_MIN <= lhs <= aa * K_TRI_MAX:\n        return CLS_TRIANGLE\n",
     "    if aa * K_TRI_MIN <= lhs <= aa * K_TRI_MAX:\n"
     "        # triangles are not centrally symmetric: centroid off the box centre\n"
     "        off_x = abs(2 * e['Sx'] - A * (e['x0'] + e['x1']))\n"
     "        off_y = abs(2 * e['Sy'] - A * (e['y0'] + e['y1']))\n"
     "        wx = A * (e['x1'] - e['x0'] + 1)\n"
     "        wy = A * (e['y1'] - e['y0'] + 1)\n"
     "        if off_x >= (5 * wx) >> 6 or off_y >= (5 * wy) >> 6:\n"
     "            return CLS_TRIANGLE\n"),
])

x = io.open(ROOT + '/Ti60_Demo.xml', newline='').read()
assert x.count('value="0x20261039"') == 1
io.open(ROOT + '/Ti60_Demo.xml', 'w', newline='').write(x.replace('value="0x20261039"', 'value="0x2026103a"'))
print('ok')

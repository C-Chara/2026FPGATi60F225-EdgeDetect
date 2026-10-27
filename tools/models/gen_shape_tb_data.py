"""Make a 1280x720 test image for sim/tb_shape_detector.v and the expected
object list from the reference model.

Usage: gen_shape_tb_data.py <case> <out_dir>
Writes <out_dir>/shape_img.hex (one byte per pixel, raster order) and
<out_dir>/shape_expected.txt (threshold of the second scan, then one line
per object: cls x0 x1 y0 y1).
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shape_features as sf          # noqa: E402
import shape_ccl_model as m          # noqa: E402


def page(shapes):
    def f(X, Y):
        mk = np.zeros_like(X, bool)
        for s in shapes:
            mk |= s(X, Y)
        return mk
    return f


def checker(x0, y0, cols, rows, s):
    def f(X, Y):
        cx = np.floor((X - x0) / s)
        cy = np.floor((Y - y0) / s)
        inside = (cx >= 0) & (cx < cols) & (cy >= 0) & (cy < rows)
        return inside & (((cx + cy) % 2) == 0)
    return f


def bowtie(cx, cy, s, bridge):
    def f(X, Y):
        a = (X >= cx - s) & (X < cx) & (Y >= cy - s) & (Y < cy)
        b = (X >= cx) & (X < cx + s) & (Y >= cy) & (Y < cy + s)
        c = (np.abs(X - cx) < bridge) & (np.abs(Y - cy) < bridge)
        return a | b | c
    return f


def dots(x0, y0, cols, rows, pitch, size):
    def f(X, Y):
        u = X - x0
        v = Y - y0
        inside = (u >= 0) & (u < cols * pitch) & (v >= 0) & (v < rows * pitch)
        return inside & ((u % pitch) < size) & ((v % pitch) < size)
    return f


r = math.radians
CASES = {
    # 720 dots above the shapes: more labels than the old 255-entry table
    'clutter': page([dots(20, 6, 60, 12, 10, 4), sf.ellipse(130, 250, 55, 55),
                     sf.rect(330, 250, 110, 110, r(20)), sf.ellipse(530, 250, 80, 45, r(30))]),
    'mixed': page([sf.ellipse(130, 110, 50, 50), sf.rect(330, 110, 150, 100, r(25)),
                   sf.triangle(520, 120, 60, r(10)), sf.ellipse(150, 270, 90, 45, r(20)),
                   sf.rounded(380, 270, 160, 100, 30), sf.rect(560, 280, 70, 70, r(40))]),
    'checker': page([checker(95, 30, 9, 6, 50)]),
    # two bow ties (squares joined at a corner) and two triangles
    'bowtie': page([bowtie(160, 120, 45, 12), bowtie(470, 120, 45, 16),
                    sf.triangle(170, 280, 55, r(15)), sf.triangle(470, 270, 60, r(45))]),
}

case, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
img = sf.render(CASES[case])
gray = np.clip(np.round(img), 0, 255).astype(int)          # 640 x 360
full = np.repeat(np.repeat(gray, 2, axis=0), 2, axis=1)    # 1280 x 720
with open(os.path.join(out, 'shape_img.hex'), 'w') as fh:
    fh.write('\n'.join('%02x' % v for v in full.flatten()))
    fh.write('\n')
# The RTL scans the first frame with threshold 100, the second with the
# threshold computed from the first scan.
s = int(gray.sum())
thr = m.threshold_from_sum(s)
thr = min(max(thr, 30), 200)
objs, labels = m.classify_frame(gray.tolist(), thr)
with open(os.path.join(out, 'shape_expected.txt'), 'w') as fh:
    fh.write('%d\n' % thr)
    for o in objs:
        fh.write('%d %d %d %d %d\n' % o)
print('case %s: threshold %d, %d labels, %d objects' % (case, thr, len(labels), len(objs)))
for o in objs:
    print('  ', m.CLS_NAME[o[0]], o[1:])

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

def study_case(name):
    """Scenes from shape_robust_study.py (median-filtered, as the hardware sees)."""
    import shape_robust_study as st
    rng = np.random.default_rng(11)
    if name == 'small':          # distant shapes: radius 8..13 samples
        shapes = [st.make_shapes(k, s, 60 + 105 * i, 120 + 120 * (i % 2), r(17 * i))
                  for i, (k, s) in enumerate([('circle', 9), ('square', 10), ('triangle', 11),
                                              ('ellipse', 9), ('rect', 10), ('circle', 13)])]
        return st.render(shapes, 8.0, False, rng)
    if name in ('texture', 'objects'):   # should give (almost) no detections
        bg = st.clutter_background(name, np.random.default_rng(101))
        if name == 'objects':
            bg = np.minimum(bg, st.clutter_background('strokes', np.random.default_rng(102)))
        return np.clip(np.round(st.median3(bg + rng.normal(0, 8.0, bg.shape))), 0, 255).astype(int)
    if name == 'paper':          # shapes on a sheet in a textured scene
        bg = st.clutter_background('texture', np.random.default_rng(201))
        Y, X = np.mgrid[0:360, 0:640]
        bg = np.where((np.abs(X - 320) < 170) & (np.abs(Y - 180) < 110), 255.0, bg)
        shapes = [st.make_shapes('circle', 30, 230, 150, 0), st.make_shapes('square', 22, 400, 150, r(20)),
                  st.make_shapes('triangle', 26, 320, 230, r(10))]
        return st.render(shapes, 8.0, False, rng, background=bg)
    if name == 'streaks':        # the board's Page 4: dark gray print with light streaks
        Y, X = np.mgrid[0:360, 0:640]
        img = np.full((360, 640), 215.0)
        ink = ((X - 220) ** 2 + (Y - 180) ** 2 <= 48 ** 2) | \
              ((np.abs(X - 430) <= 52) & (np.abs(Y - 180) <= 52))
        img[ink] = 75.0                              # gamma-encoded dark gray
        for sx, w in ((190, 1), (205, 2), (238, 1), (400, 2), (425, 1), (452, 2)):
            img[ink & (X >= sx) & (X < sx + w)] = 160.0   # streaks above threshold
        k = np.array([1, 2, 1], float) / 4
        img = np.apply_along_axis(lambda q: np.convolve(np.pad(q, 1, mode='edge'), k, 'valid'), 0, img)
        img += rng.normal(0, 4.0, img.shape)
        return np.clip(np.round(img), 0, 255).astype(int)
    if name == 'vignette':       # lens falloff, shapes near the edges of the picture
        import shape_robust_study as st
        Y, X = np.mgrid[0:360, 0:640]
        paper = X > 8                                # paper fills the view
        img = np.where(paper, 215.0, 55.0)
        ink = ((X - 95) ** 2 + (Y - 180) ** 2 <= 42 ** 2) | \
              st.make_shapes('square', 42, 540, 175, r(12))(X + 0.5, Y + 0.5) | \
              ((X - 320) ** 2 + (Y - 180) ** 2 <= 42 ** 2)
        img[ink] = 70.0
        rr = ((X - 320) / 320.0) ** 2 + ((Y - 180) / 180.0) ** 2   # 1 at the edge centres
        img = img * (1 - 0.25 * rr) * (0.45 + 0.55 * X / 640.0)   # falloff + side light
        k = np.array([1, 2, 1], float) / 4
        for ax in (0, 1):
            img = np.apply_along_axis(lambda q: np.convolve(np.pad(q, 1, mode='edge'), k, 'valid'), ax, img)
        img += rng.normal(0, 5.0, img.shape)
        return np.clip(np.round(st.median3(img)), 0, 255).astype(int)
    if name == 'blotchy':        # uneven print: glare patches and holes inside the ink
        Y, X = np.mgrid[0:360, 0:640]
        img = np.full((360, 640), 210.0)
        ink = ((X - 170) ** 2 + (Y - 180) ** 2 <= 50 ** 2) | \
              ((np.abs(X - 360) <= 50) & (np.abs(Y - 180) <= 50)) | \
              ((Y - 120) * 1.0 > -1.6 * np.abs(X - 540) + 0) & (Y < 240) & (Y > 120 - 0) & \
              (np.abs(X - 540) <= (Y - 120) * 0.58)
        img[ink] = 85.0
        g = np.random.default_rng(31)
        for _ in range(40):                          # glare / worn toner spots
            cx, cy = g.uniform(100, 600), g.uniform(110, 250)
            rr = g.uniform(2, 6)
            img[ink & ((X - cx) ** 2 + (Y - cy) ** 2 <= rr * rr)] = 170.0
        img += rng.normal(0, 6.0, img.shape)
        return np.clip(np.round(img), 0, 255).astype(int)
    raise KeyError(name)


case, out = sys.argv[1], sys.argv[2]
os.makedirs(out, exist_ok=True)
if case in CASES:
    img = sf.render(CASES[case])
    gray = np.clip(np.round(img), 0, 255).astype(int)      # 640 x 360
else:
    gray = study_case(case)
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

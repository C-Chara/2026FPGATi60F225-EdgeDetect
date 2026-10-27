"""Feature study for small shapes and cluttered backgrounds.

Renders scenes at 640 x 360 (the detector's sampling grid), runs the CCL
model and records, for every candidate region (area >= 100, not touching
the border), the features the classifier can use:
  A      area in samples
  J2     J^2 * 2^26 (moment invariant, ellipse 424955, rectangle 466034,
         equilateral triangle 621378)
  ASP2   moment aspect ratio squared (qn/qd form: 1.12^2 limit = 13/1024)
  CVX    (runs + top edges) / (width + height): 1.0 for a convex region
         without holes, larger for ragged, concave or holed regions
  RHO    mean gray inside / mean gray of the samples OUTER beyond each run
         end: about 0.2 for ink on paper, near 1 for shadows and texture
  TRUTH  the placed shape the region belongs to, or 'clutter'
and the class given by the current rules and by the candidate rules.

Usage: shape_robust_study.py <out_dir>
Writes <out_dir>/shape_features.csv and <out_dir>/shape_study.txt.
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shape_features as sf          # noqa: E402
import shape_ccl_model as m          # noqa: E402

r = math.radians
W, H = 640, 360


def page(shapes):
    def f(X, Y):
        mk = np.zeros_like(X, bool)
        for s in shapes:
            mk |= s(X, Y)
        return mk
    return f


def median3(img):
    """3x3 median: the hardware detector sees the median-filtered gray."""
    p = np.pad(img, 1, mode='edge')
    st = np.stack([p[dy:dy + H, dx:dx + W] for dy in range(3) for dx in range(3)])
    return np.median(st, axis=0)


def render(shapes, noise, blur2, rng, background=None):
    sf.rng = rng
    img = sf.render(page(shapes), noise=noise)
    if blur2:                                   # a softer (more distant) camera
        k = np.array([1, 2, 1], float) / 4
        img = np.apply_along_axis(lambda q: np.convolve(np.pad(q, 1, mode='edge'), k, 'valid'), 1, img)
        img = np.apply_along_axis(lambda q: np.convolve(np.pad(q, 1, mode='edge'), k, 'valid'), 0, img)
    if background is not None:
        img = np.minimum(img, background)
    img = median3(img)
    return np.clip(np.round(img), 0, 255).astype(int)


def smooth_field(rng, scale):
    f = rng.normal(0, 1, (H // scale + 3, W // scale + 3))
    big = np.kron(f, np.ones((scale, scale)))[:H, :W]
    k = np.ones(scale) / scale
    big = np.apply_along_axis(lambda q: np.convolve(q, k, 'same'), 1, big)
    big = np.apply_along_axis(lambda q: np.convolve(q, k, 'same'), 0, big)
    return big / big.std()


def clutter_background(kind, rng):
    """Gray image (no placed shapes) that should give no detections."""
    Y, X = np.mgrid[0:H, 0:W]
    if kind == 'texture':            # mottled surface, dark patches
        return 150 + 55 * smooth_field(rng, 12)
    if kind == 'fine_texture':       # fabric / keyboard-like small blobs
        return 150 + 60 * smooth_field(rng, 4)
    if kind == 'shadows':            # soft dark blobs on a light wall
        img = np.full((H, W), 205.0)
        for _ in range(6):
            cx, cy = rng.uniform(60, 580), rng.uniform(50, 310)
            sx, sy = rng.uniform(15, 50), rng.uniform(15, 50)
            img -= 120 * np.exp(-(((X - cx) / sx) ** 2 + ((Y - cy) / sy) ** 2))
        return img
    if kind == 'strokes':            # cables, pen strokes, frame edges
        img = np.full((H, W), 200.0)
        for _ in range(14):
            x0, y0 = rng.uniform(20, 620), rng.uniform(20, 340)
            a = rng.uniform(0, math.pi)
            L, t = rng.uniform(40, 200), rng.uniform(2, 7)
            u = (X - x0) * math.cos(a) + (Y - y0) * math.sin(a)
            v = -(X - x0) * math.sin(a) + (Y - y0) * math.cos(a)
            img[(np.abs(u) < L / 2) & (np.abs(v) < t / 2)] = 45
        return img
    if kind == 'objects':            # irregular dark objects (concave polygons)
        img = np.full((H, W), 200.0)
        for _ in range(5):
            cx, cy = rng.uniform(80, 560), rng.uniform(70, 290)
            n = 9
            ang = np.sort(rng.uniform(0, 2 * math.pi, n))
            rad = rng.uniform(15, 55, n)
            pts = [(cx + q * math.cos(a), cy + q * math.sin(a)) for a, q in zip(ang, rad)]
            # star-shaped polygon test by angle sector
            th = np.arctan2(Y - cy, X - cx) % (2 * math.pi)
            dist = np.hypot(X - cx, Y - cy)
            idx = np.searchsorted(ang, th) % n
            prv = (idx - 1) % n
            a0, a1 = ang[prv], ang[idx]
            span = (a1 - a0) % (2 * math.pi)
            t = ((th - a0) % (2 * math.pi)) / np.maximum(span, 1e-9)
            lim = rad[prv] * (1 - t) + rad[idx] * t
            img[dist <= lim] = 50
        return img
    if kind == 'text':               # printed text lines: many small marks
        img = np.full((H, W), 210.0)
        for row in range(6):
            y = 40 + row * 50
            x = 40
            while x < 600:
                w = int(rng.integers(6, 14))
                h = int(rng.integers(10, 16))
                img[y:y + h, x:x + w] = 50
                img[y + 3:y + h - 3, x + 2:x + w - 2] = 210      # hollow glyph
                x += w + int(rng.integers(3, 8))
        return img
    raise ValueError(kind)


def make_shapes(kind, size, cx, cy, rot):
    if kind == 'circle':
        return sf.ellipse(cx, cy, size, size)
    if kind == 'ellipse':
        return sf.ellipse(cx, cy, size * 1.6, size, rot)
    if kind == 'square':
        return sf.rect(cx, cy, 1.8 * size, 1.8 * size, rot)
    if kind == 'rect':
        return sf.rect(cx, cy, 2.6 * size, 1.4 * size, rot)
    if kind == 'triangle':
        return sf.triangle(cx, cy, 1.25 * size, rot)
    raise ValueError(kind)


TRUTH_CLS = {'circle': m.CLS_CIRCLE, 'ellipse': m.CLS_ELLIPSE, 'square': m.CLS_SQUARE,
             'rect': m.CLS_RECT, 'triangle': m.CLS_TRIANGLE}


def feats(e):
    A = e['A']
    c20 = A * e['Sxx'] - e['Sx'] * e['Sx']
    c02 = A * e['Syy'] - e['Sy'] * e['Sy']
    c11 = A * e['Sxy'] - e['Sx'] * e['Sy']
    aa = A * A
    m20 = (c20 << 8) // aa
    m02 = (c02 << 8) // aa
    m11 = (abs(c11) << 8) // aa
    det = m20 * m02 - m11 * m11
    j2 = ((det << 10) // aa) if det > 0 else 0
    qn = (m20 - m02) ** 2 + 4 * m11 * m11
    qd = max((m20 + m02) ** 2, 1)
    w = e['x1'] - e['x0'] + 1
    h = e['y1'] - e['y0'] + 1
    cvx = (e['R'] + e['T']) / (w + h)
    rho = (e['G'] / max(e['AD'], 1)) / max(e['SO'] / max(e['NO'], 1), 1)
    off_x = abs(2 * e['Sx'] - A * (e['x0'] + e['x1'])) / (A * w)
    off_y = abs(2 * e['Sy'] - A * (e['y0'] + e['y1'])) / (A * h)
    return dict(A=A, J2=j2, ASP2=qn * 1024 / qd, CVX=cvx, RHO=rho, W=w, H=h,
                OFF=max(off_x, off_y) * 64)


def run(out):
    os.makedirs(out, exist_ok=True)
    rng = np.random.default_rng(7)
    rows = []
    scenes = []
    # 1. shapes at decreasing size (distance), 6 per scene, two noise levels
    for noise, blur2 in ((6.0, False), (12.0, True)):
        for size in (6, 8, 10, 13, 16, 22, 32, 45):
            for kind in TRUTH_CLS:
                rots = [r(a) for a in (0, 17, 33, 52, 71, 88)]
                if size >= 32:
                    rots = rots[:3]
                shapes, truth = [], []
                step = 600 // len(rots)
                for i, rot in enumerate(rots):
                    cx = 30 + step // 2 + i * step
                    cy = 180
                    shapes.append(make_shapes(kind, size, cx, cy, rot))
                    truth.append((kind, cx, cy))
                scenes.append(('%s s%d n%d%s' % (kind, size, noise, ' soft' if blur2 else ''),
                               shapes, truth, noise, blur2, None))
    # 2. clutter scenes, several seeds each
    for kind in ('texture', 'fine_texture', 'shadows', 'strokes', 'objects', 'text'):
        for seed in range(4):
            bg = clutter_background(kind, np.random.default_rng(100 + seed))
            scenes.append(('clutter %s #%d' % (kind, seed), [], [], 8.0, False, bg))
    # 3. shapes on a cluttered background (paper sheet in a messy scene)
    for seed in range(4):
        bg = clutter_background('texture', np.random.default_rng(200 + seed))
        Y, X = np.mgrid[0:H, 0:W]
        paper = (np.abs(X - 320) < 170) & (np.abs(Y - 180) < 110)
        bg = np.where(paper, 255.0, bg)
        shapes = [make_shapes('circle', 30, 230, 150, 0), make_shapes('square', 22, 400, 150, r(20)),
                  make_shapes('triangle', 26, 320, 230, r(10))]
        truth = [('circle', 230, 150), ('square', 400, 150), ('triangle', 320, 230)]
        scenes.append(('paper on texture #%d' % seed, shapes, truth, 8.0, False, bg))

    for name, shapes, truth, noise, blur2, bg in scenes:
        if bg is None:
            gray = render(shapes, noise, blur2, rng)
        else:
            gray = render(shapes, noise, blur2, rng, background=bg) if shapes else \
                np.clip(np.round(median3(bg + rng.normal(0, noise, bg.shape))), 0, 255).astype(int)
        thr = min(max(m.threshold_from_sum(int(gray.sum())), 30), 200)
        labels, pairs = m.label_frame(gray.tolist(), thr)
        roots = m.resolve(labels, pairs)
        for lab in roots:
            e = labels[lab]
            if e['A'] < 100 or e['flags']:
                continue
            f = feats(e)
            cx = (e['x0'] + e['x1']) / 2
            cy = (e['y0'] + e['y1']) / 2
            t = 'clutter'
            for kind, tx, ty in truth:
                if abs(cx - tx) <= f['W'] / 2 and abs(cy - ty) <= f['H'] / 2:
                    t = kind
            f.update(scene=name, truth=t, old=m.CLS_NAME[m.classify(e) if e['A'] >= 600 else 0],
                     e=e)
            rows.append(f)
    return rows


def new_class(f, e, a_min, cvx_max, rho_max, asp_max=1e9, sym_max=1e9):
    """Candidate rule set: old bands + area >= a_min + convexity + contrast,
    aspect limit, and centroid at the box centre for the symmetric classes."""
    if a_min == 'hw':
        return m.classify(e)             # the rule set built into the hardware
    if f['A'] < a_min or f['A'] > m.A_MAX:
        return m.CLS_NONE
    if f['CVX'] > cvx_max or f['RHO'] > rho_max or f['ASP2'] > asp_max:
        return m.CLS_NONE
    saved = m.A_MIN, m.clutter_ok, m.ASP_MAX, m.SYM_SHIFT
    m.A_MIN, m.clutter_ok, m.ASP_MAX, m.SYM_SHIFT = a_min, (lambda e: True), 1 << 40, 0
    c = m.classify(e)
    m.A_MIN, m.clutter_ok, m.ASP_MAX, m.SYM_SHIFT = saved
    if c in (m.CLS_CIRCLE, m.CLS_ELLIPSE, m.CLS_SQUARE, m.CLS_RECT) and f['OFF'] > sym_max:
        return m.CLS_NONE
    return c


def report(rows, out):
    with open(os.path.join(out, 'shape_features.csv'), 'w') as fh:
        fh.write('scene,truth,A,W,H,J2,ASP2,CVX,RHO,OFF64,old_class\n')
        for f in rows:
            fh.write('%s,%s,%d,%d,%d,%d,%.2f,%.3f,%.3f,%.2f,%s\n' % (
                f['scene'], f['truth'], f['A'], f['W'], f['H'], f['J2'], f['ASP2'],
                f['CVX'], f['RHO'], f['OFF'], f['old']))
    lines = []
    shp = [f for f in rows if f['truth'] != 'clutter']
    clu = [f for f in rows if f['truth'] == 'clutter']
    lines.append('candidates: %d on shapes, %d clutter' % (len(shp), len(clu)))
    lines.append('CVX  shapes: max %.3f  p99 %.3f | clutter: min %.3f median %.3f' % (
        max(f['CVX'] for f in shp), np.percentile([f['CVX'] for f in shp], 99),
        min(f['CVX'] for f in clu), np.median([f['CVX'] for f in clu])))
    lines.append('RHO  shapes: max %.3f  p99 %.3f | clutter: min %.3f median %.3f' % (
        max(f['RHO'] for f in shp), np.percentile([f['RHO'] for f in shp], 99),
        min(f['RHO'] for f in clu), np.median([f['RHO'] for f in clu])))
    settings = [('old (A>=600, no filters)', 600, 99, 99, 1e9, 1e9),
                ('A>=150, no filters', 150, 99, 99, 1e9, 1e9),
                ('A>=150, RHO<=0.45', 150, 99, 0.45, 1e9, 1e9),
                ('A>=150, ASP<=3.5', 150, 99, 99, 740, 1e9),
                ('A>=150, SYM<=4/64', 150, 99, 99, 1e9, 4),
                ('A>=150, CVX<=1.5', 150, 1.5, 99, 1e9, 1e9),
                ('A>=150, all: CVX<=1.5 RHO<=0.45 ASP<=3.5 SYM<=4/64', 150, 1.5, 0.45, 740, 4),
                ('A>=150, all: CVX<=1.5 RHO<=0.40 ASP<=3.5 SYM<=3/64', 150, 1.5, 0.40, 740, 3),
                ('A>=200, all: CVX<=1.5 RHO<=0.45 ASP<=3.5 SYM<=4/64', 200, 1.5, 0.45, 740, 4),
                ('HARDWARE rule set (shape_ccl_model.classify)', 'hw', 0, 0, 0, 0)]
    sizes = sorted({int(f['scene'].split(' s')[1].split()[0]) for f in shp if ' s' in f['scene']})
    for label, a_min, cvx_max, rho_max, asp_max, sym_max in settings:
        lines.append('')
        lines.append('== ' + label)
        fp = sum(1 for f in clu if new_class(f, f['e'], a_min, cvx_max, rho_max, asp_max, sym_max) != m.CLS_NONE)
        lines.append('   false detections in clutter: %d (of %d candidates)' % (fp, len(clu)))
        hdr = '   size ' + ' '.join('%9s' % k for k in TRUTH_CLS)
        for noise in ('n6', 'n12 soft'):
            lines.append('   correct / placed, %s' % noise)
            lines.append(hdr)
            for s in sizes:
                cells = []
                for k in TRUTH_CLS:
                    scene = '%s s%d %s' % (k, s, noise)
                    got = [f for f in shp if f['scene'] == scene]
                    placed = 3 if s >= 32 else 6
                    ok = sum(1 for f in got if new_class(f, f['e'], a_min, cvx_max, rho_max, asp_max, sym_max) == TRUTH_CLS[k])
                    cells.append('%5d/%d' % (ok, placed))
                lines.append('   %4d ' % s + ' '.join('%9s' % c for c in cells))
        pot = [f for f in shp if f['scene'].startswith('paper')]
        ok = sum(1 for f in pot if new_class(f, f['e'], a_min, cvx_max, rho_max, asp_max, sym_max) == TRUTH_CLS[f['truth']])
        lines.append('   paper-on-texture shapes correct: %d/%d' % (ok, 12))
    txt = '\n'.join(lines)
    with open(os.path.join(out, 'shape_study.txt'), 'w') as fh:
        fh.write(txt + '\n')
    print(txt)


if __name__ == '__main__':
    out = sys.argv[1]
    report(run(out), out)

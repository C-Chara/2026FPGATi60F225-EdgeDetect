"""Bit-exact reference model of src/edge/shape_ccl.v + shape_classify.v.

Input: 640 x 360 gray samples (every second pixel of every second row).
Foreground: gray < threshold. One raster pass labels 4-connected regions
(a run inherits the label of the first run above it that it touches; when it
touches a second, different label the object is marked as merged and is not
classified). Per label: area, sums of x, y, x^2, y^2, xy, bounding box and
flags. After the frame each clean label is classified from
    J^2 = det(central second moments) / A^4  and the moment aspect ratio.
Usage as a library (classify_frame) or as a script (renders test pages).
"""
import math

W, H = 640, 360
MAX_LABELS = 1023
MAX_OBJECTS = 32
A_MIN, A_MAX = 150, 100000

CLS_NONE, CLS_CIRCLE, CLS_ELLIPSE, CLS_SQUARE, CLS_RECT, CLS_TRIANGLE = 0, 1, 2, 3, 4, 5
CLS_NAME = {0: '-', 1: 'circle', 2: 'ellipse', 3: 'square', 4: 'rect', 5: 'triangle'}

# Thresholds on J^2 * 2^26 (J = sqrt(det)/A^2): ellipse 1/(4pi)=0.0796,
# rectangle 1/12=0.0833, triangle 0.0962.
K_ELLIPSE_MAX = 432723     # J <= 0.0803
K_RECT_MIN = 452340        # J >= 0.0821
K_RECT_MAX = 484861        # J <= 0.0850
K_TRI_MIN = 543582         # J >= 0.0900
K_TRI_MAX = 640000         # J <= 0.0977 (digitized triangles stay below 0.0962)
Q_ROUND = 13               # aspect <= ~1.12: Qn * 1024 <= Qd * 13


def threshold_from_sum(gray_sum):
    """0.6 x mean gray: gray_sum * 175 >> 26 (640*360 samples)."""
    return (gray_sum * 175) >> 26


MAX_PAIRS = 1023
OUTER = 2                  # surrounding sample: 2 samples left of each run start
# Clutter rejection (tools/models/shape_robust_study.py, docs/sim_data):
RHO_NUM, RHO_DEN = 9, 20   # mean inside <= 0.45 x mean of the surrounding samples
CVX_NUM, CVX_DEN = 3, 2    # runs + top edges <= 1.5 x (width + height)
ASP_MAX = 740              # aspect <= ~3.5: Qn * 1024 <= Qd * 740
SYM_SHIFT = 4              # circle/ellipse/square/rect: centroid within 1/16
                           # of the box size from the box centre
TRI_OFF = 6                # triangle: centroid at least 6/64 off the box centre
# Fill of the bounding box, floor(64 * A / (w * h)): circle ~0.79, ellipse
# 0.67..0.84, triangle at most 0.5 (+ digitization)
FILL_CIRCLE = (47, 55)
FILL_ELLIPSE = (42, 55)
FILL_TRIANGLE = (30, 39)


def label_frame(gray, thr):
    """Raster pass. Returns (labels, pairs): per-label partial stats and the
    list of (a, b) label pairs found to belong to the same object."""
    labels = {}              # label -> dict of stats
    pairs = []
    last_pair = None
    next_label = 1
    lb_prev = [0] * W        # run id + 1 of the run above (0 = background)
    prt = [0] * 330          # previous-row run id -> label
    for y in range(H):
        lb_cur = [0] * W
        crt = [0] * 330
        run_id = 0
        in_run = False
        for x in range(W + 1):
            fg = x < W and gray[y][x] < thr
            up = 0
            if x < W and lb_prev[x]:
                up = prt[lb_prev[x] - 1]
            if fg:
                if not in_run:
                    in_run = True
                    x0, run_label = x, 0
                    n = sx = sxx = sg = tops = 0
                if up:
                    if run_label == 0:
                        run_label = up
                    elif up != run_label and (run_label, up) != last_pair:
                        last_pair = (run_label, up)
                        if len(pairs) < MAX_PAIRS:
                            pairs.append(last_pair)
                n += 1
                sx += x
                sxx += x * x
                sg += gray[y][x]
                if y == 0 or not lb_prev[x]:
                    tops += 1                     # top boundary of this sample
                lb_cur[x] = run_id + 1
            elif in_run:
                in_run = False
                x1 = x - 1
                lab = run_label
                if lab == 0:
                    if next_label <= MAX_LABELS:
                        lab = next_label
                        next_label += 1
                        labels[lab] = dict(A=0, Sx=0, Sy=0, Sxx=0, Syy=0, Sxy=0,
                                           G=0, T=0, R=0, SO=0, NO=0,
                                           x0=x0, x1=x1, y0=y, y1=y, flags=0)
                if lab:
                    e = labels[lab]
                    if x0 == 0 or x1 == W - 1 or y == 0 or y == H - 1:
                        e['flags'] |= 1           # touches the border
                    e['A'] += n
                    e['Sx'] += sx
                    e['Sy'] += n * y
                    e['Sxx'] += sxx
                    e['Syy'] += n * y * y
                    e['Sxy'] += y * sx
                    e['G'] += sg
                    e['T'] += tops
                    e['R'] += 1
                    # surrounding brightness: the sample OUTER left of the run
                    if x0 >= OUTER:
                        e['SO'] += gray[y][x0 - OUTER]
                        e['NO'] += 1
                    e['x0'] = min(e['x0'], x0)
                    e['x1'] = max(e['x1'], x1)
                    e['y0'] = min(e['y0'], y)
                    e['y1'] = max(e['y1'], y)
                crt[run_id] = lab
                run_id += 1
        lb_prev, prt = lb_cur, crt
    return labels, pairs


def resolve(labels, pairs):
    """Union the label pairs (parent always the smaller label), then fold every
    label into its parent from the highest label down. Returns root labels."""
    n = max(labels) + 1 if labels else 1
    parent = list(range(n))

    def find(a):
        while parent[a] != a:
            a = parent[a]
        return a
    for a, b in pairs:
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[max(ra, rb)] = min(ra, rb)
    for lab in range(n - 1, 0, -1):
        p = parent[lab]
        if p != lab and lab in labels and p in labels:
            c, e = labels[lab], labels[p]
            for k in ('A', 'Sx', 'Sy', 'Sxx', 'Syy', 'Sxy', 'G', 'T', 'R', 'SO', 'NO'):
                e[k] += c[k]
            e['x0'] = min(e['x0'], c['x0'])
            e['x1'] = max(e['x1'], c['x1'])
            e['y0'] = min(e['y0'], c['y0'])
            e['y1'] = max(e['y1'], c['y1'])
            e['flags'] |= c['flags']
    return [lab for lab in sorted(labels) if parent[lab] == lab]


def clutter_ok(e):
    """Ink on paper: dark against bright surroundings, convex without holes."""
    w = e['x1'] - e['x0'] + 1
    h = e['y1'] - e['y0'] + 1
    if e['NO'] == 0:
        return False
    if RHO_DEN * e['G'] * e['NO'] > RHO_NUM * e['SO'] * e['A']:
        return False
    return CVX_DEN * (e['R'] + e['T']) <= CVX_NUM * (w + h)


def classify(e):
    A = e['A']
    if not (A_MIN <= A <= A_MAX) or e['flags'] or not clutter_ok(e):
        return CLS_NONE
    c20 = A * e['Sxx'] - e['Sx'] * e['Sx']
    c02 = A * e['Syy'] - e['Sy'] * e['Sy']
    c11 = A * e['Sxy'] - e['Sx'] * e['Sy']
    aa = A * A
    m20 = (c20 << 8) // aa
    m02 = (c02 << 8) // aa
    m11 = (abs(c11) << 8) // aa
    det = m20 * m02 - m11 * m11
    if det <= 0:
        return CLS_NONE
    lhs = det << 10                      # det * 1024 vs A^2 * K
    qn = (m20 - m02) ** 2 + 4 * m11 * m11
    qd = (m20 + m02) ** 2
    rounder = (qn << 10) <= qd * Q_ROUND
    if (qn << 10) > qd * ASP_MAX:
        return CLS_NONE                  # strokes, cables, frame edges
    # centroid offset from the box centre (2*A*|centroid - centre|)
    off_x = abs(2 * e['Sx'] - A * (e['x0'] + e['x1']))
    off_y = abs(2 * e['Sy'] - A * (e['y0'] + e['y1']))
    wx = A * (e['x1'] - e['x0'] + 1)
    wy = A * (e['y1'] - e['y0'] + 1)
    centred = off_x <= wx >> SYM_SHIFT and off_y <= wy >> SYM_SHIFT
    fill = (A << 6) // ((e['x1'] - e['x0'] + 1) * (e['y1'] - e['y0'] + 1))
    if lhs <= aa * K_ELLIPSE_MAX:
        lo, hi = FILL_CIRCLE if rounder else FILL_ELLIPSE
        if not centred or not lo <= fill <= hi:
            return CLS_NONE
        return CLS_CIRCLE if rounder else CLS_ELLIPSE
    if aa * K_RECT_MIN <= lhs <= aa * K_RECT_MAX:
        if not centred:
            return CLS_NONE
        return CLS_SQUARE if rounder else CLS_RECT
    if aa * K_TRI_MIN <= lhs <= aa * K_TRI_MAX:
        # triangles are not centrally symmetric: centroid off the box centre
        asym = off_x >= (TRI_OFF * wx) >> 6 or off_y >= (TRI_OFF * wy) >> 6
        if FILL_TRIANGLE[0] <= fill <= FILL_TRIANGLE[1] and asym:
            return CLS_TRIANGLE
    return CLS_NONE


def classify_frame(gray, thr):
    labels, pairs = label_frame(gray, thr)
    roots = resolve(labels, pairs)
    objs = []
    for lab in roots:
        c = classify(labels[lab])
        if c != CLS_NONE and len(objs) < MAX_OBJECTS:
            e = labels[lab]
            objs.append((c, e['x0'], e['x1'], e['y0'], e['y1']))
    return objs, labels


if __name__ == '__main__':
    import sys
    sys.path.insert(0, __file__.rsplit('\\', 1)[0].rsplit('/', 1)[0])
    import numpy as np
    import shape_features as sf

    def page(shapes):
        def f(X, Y):
            m = np.zeros_like(X, bool)
            for s in shapes:
                m |= s(X, Y)
            return m
        return f

    def checker(x0, y0, cols, rows, s):
        def f(X, Y):
            cx = np.floor((X - x0) / s)
            cy = np.floor((Y - y0) / s)
            inside = (cx >= 0) & (cx < cols) & (cy >= 0) & (cy < rows)
            return inside & (((cx + cy) % 2) == 0)
        return f

    r = math.radians
    tests = {
        'p2 circle': page([sf.ellipse(320, 180, 60, 60)]),
        'p3 rect': page([sf.rect(320, 180, 240, 160)]),
        'p3 rect rot25': page([sf.rect(320, 180, 240, 160, r(25))]),
        'p4 circle+square rot15': page([sf.ellipse(200, 180, 56, 56), sf.rect(430, 180, 140, 140, r(15))]),
        'p5 ellipse+rounded': page([sf.ellipse(190, 180, 100, 50), sf.rounded(430, 180, 200, 140, 40)]),
        'triangle rot10 + tilted circle': page([sf.triangle(200, 190, 80, r(10)), sf.ellipse(450, 180, 66, 60, r(40))]),
        'p6 checkerboard': page([checker(95, 30, 9, 6, 50)]),
    }
    for name, f in tests.items():
        img = sf.render(f)
        gray = np.clip(np.round(img), 0, 255).astype(int)
        thr = threshold_from_sum(int(gray.sum()))
        objs, labels = classify_frame(gray.tolist(), thr)
        summary = {}
        for o in objs:
            summary[CLS_NAME[o[0]]] = summary.get(CLS_NAME[o[0]], 0) + 1
        print('%-32s thr=%3d labels=%3d objects=%s' % (name, thr, len(labels), summary)); [print('      ', CLS_NAME[o[0]], o[1:]) for o in objs[:6]]

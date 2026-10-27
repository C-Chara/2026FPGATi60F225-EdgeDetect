"""Digit recognition study: grid templates matched by Hamming distance.

Digits are rendered from TrueType fonts into 640 x 360 scenes (paper 210,
ink 70, blur, noise, 3x3 median as the hardware sees it), the CCL model
finds the candidates (objects that are not shapes, dark against their
surroundings, taller than wide), each candidate box is cut into a GW x GH
grid of dark/light cells (dark: at least half the samples below the local
threshold) and compared with templates rendered from Arial Bold
(cells within 0.3..0.7 coverage are "don't care").

Usage: digit_study.py <out_dir>   (writes digit_study.txt)
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shape_ccl_model as m          # noqa: E402
import shape_robust_study as st      # noqa: E402
from ttf_glyph import Font, inside   # noqa: E402

FONTS = {'arialbd': r'C:\Windows\Fonts\arialbd.ttf',
         'arial': r'C:\Windows\Fonts\arial.ttf',
         'bahnschrift': r'C:\Windows\Fonts\bahnschrift.ttf'}
W, H = 640, 360
DMAX = 8                       # at most 8 of the cared cells may differ


def glyph_mask(font, ch, X, Y, cx, cy, height, rot):
    polys = font.contours(ch)
    allp = np.array([p for poly in polys for p in poly])
    x0, y0 = allp.min(axis=0)
    x1, y1 = allp.max(axis=0)
    s = (y1 - y0) / height                     # font units per sample
    c, sn = math.cos(rot), math.sin(rot)
    u = (X - cx) * c + (Y - cy) * sn
    v = -(X - cx) * sn + (Y - cy) * c
    fx = (x0 + x1) / 2 + u * s
    fy = (y0 + y1) / 2 - v * s                 # font y is up
    return inside(polys, fx, fy)


def render(masks_fn, rng, noise=6.0):
    ss = 2
    ys, xs = np.mgrid[0:H * ss, 0:W * ss]
    X, Y = (xs + 0.5) / ss, (ys + 0.5) / ss
    cov = masks_fn(X, Y).astype(float).reshape(H, ss, W, ss).mean(axis=(1, 3))
    img = 210 - 140 * cov
    k = np.array([1, 2, 1], float) / 4
    for ax in (0, 1):
        img = np.apply_along_axis(lambda q: np.convolve(np.pad(q, 1, mode='edge'), k, 'valid'), ax, img)
    img += rng.normal(0, noise, img.shape)
    return np.clip(np.round(st.median3(img)), 0, 255).astype(int)


ROTS = (-8, 0, 8)


def templates(gw, gh, font_name='arialbd', rots=ROTS):
    """Per (digit, rotation): (bits, care) over gw*gh cells of the glyph's ink
    box (coverage >= 0.5 is dark; 0.3..0.7 is don't care)."""
    f = Font(FONTS[font_name])
    out = {}
    n = 300
    Y, X = np.mgrid[0:n, 0:n] + 0.5
    for d in '0123456789':
        for rot in rots:
            mk = glyph_mask(f, d, X, Y, n / 2, n / 2, n * 0.6, math.radians(rot))
            ys, xs = np.nonzero(mk)
            x0, x1, y0, y1 = xs.min(), xs.max() + 1, ys.min(), ys.max() + 1
            bits, care = [], []
            for j in range(gh):
                for i in range(gw):
                    a0 = x0 + (x1 - x0) * i // gw
                    a1 = x0 + (x1 - x0) * (i + 1) // gw
                    b0 = y0 + (y1 - y0) * j // gh
                    b1 = y0 + (y1 - y0) * (j + 1) // gh
                    cv = mk[b0:b1, a0:a1].mean()
                    bits.append(cv >= 0.5)
                    care.append(abs(cv - 0.5) > 0.2)
            out[(d, rot)] = (np.array(bits), np.array(care), (y1 - y0) / (x1 - x0))
    return out


def candidates(gray):
    """CCL model objects that may be digits: not a shape, ink on paper,
    taller than wide."""
    thr = min(max(m.threshold_from_sum(int(gray.sum())), 30), 200)
    labels, pairs = m.label_frame(gray.tolist(), thr)
    roots = m.resolve(labels, pairs)
    D = m.light_map(gray.tolist())
    out = []
    for lab in roots:
        e = labels[lab]
        if m.digit_candidate(e):          # same rule as the hardware (any count)
            out.append((e, thr))
    return out, D


def grid_bits(gray, e, thr, D, gw, gh):
    x0, x1, y0, y1 = e['x0'], e['x1'], e['y0'], e['y1']
    w, h = x1 - x0 + 1, y1 - y0 + 1
    kw, kh = (gw << 16) // w, (gh << 16) // h
    dark = np.zeros(gw * gh, int)
    tot = np.zeros(gw * gh, int)
    for y in range(y0, y1 + 1):
        cy = ((y - y0) * kh) >> 16
        for x in range(x0, x1 + 1):
            cx = ((x - x0) * kw) >> 16
            t = m.local_threshold(D[y // m.BH][x // m.BW], thr)
            k = cy * gw + cx
            tot[k] += 1
            dark[k] += gray[y][x] < t
    return 2 * dark >= tot, h, w


def classify(bits, h, w, tm, dmax):
    # best distance per digit (over its rotated templates)
    per = {}
    for (d, rot), (tb, tc, asp) in tm.items():
        dist = int(np.sum((bits != tb) & tc))
        per[d] = min(per.get(d, 99), dist)
    best = sorted((v, d) for d, v in per.items())
    (d1, c1), (d2, c2) = best[0], best[1]
    if d1 > dmax or d2 - d1 < 2:
        return None
    return c1


def run(out):
    os.makedirs(out, exist_ok=True)
    rng = np.random.default_rng(5)
    lines = []
    grids = [(7, 9)]
    tms = {g: templates(*g) for g in grids}
    stats = {g: {} for g in grids}
    for fname in ('arialbd', 'arial', 'bahnschrift'):
        f = Font(FONTS[fname])
        for height in (20, 28, 40, 60):
            for rot_deg in (0, -10, 10):
                digits = '1234567890'
                step = 600 // len(digits)
                if height * 0.8 > step:
                    digits = digits[:5] if rot_deg <= 0 else digits[5:]
                    step = 600 // len(digits)
                places = [(20 + step // 2 + i * step, 180, d) for i, d in enumerate(digits)]

                def masks(X, Y, places=places):
                    mk = np.zeros(X.shape, bool)
                    for cx, cy, d in places:
                        near = (np.abs(X - cx) < height) & (np.abs(Y - cy) < height)
                        if near.any():
                            sub = glyph_mask(f, d, X[near], Y[near], cx, cy, height, math.radians(rot_deg))
                            mk[near] |= sub
                    return mk
                gray = render(masks, rng)
                cands, D = candidates(gray)
                for g in grids:
                    s = stats[g].setdefault((fname, height), [0, 0, 0])
                    for cx, cy, d in places:
                        if d == '0':
                            continue
                        s[1] += 1
                        hit = [c for c in cands if c[0]['x0'] <= cx <= c[0]['x1'] and c[0]['y0'] <= cy <= c[0]['y1']]
                        if hit:
                            bits, h, w = grid_bits(gray, hit[0][0], hit[0][1], D, *g)
                            r = classify(bits, h, w, tms[g], dmax=DMAX)
                            if r == d:
                                s[0] += 1
                            elif r is not None:
                                s[2] += 1
    for g in grids:
        lines.append('grid %dx%d: correct / placed (wrong)' % g)
        for fname in ('arialbd', 'arial', 'bahnschrift'):
            row = []
            for height in (20, 28, 40, 60):
                c, n, wr = stats[g][(fname, height)]
                row.append('%2d/%2d(%d)' % (c, n, wr))
            lines.append('  %-12s h=20/28/40/60: ' % fname + ' '.join(row))
    # clutter: digit false positives in the shape study's clutter scenes
    for g in grids:
        fp = 0
        for kind in ('texture', 'fine_texture', 'shadows', 'strokes', 'objects', 'text'):
            for seed in range(2):
                bg = st.clutter_background(kind, np.random.default_rng(100 + seed))
                gray = np.clip(np.round(st.median3(bg + rng.normal(0, 8.0, bg.shape))), 0, 255).astype(int)
                cands, D = candidates(gray)
                for e, thr in cands:
                    bits, h, w = grid_bits(gray, e, thr, D, *g)
                    r = classify(bits, h, w, tms[g], dmax=DMAX)
                    if r not in (None, '0'):
                        fp += 1
        lines.append('grid %dx%d: false digits in 12 clutter scenes: %d' % (g + (fp,)))
    txt = '\n'.join(lines)
    open(os.path.join(out, 'digit_study.txt'), 'w').write(txt + '\n')
    print(txt)


if __name__ == '__main__':
    run(sys.argv[1])

"""Test image and expected result for sim/tb_digits.v (detector + digit_reader).

Usage: gen_digit_tb_data.py <case> <out_dir>
Writes <out_dir>/shape_img.hex (1280 x 720) and <out_dir>/digit_expected.txt:
'slots n', then per slot 'slot i x0 x1 y0 y1 digit' (digit 15 = none).
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import digit_study as ds             # noqa: E402
import shape_ccl_model as m          # noqa: E402
import shape_robust_study as st      # noqa: E402
from ttf_glyph import Font           # noqa: E402

CASES = {
    # digits, height, rotations, extra shapes
    '4739': ('4739', 40, (0, 5, -6, 3), True),
    '2026': ('2026', 30, (0, 0, 0, 0), False),
}


def main(case, out):
    os.makedirs(out, exist_ok=True)
    digits, height, rots, shape = CASES[case]
    f = Font(ds.FONTS['arialbd'])
    step = 480 // len(digits)
    places = [(80 + step // 2 + i * step, 200, d, rots[i]) for i, d in enumerate(digits)]

    def masks(X, Y):
        mk = np.zeros(X.shape, bool)
        for cx, cy, d, rot in places:
            near = (np.abs(X - cx) < height) & (np.abs(Y - cy) < height)
            mk[near] |= ds.glyph_mask(f, d, X[near], Y[near], cx, cy, height, math.radians(rot))
        if shape:                                   # a circle: a shape, no digit
            mk |= (X - 300) ** 2 + (Y - 80) ** 2 <= 35 ** 2
        return mk
    gray = ds.render(masks, np.random.default_rng(9))
    full = np.repeat(np.repeat(gray, 2, axis=0), 2, axis=1)
    with open(os.path.join(out, 'shape_img.hex'), 'w') as fh:
        fh.write('\n'.join('%02x' % v for v in full.flatten()) + '\n')
    thr = min(max(m.threshold_from_sum(int(gray.sum())), 30), 200)
    labels, pairs = m.label_frame(gray.tolist(), thr)
    roots = m.resolve(labels, pairs)
    boxes = m.digit_list(labels, roots)
    D = m.light_map(gray.tolist())
    tm = ds.templates(7, 9)
    lines = ['slots %d' % len(boxes)]
    for i, (x0, x1, y0, y1) in enumerate(boxes):
        e = dict(x0=x0, x1=x1, y0=y0, y1=y1)
        bits, h, w = ds.grid_bits(gray, e, thr, D, 7, 9)
        r = ds.classify(bits, h, w, tm, dmax=ds.DMAX)
        dg = 15 if r in (None, '0') else int(r)
        lines.append('slot %d %d %d %d %d %d' % (i, x0, x1, y0, y1, dg))
    objs, _ = m.classify_frame(gray.tolist(), thr)
    open(os.path.join(out, 'digit_expected.txt'), 'w').write('\n'.join(lines) + '\n')
    print(case, 'threshold', thr, '| shapes', [m.CLS_NAME[o[0]] for o in objs], '|', ' / '.join(lines))


if __name__ == '__main__':
    main(sys.argv[1], sys.argv[2])

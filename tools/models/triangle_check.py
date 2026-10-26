"""Why checkerboard squares became 'triangles', and a symmetry test to stop it.

Two checkerboard squares that touch at a corner (merged by blur) form a
centrally symmetric 'bow tie'. Triangles are the only class here without
central symmetry, so their centroid is away from the bounding-box centre.
D = max(|cx - bx| / width, |cy - by| / height).
"""
import math
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import shape_features as sf   # noqa: E402


def feats(mask):
    ys, xs = np.nonzero(mask)
    A, J, asp, _ = sf.features(mask)
    cx, cy = xs.mean(), ys.mean()
    bx, by = (xs.min() + xs.max()) / 2, (ys.min() + ys.max()) / 2
    D = max(abs(cx - bx) / (xs.max() - xs.min() + 1), abs(cy - by) / (ys.max() - ys.min() + 1))
    return J, asp, D


def bowtie(s, bridge):
    # two squares touching at a corner, joined by a bridge of `bridge` pixels
    def f(X, Y):
        a = (X >= 320 - s) & (X < 320) & (Y >= 180 - s) & (Y < 180)
        b = (X >= 320) & (X < 320 + s) & (Y >= 180) & (Y < 180 + s)
        c = (np.abs(X - 320) < bridge) & (np.abs(Y - 180) < bridge)
        return a | b | c
    return f


r = math.radians
cases = [('triangle rot%d' % a, sf.triangle(320, 180, 60, r(a))) for a in range(0, 120, 5)]
cases += [('triangle small rot%d' % a, sf.triangle(320, 180, 30, r(a))) for a in (0, 15, 45)]
cases += [('square rot%d' % a, sf.rect(320, 180, 90, 90, r(a))) for a in (0, 20, 45)]
cases += [('circle', sf.ellipse(320, 180, 60, 60)), ('ellipse', sf.ellipse(320, 180, 90, 50, r(30))),
          ('rounded rect', sf.rounded(320, 180, 100, 70, 20))]
cases += [('bowtie bridge %d' % b, bowtie(50, b)) for b in (2, 5, 10, 15)]
print('%-24s %7s %6s %6s' % ('shape', 'J', 'ASP', 'D'))
for name, f in cases:
    img = sf.render(f)
    J, asp, D = feats(img < 120)
    print('%-24s %7.4f %6.2f %6.3f' % (name, J, asp, D))

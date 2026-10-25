"""Feature study for the connected-component shape classifier.

Renders filled shapes at 640x360 (the classifier works on every second pixel
of every second row), adds blur and sensor noise, thresholds, and computes
the rotation-invariant features the hardware will use:
  J   = sqrt(mu20*mu02 - mu11^2) / A^2   (1/(4 pi)=0.0796 ellipse, 1/12=0.0833
                                          rectangle, 0.0962 equilateral triangle)
  ASP = sqrt(lambda1/lambda2)            (moment aspect ratio)
  F2  = max/min of the support widths in 8 directions (22.5 deg steps)
"""
import math
import numpy as np

W, H = 640, 360
rng = np.random.default_rng(3)


def render(inside, ss=4, blur=True, noise=6.0):
    ys, xs = np.mgrid[0:H * ss, 0:W * ss]
    m = inside((xs + 0.5) / ss, (ys + 0.5) / ss).astype(float)
    cov = m.reshape(H, ss, W, ss).mean(axis=(1, 3))
    img = 215 - 185 * cov
    if blur:
        k = np.array([1, 2, 1], float) / 4
        img = np.apply_along_axis(lambda r: np.convolve(np.pad(r, 1, mode='edge'), k, 'valid'), 1, img)
        img = np.apply_along_axis(lambda c: np.convolve(np.pad(c, 1, mode='edge'), k, 'valid'), 0, img)
    img += rng.normal(0, noise, img.shape)
    return img


def features(mask):
    ys, xs = np.nonzero(mask)
    A = len(xs)
    x = xs.astype(float)
    y = ys.astype(float)
    mx, my = x.mean(), y.mean()
    m20 = ((x - mx) ** 2).sum() / A
    m02 = ((y - my) ** 2).sum() / A
    m11 = ((x - mx) * (y - my)).sum() / A
    det = m20 * m02 - m11 ** 2
    J = math.sqrt(det) / A
    tr = m20 + m02
    disc = math.sqrt(max((m20 - m02) ** 2 + 4 * m11 ** 2, 0))
    asp = math.sqrt((tr + disc) / max(tr - disc, 1e-9))
    widths = []
    for k in range(8):
        t = k * math.pi / 8
        p = x * math.cos(t) + y * math.sin(t)
        widths.append(p.max() - p.min() + 1)
    F2 = max(widths) / min(widths)
    return A, J, asp, F2


def poly_inside(pts):
    def f(X, Y):
        inside = np.ones_like(X, bool)
        n = len(pts)
        for i in range(n):
            x0, y0 = pts[i]
            x1, y1 = pts[(i + 1) % n]
            inside &= (x1 - x0) * (Y - y0) - (y1 - y0) * (X - x0) >= 0
        return inside
    return f


def rot_pts(pts, cx, cy, a):
    c, s = math.cos(a), math.sin(a)
    return [(cx + px * c - py * s, cy + px * s + py * c) for px, py in pts]


def ellipse(cx, cy, a, b, rot=0.0):
    c, s = math.cos(rot), math.sin(rot)
    return lambda X, Y: (((X - cx) * c + (Y - cy) * s) / a) ** 2 + ((-(X - cx) * s + (Y - cy) * c) / b) ** 2 <= 1


def rect(cx, cy, w, h, rot=0.0):
    pts = [(-w / 2, -h / 2), (w / 2, -h / 2), (w / 2, h / 2), (-w / 2, h / 2)]
    return poly_inside(rot_pts(pts, cx, cy, rot))


def rounded(cx, cy, w, h, r, rot=0.0):
    c, s = math.cos(rot), math.sin(rot)

    def f(X, Y):
        u = np.abs((X - cx) * c + (Y - cy) * s) - (w / 2 - r)
        v = np.abs(-(X - cx) * s + (Y - cy) * c) - (h / 2 - r)
        return np.hypot(np.maximum(u, 0), np.maximum(v, 0)) <= r
    return f


def triangle(cx, cy, r, rot=0.0):
    pts = [(r * math.cos(a), r * math.sin(a)) for a in (-math.pi / 2, math.pi / 6, 5 * math.pi / 6)]
    return poly_inside(rot_pts(pts, cx, cy, rot))


cases = []
for r in (25, 45, 65):
    cases.append(('circle r%d' % r, ellipse(320, 180, r, r)))
for q in (1.1, 1.2, 1.3, 1.5, 2.0):
    cases.append(('ellipse %.1f rot30' % q, ellipse(320, 180, 55 * q, 55, math.radians(30))))
for a in (0, 11, 22, 33, 45):
    cases.append(('square 90 rot%d' % a, rect(320, 180, 90, 90, math.radians(a))))
for a in (0, 15, 30):
    cases.append(('rect 120x80 rot%d' % a, rect(320, 180, 120, 80, math.radians(a))))
    cases.append(('rect 140x50 rot%d' % a, rect(320, 180, 140, 50, math.radians(a))))
cases.append(('square 50 rot20', rect(320, 180, 50, 50, math.radians(20))))
for a in (0, 20, 45):
    cases.append(('triangle r60 rot%d' % a, triangle(320, 180, 60, math.radians(a))))
cases.append(('rounded 100x70 r20', rounded(320, 180, 100, 70, 20)))
cases.append(('rounded 100x70 r20 rot25', rounded(320, 180, 100, 70, 20, math.radians(25))))
cases.append(('rounded sq 90 r20', rounded(320, 180, 90, 90, 20)))
cases.append(('rounded sq 90 r30', rounded(320, 180, 90, 90, 30)))

print('%-26s %6s %7s %6s %6s' % ('shape', 'A', 'J', 'ASP', 'F2'))
for name, f in cases:
    img = render(f)
    mask = img < 120
    A, J, asp, F2 = features(mask)
    print('%-26s %6d %7.4f %6.2f %6.2f' % (name, A, J, asp, F2))

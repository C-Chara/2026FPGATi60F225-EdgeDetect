"""Reference model and test data for src/edge/raw_demosaic.v.

gen <out_dir> <phase>  : writes raw_img.hex (Bayer mosaic of a colour test
                          picture, 1280x720) and raw_expected.hex (RGB565 the
                          RTL must produce for the first frame: gains 1.0,
                          gamma on).
check <out_dir>        : compares raw_rtl.hex with raw_expected.hex.
"""
import math
import os
import sys

W, H = 1280, 720


def gamma(v):
    return min(4 * v, round(255 * (v / 255) ** (1 / 2.2)))


def picture():
    img = [[(0, 0, 0)] * W for _ in range(H)]
    bars = [(255, 255, 255), (255, 255, 0), (0, 255, 255), (0, 255, 0),
            (255, 0, 255), (255, 0, 0), (0, 0, 255), (40, 40, 40)]
    for y in range(H):
        row = []
        for x in range(W):
            if y < 300:
                c = bars[x * len(bars) // W]
            elif y < 420:
                v = x * 255 // (W - 1)
                c = (v, v, v)
            else:
                # a red disc and a blue square on white, a green triangle
                c = (230, 230, 230)
                if (x - 300) ** 2 + (y - 570) ** 2 < 110 ** 2:
                    c = (200, 30, 30)
                if 560 <= x < 760 and 480 <= y < 680:
                    c = (30, 40, 200)
                if y > 480 and abs(x - 1000) < (y - 480) * 0.6 and y < 680:
                    c = (30, 180, 40)
            row.append(c)
        img[y] = row
    return img


def mosaic(img, phase):
    py, px = phase >> 1, phase & 1
    raw = [[0] * W for _ in range(H)]
    for y in range(H):
        for x in range(W):
            t = (((y + py) & 1) << 1) | ((x + px) & 1)
            r, g, b = img[y][x]
            raw[y][x] = r if t == 0 else (b if t == 3 else g)
    return raw


def demosaic(raw, phase):
    py, px = phase >> 1, phase & 1
    out = []
    for y in range(H):
        for x in range(W):
            e = raw[y][x]
            d = raw[y][x - 1] if x > 0 else e
            b = raw[y - 1][x] if y > 0 else e
            if y == 0:
                a = d
            elif x == 0:
                a = b
            else:
                a = raw[y - 1][x - 1]
            t = (((y + py) & 1) << 1) | ((x + px) & 1)
            if t == 0:
                r, bb, g = e, a, (b + d) >> 1
            elif t == 3:
                bb, r, g = e, a, (b + d) >> 1
            elif t == 1:
                r, bb, g = d, b, (e + a) >> 1
            else:
                bb, r, g = d, b, (e + a) >> 1
            ro, go, bo = gamma(r), gamma(g), gamma(bb)
            out.append(((ro >> 3) << 11) | ((go >> 2) << 5) | (bo >> 3))
    return out


if __name__ == '__main__':
    cmd, out = sys.argv[1], sys.argv[2]
    if cmd == 'gen':
        phase = int(sys.argv[3])
        raw = mosaic(picture(), phase)
        with open(os.path.join(out, 'raw_img.hex'), 'w') as f:
            f.write('\n'.join('%02x' % v for row in raw for v in row) + '\n')
        exp = demosaic(raw, phase)
        with open(os.path.join(out, 'raw_expected.hex'), 'w') as f:
            f.write('\n'.join('%04x' % v for v in exp) + '\n')
        print('generated phase', phase)
    else:
        exp = [l.strip() for l in open(os.path.join(out, 'raw_expected.hex')) if l.strip()]
        got = [l.strip() for l in open(os.path.join(out, 'raw_rtl.hex')) if l.strip()]
        n = min(len(exp), len(got))
        bad = [i for i in range(n) if exp[i] != got[i]]
        print('pixels expected %d rtl %d mismatches %d' % (len(exp), len(got), len(bad)))
        for i in bad[:5]:
            print('  at x=%d y=%d expected %s got %s' % (i % W, i // W, exp[i], got[i]))

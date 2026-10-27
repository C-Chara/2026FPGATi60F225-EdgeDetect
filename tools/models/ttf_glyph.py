"""Minimal TrueType outline reader (cmap format 4, loca, glyf; simple glyphs)
and a polygon rasterizer, used to render digit templates and test images
without PIL.

glyph_polygons(font_path, char) -> (list of contours [(x, y), ...] in font
units with y up, advance width, units per em). Quadratic curves are
flattened to line segments.
"""
import struct

import numpy as np


class Font:
    def __init__(self, path):
        self.d = open(path, 'rb').read()
        n = struct.unpack('>H', self.d[4:6])[0]
        self.t = {}
        for i in range(n):
            tag, _, off, ln = struct.unpack('>4sIII', self.d[12 + 16 * i:28 + 16 * i])
            self.t[tag.decode('latin-1')] = (off, ln)
        head = self.t['head'][0]
        self.upem = struct.unpack('>H', self.d[head + 18:head + 20])[0]
        self.loca_long = struct.unpack('>h', self.d[head + 50:head + 52])[0] == 1
        self.cmap = self._cmap()

    def _cmap(self):
        off = self.t['cmap'][0]
        n = struct.unpack('>H', self.d[off + 2:off + 4])[0]
        for i in range(n):
            pid, eid, sub = struct.unpack('>HHI', self.d[off + 4 + 8 * i:off + 12 + 8 * i])
            so = off + sub
            if struct.unpack('>H', self.d[so:so + 2])[0] == 4 and pid in (0, 3):
                seg2 = struct.unpack('>H', self.d[so + 6:so + 8])[0]
                seg = seg2 // 2
                p = so + 14
                ends = struct.unpack('>%dH' % seg, self.d[p:p + seg2]); p += seg2 + 2
                starts = struct.unpack('>%dH' % seg, self.d[p:p + seg2]); p += seg2
                deltas = struct.unpack('>%dh' % seg, self.d[p:p + seg2]); p += seg2
                ro_pos = p
                ros = struct.unpack('>%dH' % seg, self.d[p:p + seg2])
                m = {}
                for k in range(seg):
                    for c in range(starts[k], ends[k] + 1):
                        if c == 0xFFFF:
                            continue
                        if ros[k] == 0:
                            g = (c + deltas[k]) & 0xFFFF
                        else:
                            a = ro_pos + 2 * k + ros[k] + 2 * (c - starts[k])
                            g = struct.unpack('>H', self.d[a:a + 2])[0]
                            if g:
                                g = (g + deltas[k]) & 0xFFFF
                        m[c] = g
                return m
        raise ValueError('no cmap format 4')

    def _glyph_off(self, g):
        lo = self.t['loca'][0]
        if self.loca_long:
            a, b = struct.unpack('>II', self.d[lo + 4 * g:lo + 4 * g + 8])
        else:
            a, b = struct.unpack('>HH', self.d[lo + 2 * g:lo + 2 * g + 4])
            a, b = 2 * a, 2 * b
        return self.t['glyf'][0] + a, b - a

    def contours(self, ch, steps=8):
        off, ln = self._glyph_off(self.cmap[ord(ch)])
        if ln == 0:
            return []
        nc = struct.unpack('>h', self.d[off:off + 2])[0]
        assert nc >= 0, 'composite glyphs not supported'
        p = off + 10
        ends = struct.unpack('>%dH' % nc, self.d[p:p + 2 * nc]); p += 2 * nc
        il = struct.unpack('>H', self.d[p:p + 2])[0]; p += 2 + il
        npts = ends[-1] + 1
        flags = []
        while len(flags) < npts:
            f = self.d[p]; p += 1
            flags.append(f)
            if f & 8:
                r = self.d[p]; p += 1
                flags += [f] * r
        def coords(short_bit, same_bit):
            nonlocal p
            v, out = 0, []
            for f in flags:
                if f & short_bit:
                    dv = self.d[p]; p += 1
                    v += dv if f & same_bit else -dv
                elif not f & same_bit:
                    v += struct.unpack('>h', self.d[p:p + 2])[0]; p += 2
                out.append(v)
            return out
        xs = coords(2, 16)
        ys = coords(4, 32)
        polys, s = [], 0
        for e in ends:
            pts = [(xs[i], ys[i], flags[i] & 1) for i in range(s, e + 1)]
            s = e + 1
            # expand implied on-curve points
            full = []
            for i, q in enumerate(pts):
                n_ = pts[(i + 1) % len(pts)]
                full.append(q)
                if not q[2] and not n_[2]:
                    full.append(((q[0] + n_[0]) / 2, (q[1] + n_[1]) / 2, 1))
            k0 = next(i for i, q in enumerate(full) if q[2])
            full = full[k0:] + full[:k0]
            poly = []
            i = 0
            while i < len(full):
                a = full[i]
                b = full[(i + 1) % len(full)]
                if b[2]:
                    poly.append((a[0], a[1])); i += 1
                else:
                    c = full[(i + 2) % len(full)]
                    for t in np.linspace(0, 1, steps, endpoint=False):
                        poly.append(((1 - t) ** 2 * a[0] + 2 * t * (1 - t) * b[0] + t * t * c[0],
                                     (1 - t) ** 2 * a[1] + 2 * t * (1 - t) * b[1] + t * t * c[1]))
                    i += 2
            polys.append(poly)
        return polys


def inside(polys, X, Y):
    """Non-zero winding test for arrays of points (font units)."""
    wn = np.zeros(X.shape, int)
    for poly in polys:
        P = np.array(poly)
        A, B = P, np.roll(P, -1, axis=0)
        for (x0, y0), (x1, y1) in zip(A, B):
            up = (y0 <= Y) & (y1 > Y)
            dn = (y0 > Y) & (y1 <= Y)
            cr = (x1 - x0) * (Y - y0) - (X - x0) * (y1 - y0)
            wn += np.where(up & (cr > 0), 1, 0) - np.where(dn & (cr < 0), 1, 0)
    return wn != 0

"""Convert a 1280x720 RRGGBB hex dump (one pixel per line) to PNG (no PIL)."""
import struct
import sys
import zlib

src, dst = sys.argv[1], sys.argv[2]
W, H = 1280, 720
scale = int(sys.argv[3]) if len(sys.argv) > 3 else 2
px = [int(l, 16) for l in open(src) if l.strip()][:W * H]
px += [0] * (W * H - len(px))
w, h = W // scale, H // scale
raw = bytearray()
for y in range(h):
    raw.append(0)
    row = px[(y * scale) * W:(y * scale + 1) * W]
    for x in range(w):
        v = row[x * scale]
        raw += bytes(((v >> 16) & 255, (v >> 8) & 255, v & 255))


def chunk(t, d):
    c = struct.pack('>I', len(d)) + t + d
    return c + struct.pack('>I', zlib.crc32(t + d) & 0xffffffff)


png = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('>IIBBBBB', w, h, 8, 2, 0, 0, 0))
png += chunk(b'IDAT', zlib.compress(bytes(raw), 6)) + chunk(b'IEND', b'')
open(dst, 'wb').write(png)
print('wrote', dst, w, 'x', h)

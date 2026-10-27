"""Bit-exact reference model of src/edge/shape_tracker.v (cross-frame voting).

Every detector result (one list of {cls, x0, x1, y0, y1} per analysed frame)
updates up to N tracks:
  match   a detection belongs to the nearest unmatched track whose box centre
          lies within half the larger box size (|2*dcx| <= max w, same in y)
          and whose size is within a factor of 2 (2*|dw| <= max w, same in h).
  update  the box follows the detection. The shown class changes only after
          SWITCH consecutive detections of the same new class.
  new     an unmatched detection starts a track in the first free slot.
  age     a track missed MISS_MAX + 1 times in a row is dropped; until then
          it keeps its last box (no blinking on a single missed frame).
  show    a track is shown once it was detected SHOW times (one-frame
          false detections never appear).
Output order: track slot order.

Usage as a script: shape_tracker_model.py <out_dir> writes the testbench
input sequence, the expected outputs and a stability report.
"""
import os
import random
import sys

N = 32
SHOW = 2
SWITCH = 3
MISS_MAX = 2


class Tracker:
    def __init__(self):
        self.t = [dict(valid=False, box=(0, 0, 0, 0), cls=0, cand=0, ccnt=0, hits=0, miss=0)
                  for _ in range(N)]

    def update(self, dets):
        matched = [False] * N
        for cls, x0, x1, y0, y1 in dets:
            dcx, dcy = x0 + x1, y0 + y1
            dw, dh = x1 - x0 + 1, y1 - y0 + 1
            found = free = None
            best = 0
            for j, t in enumerate(self.t):
                if t['valid'] and not matched[j]:
                    tx0, tx1, ty0, ty1 = t['box']
                    tw, th = tx1 - tx0 + 1, ty1 - ty0 + 1
                    ex, ey = abs(dcx - (tx0 + tx1)), abs(dcy - (ty0 + ty1))
                    if ex <= max(dw, tw) and ey <= max(dh, th) and \
                            2 * abs(dw - tw) <= max(dw, tw) and 2 * abs(dh - th) <= max(dh, th) and \
                            (found is None or ex + ey < best):
                        found, best = j, ex + ey
                if not t['valid'] and free is None:
                    free = j
            if found is not None:
                t = self.t[found]
                t['box'] = (x0, x1, y0, y1)
                if cls == t['cls']:
                    t['cand'], t['ccnt'] = cls, 0
                elif cls == t['cand']:
                    t['ccnt'] += 1
                    if t['ccnt'] >= SWITCH:
                        t['cls'], t['ccnt'] = cls, 0
                else:
                    t['cand'], t['ccnt'] = cls, 1
                t['hits'] = min(t['hits'] + 1, 3)
                t['miss'] = 0
                matched[found] = True
            elif free is not None:
                self.t[free] = dict(valid=True, box=(x0, x1, y0, y1), cls=cls, cand=cls,
                                    ccnt=0, hits=1, miss=0)
                matched[free] = True
        for j, t in enumerate(self.t):
            if t['valid'] and not matched[j]:
                if t['miss'] >= MISS_MAX:
                    t['valid'], t['hits'], t['miss'] = False, 0, 0
                else:
                    t['miss'] += 1
        return [(t['cls'],) + t['box'] for t in self.t if t['valid'] and t['hits'] >= SHOW]


def scenario(seed=5, updates=80):
    """Noisy detector output: what the board shows today without voting."""
    rng = random.Random(seed)
    seq = []
    for k in range(updates):
        dets = []
        # A: circle near the circle/ellipse boundary, flips 30% of the time
        dets.append((2 if rng.random() < 0.3 else 1, 100, 140, 80, 120))
        # B: square moving right 3 samples per update, flips to rect 15%
        x = 200 + 3 * k
        dets.append((4 if rng.random() < 0.15 else 3, x, x + 40, 150, 190))
        # C: triangle missed 1 in 4 analyses
        if rng.random() > 0.25:
            dets.append((5, 400, 450, 60, 110))
        # D: a large ellipse near the bottom, stable
        dets.append((2, 300, 380, 260, 300))
        # clutter: a one-update false detection now and then
        if rng.random() < 0.3:
            fx, fy = rng.randrange(20, 600), rng.randrange(20, 330)
            dets.append((rng.choice([3, 4, 5]), fx, fx + 15, fy, fy + 15))
        # E: appears at update 40 and leaves at 60
        if 40 <= k < 60:
            dets.append((1, 520, 560, 220, 260))
        rng.shuffle(dets)
        seq.append(dets)
    return seq


def main(out):
    os.makedirs(out, exist_ok=True)
    seq = scenario()
    tr = Tracker()
    outs = [tr.update(d) for d in seq]
    with open(os.path.join(out, 'tracker_in.txt'), 'w') as fh:
        for d in seq:
            fh.write('%d\n' % len(d))
            for o in d:
                fh.write('%d %d %d %d %d\n' % o)
    with open(os.path.join(out, 'tracker_expected.txt'), 'w') as fh:
        for k, o in enumerate(outs):
            fh.write('update %d count %d\n' % (k, len(o)))
            for x in o:
                fh.write('obj %d %d %d %d %d\n' % x)

    # stability report: label changes and false detections, raw vs voted
    def near(o, cx, cy):
        return abs((o[1] + o[2]) / 2 - cx) < 25 and abs((o[3] + o[4]) / 2 - cy) < 25

    def track_of(name, k):
        return {'A circle': (120, 100), 'B square (moving)': (220 + 3 * k, 170),
                'C triangle (25% missed)': (425, 85), 'D ellipse': (340, 280)}[name]
    lines = ['%-26s %22s %22s' % ('object', 'raw detector', 'with voting'),
             '%-26s %11s %10s %11s %10s' % ('', 'changes', 'missing', 'changes', 'missing')]
    for name in ('A circle', 'B square (moving)', 'C triangle (25% missed)', 'D ellipse'):
        res = []
        for lists in (seq, outs):
            prev, changes, missing = None, 0, 0
            for k, lst in enumerate(lists):
                cx, cy = track_of(name, k)
                hit = [o for o in lst if near(o, cx, cy)]
                c = hit[0][0] if hit else None
                if c is None:
                    missing += 1
                elif prev is not None and c != prev:
                    changes += 1
                if c is not None:
                    prev = c
            res += [changes, missing]
        lines.append('%-26s %11d %10d %11d %10d' % (name, *res))
    false_raw = sum(1 for lst in seq for o in lst if o[2] - o[1] == 15)
    false_vot = sum(1 for lst in outs for o in lst if o[2] - o[1] == 15)
    lines.append('one-update false detections shown: raw %d, with voting %d' % (false_raw, false_vot))
    e_first = next(k for k, lst in enumerate(outs) if any(near(o, 540, 240) for o in lst))
    e_last = max(k for k, lst in enumerate(outs) if any(near(o, 540, 240) for o in lst))
    lines.append('E (present in updates 40..59): shown %d..%d' % (e_first, e_last))
    txt = '\n'.join(lines)
    with open(os.path.join(out, 'tracker_study.txt'), 'w') as fh:
        fh.write(txt + '\n')
    print(txt)


if __name__ == '__main__':
    main(sys.argv[1])

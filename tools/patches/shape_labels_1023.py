"""Raise the shape detector's label and merge-pair tables from 255 to 1023.

With 255 labels a cluttered or noisy scene (RAW 60 fps) used up every label
above the objects: shapes lower in the frame got none and vanished, and
objects whose pairs no longer fit were split (partial outline, class
flicker). Labels are 10 bits now; counters 11 bits."""
import io
import sys

ROOT = sys.argv[1]
p = ROOT + '/src/edge/shape_detector.v'
raw = io.open(p, newline='', encoding='utf-8').read()
crlf = '\r\n' in raw
s = raw.replace('\r\n', '\n')

pairs = [
    ("    reg [7:0]  run_q;\n", "    reg [9:0]  run_q;\n", 1),
    ("    reg [7:0]  run_ram [0:1023];\n", "    reg [9:0]  run_ram [0:1023];\n", 1),
    ("    reg [7:0]  runw_data;\n", "    reg [9:0]  runw_data;\n", 1),
    ("    wire [7:0] up_label = (s2_lb != 0 && srow != 0) ? run_q : 8'd0;\n",
     "    wire [9:0] up_label = (s2_lb != 0 && srow != 0) ? run_q : 10'd0;\n", 1),
    ("    reg [7:0]  run_label;\n", "    reg [9:0]  run_label;\n", 1),
    ("    reg [15:0] last_pair;\n", "    reg [19:0] last_pair;\n", 1),
    ("    reg [7:0]  ev_label;\n", "    reg [9:0]  ev_label;\n", 1),
    ("    reg [7:0]  up_lab;\n", "    reg [9:0]  up_lab;\n", 1),
    ("    reg [8:0]  next_label;     // next free label, 256 = full\n",
     "    reg [10:0] next_label;     // next free label, 1024 = full\n", 1),
    ("    reg [8:0]  npairs;\n", "    reg [10:0] npairs;\n", 1),
    ("    reg [8:0]  pidx;\n", "    reg [10:0] pidx;\n", 1),
    ("    reg [7:0]  fa, fb, fcur, ra, fpar;\n", "    reg [9:0]  fa, fb, fcur, ra, fpar;\n", 1),
    ("    reg  [SWID-1:0] stats_ram [0:255];\n", "    reg  [SWID-1:0] stats_ram [0:1023];\n", 1),
    ("    reg  [7:0]      stats_waddr;\n", "    reg  [9:0]      stats_waddr;\n", 1),
    ("    wire [7:0]      stats_raddr", "    wire [9:0]      stats_raddr", 1),
    ("    reg  [15:0] pair_ram [0:255];\n    reg  [15:0] pair_q;\n",
     "    reg  [19:0] pair_ram [0:1023];\n    reg  [19:0] pair_q;\n", 1),
    ("    reg  [7:0]  pair_waddr;\n    reg  [15:0] pair_wdata;\n",
     "    reg  [9:0]  pair_waddr;\n    reg  [19:0] pair_wdata;\n", 1),
    ("    reg  [7:0] parent_ram [0:255];\n    reg  [7:0] parent_q;\n",
     "    reg  [9:0] parent_ram [0:1023];\n    reg  [9:0] parent_q;\n", 1),
    ("    reg  [7:0] parent_waddr, parent_wdata;\n    wire [7:0] parent_raddr",
     "    reg  [9:0] parent_waddr, parent_wdata;\n    wire [9:0] parent_raddr", 1),
    ("pidx[7:0]", "pidx[9:0]", 7),
    ("npairs < 9'd256", "npairs < 11'd1024", 1),
    ("pair_waddr <= npairs[7:0];", "pair_waddr <= npairs[9:0];", 1),
    ("npairs <= npairs + 9'd1;", "npairs <= npairs + 11'd1;", 1),
    ("next_label <= 9'd1;", "next_label <= 11'd1;", 2),
    ("next_label <= 9'd255", "next_label <= 11'd1023", 1),
    ("next_label[7:0]", "next_label[9:0]", 2),
    ("next_label <= next_label + 9'd1;", "next_label <= next_label + 11'd1;", 1),
    ("pidx == 9'd255", "pidx == 11'd1023", 1),
    ("pidx + 9'd1", "pidx + 11'd1", 4),
    ("pidx - 9'd1", "pidx - 11'd1", 2),
    ("pidx <= 9'd1;", "pidx <= 11'd1;", 1),
    ("next_label - 9'd1", "next_label - 11'd1", 1),
    ("pair_q[15:8]", "pair_q[19:10]", 2),
    ("fb <= pair_q[7:0];", "fb <= pair_q[9:0];", 1),
]
for old, new, n in pairs:
    assert s.count(old) == n, (old, s.count(old))
    s = s.replace(old, new)
io.open(p, 'w', newline='').write(s.replace('\n', '\r\n') if crlf else s)

m = ROOT + '/tools/models/shape_ccl_model.py'
t = io.open(m, encoding='utf-8').read()
for old, new in (("MAX_LABELS = 255\n", "MAX_LABELS = 1023\n"), ("MAX_PAIRS = 255\n", "MAX_PAIRS = 1023\n")):
    assert t.count(old) == 1, old
    t = t.replace(old, new)
io.open(m, 'w', encoding='utf-8').write(t)
print('ok')

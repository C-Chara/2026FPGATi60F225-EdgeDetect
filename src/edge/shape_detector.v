`timescale 1ns/1ps

// Multi-object shape recognition by connected components and moments.
// Reference model: tools/models/shape_ccl_model.py (same integer arithmetic).
//
// Frames alternate between SCAN and PROCESS (the 30 fps camera shows every
// image twice at 60 Hz, so this is one analysis per camera frame):
//   SCAN    every second pixel of every second row (640 x 360) is compared
//           with an automatic threshold (0.6 x mean gray of the previous
//           scanned frame); light gaps of 1-2 samples inside a row are
//           closed. Runs of dark samples are labelled 4-connected:
//           a run takes the label of the first run above it; when it also
//           touches another label the pair is stored and merged later.
//           Each label accumulates area, sums of x, y, x^2, y^2, xy, its
//           bounding box and a border flag, and for clutter rejection the
//           sum of its gray, its run and top-edge counts and the gray of the
//           sample four left of its first run in each row (its surroundings).
//   PROCESS union of the stored pairs, folding of every merged label into
//           its parent (highest label first), then classification of every
//           root from J^2 = det(second central moments) / A^4 (ellipse
//           0.0796^2, rectangle 0.0833^2, triangle 0.0962^2) and the moment
//           aspect ratio (round below about 1.12). Rejected as clutter:
//           mean gray above 0.65 x the surroundings (not ink on paper),
//           aspect above about 3.5 (strokes), and for the
//           symmetric classes a centroid more than 1/16 of the box size off
//           the box centre. Study: tools/models/shape_robust_study.py.
// Results: up to MAX_OBJECTS objects, published at the end of PROCESS.
module shape_detector #(
    parameter integer MAX_OBJECTS = 32,
    parameter integer A_MIN = 150,
    parameter integer A_MAX = 100000,
    parameter LOCAL_THR = 1'b1,          // 0: one threshold for the whole frame
    parameter integer A_DIG = 60,        // digit candidates may be smaller
    parameter integer A_TRI = 320,       // triangles: small ones are clutter (dots, letters)
    parameter integer MAX_DIGITS = 4
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        vsync_n,        // low during vertical sync
    input  wire        de,             // 1280 pixels per row, 720 rows
    input  wire [7:0]  gray,
    output reg  [5:0]  obj_count,
    // per object {cls[2:0], x0[9:0], x1[9:0], y0[8:0], y1[8:0]}, half resolution
    output reg  [MAX_OBJECTS*41-1:0] obj_data,
    // Per object (entry k = obj_data entry k), for the overlay's colouring,
    // read from a RAM (registered, one clock): mom_q = entry mom_raddr =
    // {cx4[11:0], cy4[10:0], ka[17:0], kb_neg, kb[17:0], kc[17:0]}: the
    // centroid in quarter samples (4 x Sx / A) and the inverse second-moment
    // matrix, ka = m02 * 2^28 / det, kb = 2 * |m11| * 2^28 / det (sign kb_neg),
    // kc = m20 * 2^28 / det (det = m20 * m02 - m11^2; saturated to 18 bits).
    input  wire [4:0]  mom_raddr,
    output reg  [77:0] mom_q,
    output reg  [7:0]  threshold,
    output reg         obj_strobe,     // one clock: obj_count / obj_data are new
    // Debug readout of the largest candidate of the last analysis (area in
    // samples, 100 x inside/outside gray, 100 x (runs+tops)/(w+h), J^2*2^16,
    // fill/64, reject bits: 0 unused, 1 contrast, 2 aspect, 3 no J band,
    // 4 off-centre, 5 fill, 6 triangle symmetric; 0 = accepted)
    output reg  [17:0] dbg_area,
    output reg  [9:0]  dbg_rho, dbg_cvx, dbg_j,
    output reg  [6:0]  dbg_fill, dbg_why,
    // Digit candidates of the last analysis (objects that are no shape, ink
    // on paper, 1.25 <= h/w <= 6, h >= 12): {x0, x1, y0, y1}, raster order.
    output reg  [2:0]  dig_count,
    output reg  [MAX_DIGITS*38-1:0] dig_data,
    // The sample stream with its local-threshold decision, every frame
    output wire        smp_v,
    output wire [9:0]  smp_x,
    output wire [8:0]  smp_y,
    output wire        smp_dark
);
    localparam integer SW = 640, SH = 360;
    localparam [2:0] CLS_NONE = 3'd0, CLS_CIRCLE = 3'd1, CLS_ELLIPSE = 3'd2,
                     CLS_SQUARE = 3'd3, CLS_RECT = 3'd4, CLS_TRIANGLE = 3'd5;
    // J^2 * 2^26 bands
    localparam [63:0] K_ELLIPSE_MAX = 64'd432723, K_RECT_MIN = 64'd452340,
                      K_RECT_MAX = 64'd484861, K_TRI_MIN = 64'd543582,
                      K_TRI_MAX = 64'd640000;
    // Fill of the bounding box, floor(64 * A / (w * h)): circle, ellipse, triangle
    localparam [63:0] FILL_C_MIN = 47, FILL_C_MAX = 55, FILL_E_MIN = 42, FILL_E_MAX = 55,
                      FILL_T_MIN = 30, FILL_T_MAX = 39;

    // ------------------------------------------------------------------
    // Label statistics word
    localparam integer WA = 18, WSX = 28, WSY = 27, WSXX = 37, WSYY = 35, WSXY = 36;
    localparam integer OA = 0, OSX = OA + WA, OSY = OSX + WSX, OSXX = OSY + WSY,
                       OSYY = OSXX + WSXX, OSXY = OSYY + WSYY, OX0 = OSXY + WSXY,
                       OX1 = OX0 + 10, OY0 = OX1 + 10, OY1 = OY0 + 9, OFL = OY1 + 9,
                       OG = OFL + 1, OT = OG + 26, ORN = OT + 18, OSO = ORN + 18,
                       ONO = OSO + 26, OAD = ONO + 18, SWID = OAD + 18;
    // OG gray sum, OT top-edge samples, ORN runs, OSO / ONO sum and count of
    // the surrounding samples (four left of the first run of each row), OAD
    // dark samples (OA also counts the filled holes)

    // ------------------------------------------------------------------
    // Input timing: full-resolution column / row counters
    reg [10:0] xf;
    reg [9:0]  yf;
    reg        de_d, vs_d;
    wire       vs_fall = vs_d && !vsync_n;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            xf <= 0; yf <= 0; de_d <= 0; vs_d <= 1;
        end else begin
            vs_d <= vsync_n;
            de_d <= de;
            if (!vsync_n) begin xf <= 0; yf <= 0; end
            else if (de) xf <= xf + 11'd1;
            else begin
                xf <= 0;
                if (de_d) yf <= yf + 10'd1;
            end
        end
    end
    reg        scanning;
    wire       sample = scanning && vsync_n && de && !xf[0] && !yf[0] && yf < 2*SH;
    wire [9:0] sx_now = xf[10:1];

    // ------------------------------------------------------------------
    // Scan pipeline: stage 0 reads lb[x] (run id + 1 of the run above),
    // stage 1 reads that run's label, stage 2 processes the sample.
    reg        s1_v, s2_v, s1_fg, s2_fg, s1_last, s2_last;
    reg [9:0]  s1_x, s2_x;
    reg [8:0]  lb_q, s2_lb;
    reg [9:0]  run_q;
    reg        row_bank;
    reg [8:0]  run_id;
    reg [8:0]  srow;
    reg [7:0]  thr_use;
    reg [7:0]  s1_gray, s2_gray, g_m1, g_m2, g_m3, g_m4;   // g_mk: sample x-k of stage 2

    // Local threshold (lens vignetting, uneven light). Every frame, per block
    // of 32 x 30 samples (20 x 12 blocks), the brightest min(g[x-1], g[x])
    // goes to light_m; in the vertical blanking light_d gets the maximum over
    // the 7 x 7 block neighbourhood. The threshold of a sample is
    // light_d * 141 / 256 (0.55 x the local paper white), within 0.5 .. 1.25 x
    // the global threshold (inside a large dark shape light_d is the ink).
    wire       lsample = vsync_n && de && !xf[0] && !yf[0] && yf < 2*SH;
    reg  [7:0] lprev;                     // previous sample of the row
    wire [7:0] lval = (sx_now == 0 || gray < lprev) ? gray : lprev;
    reg  [7:0] blk_max [0:19];            // maxima of the current block row
    reg  [4:0] row_in_blk;                // sampled row within the block row
    reg  [3:0] lby;                       // block row
    reg        blk_first;                 // first sampled row of a block row
    reg  [4:0] lwr;                       // copy of blk_max into light_m
    reg        lwr_on;
    reg  [7:0] light_m [0:511];
    reg  [7:0] light_d [0:511];
    integer    q;
    initial for (q = 0; q < 512; q = q + 1) light_d[q] = 8'd0;
    reg  [8:0] lm_raddr, ld_raddr, ld_waddr;
    reg  [7:0] lm_q, ld_q;
    reg        ld_we;
    reg  [7:0] ld_wdata;
    always @(posedge clk) begin
        if (lwr_on) light_m[{lby, lwr}] <= blk_max[lwr];
        lm_q <= light_m[lm_raddr];
        if (ld_we) light_d[ld_waddr] <= ld_wdata;
        ld_q <= light_d[ld_raddr];
    end
    // Dilation over the 7 x 7 block neighbourhood, one read per clock.
    reg        dil_on, dil_rv, dil_rv2;   // read issued / its data in lm_q
    reg  [3:0] dj; reg [4:0] di;          // target block
    reg  [2:0] nj, ni;                    // neighbour offset + 3
    reg  [7:0] dacc;
    reg        dil_last, dil_last_d;
    wire signed [5:0] tj = $signed({2'b0, dj}) + $signed({3'b0, nj}) - 6'sd3;
    wire signed [6:0] ti = $signed({2'b0, di}) + $signed({4'b0, ni}) - 7'sd3;
    wire       nb_ok = tj >= 0 && tj < 12 && ti >= 0 && ti < 20;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            lprev <= 0; row_in_blk <= 0; lby <= 0; blk_first <= 1; lwr <= 0; lwr_on <= 0;
            for (q = 0; q < 20; q = q + 1) blk_max[q] <= 0;
            lm_raddr <= 0; ld_waddr <= 0; ld_we <= 0; ld_wdata <= 0;
            dil_on <= 0; dil_rv <= 0; dil_rv2 <= 0; dj <= 0; di <= 0; nj <= 0; ni <= 0; dacc <= 0;
            dil_last <= 0; dil_last_d <= 0;
        end else begin
            ld_we <= 0;
            if (!vsync_n) begin
                row_in_blk <= 0; lby <= 0; blk_first <= 1; lwr_on <= 0;
            end else begin
                if (lsample) begin
                    lprev <= gray;
                    if ((blk_first && sx_now[4:0] == 0) || lval > blk_max[sx_now[9:5]])
                        blk_max[sx_now[9:5]] <= lval;
                    if (sx_now == SW-1) begin               // end of a sampled row
                        if (row_in_blk == 5'd29) begin
                            row_in_blk <= 0; lwr <= 0; lwr_on <= 1;
                        end else begin
                            row_in_blk <= row_in_blk + 5'd1;
                            blk_first <= 0;
                        end
                    end
                end
                if (lwr_on) begin                           // 20 writes, then next block row
                    if (lwr == 5'd19) begin
                        lwr_on <= 0; blk_first <= 1;
                        lby <= lby + 4'd1;
                        if (lby == 4'd11) begin             // frame done: dilate
                            dil_on <= 1; dj <= 0; di <= 0; nj <= 0; ni <= 0; dacc <= 0;
                        end
                    end else lwr <= lwr + 5'd1;
                end
            end
            // dilation: issue reads (lm_q one clock later), accumulate, write
            dil_rv <= dil_on && nb_ok;
            dil_rv2 <= dil_rv;
            dil_last_d <= dil_last;
            dil_last <= 0;
            if (dil_on) begin
                lm_raddr <= {tj[3:0], ti[4:0]};
                if (ni == 3'd6) begin
                    ni <= 0;
                    if (nj == 3'd6) begin nj <= 0; dil_last <= 1; dil_on <= 0; end
                    else nj <= nj + 3'd1;
                end else ni <= ni + 3'd1;
            end
            if (dil_rv2 && lm_q > dacc) dacc <= lm_q;
            if (dil_last_d) begin
                // the last read's data arrives with dil_last_d
                ld_we <= 1; ld_waddr <= {dj, di};
                ld_wdata <= (dil_rv2 && lm_q > dacc) ? lm_q : dacc;
                dacc <= 0;
                if (di == 5'd19) begin
                    di <= 0;
                    if (dj != 4'd11) begin dj <= dj + 4'd1; dil_on <= 1; end
                end else begin di <= di + 5'd1; dil_on <= 1; end
            end
        end
    end
    // Threshold for the sample three clocks later (address, RAM, register)
    wire [10:0] xa = xf + 11'd3;
    always @(posedge clk) ld_raddr <= {lby, xa[10:6]};
    reg  [7:0] thr_pix;
    wire [15:0] tmul = ld_q * 8'd141;
    wire [7:0]  t_lo = {1'b0, thr_use[7:1]};
    wire [8:0]  t_hi = thr_use + thr_use[7:2];
    always @(posedge clk) thr_pix <= LOCAL_THR ? ((tmul[15:8] < t_lo) ? t_lo :
                                                 ({1'b0, tmul[15:8]} > t_hi) ? t_hi[7:0] : tmul[15:8])
                                               : thr_use;

    assign smp_v = lsample;
    assign smp_x = sx_now;
    assign smp_y = yf[9:1];
    assign smp_dark = gray < thr_pix;

    // Gap closing (before stage 0): a light gap of one or two samples between
    // dark samples of the same row counts as dark, so printer streaks and
    // thin highlights do not cut a shape into slices. The decision for
    // sample x needs x+1 and x+2: samples pass a three-entry delay line (e2
    // oldest) and are emitted three samples late; after the last sample of a
    // row three empty entries push the line out, two clocks apart like samples.
    reg        e0_v, e1_v, e2_v, e0_fg, e1_fg, e2_fg, h1_fg, h2_fg;
    reg [7:0]  e0_g, e1_g, e2_g;
    reg [9:0]  e0_x, e1_x, e2_x;
    reg [2:0]  flush_cnt;
    wire       shift = sample || flush_cnt == 3'd5 || flush_cnt == 3'd3 || flush_cnt == 3'd1;
    wire       emit_v = shift && e2_v;
    wire       emit_fg = e2_fg || (h1_fg && (e1_fg || e0_fg)) || (h2_fg && e1_fg);
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            e0_v <= 0; e1_v <= 0; e2_v <= 0; e0_fg <= 0; e1_fg <= 0; e2_fg <= 0;
            h1_fg <= 0; h2_fg <= 0; e0_g <= 0; e1_g <= 0; e2_g <= 0;
            e0_x <= 0; e1_x <= 0; e2_x <= 0; flush_cnt <= 0;
        end else begin
            if (sample && sx_now == SW-1) flush_cnt <= 3'd6;
            else if (flush_cnt != 0) flush_cnt <= flush_cnt - 3'd1;
            if (shift) begin
                e2_v <= e1_v; e2_fg <= e1_fg; e2_g <= e1_g; e2_x <= e1_x;
                e1_v <= e0_v; e1_fg <= e0_fg; e1_g <= e0_g; e1_x <= e0_x;
                e0_v <= sample; e0_fg <= sample && gray < thr_pix;
                e0_g <= gray; e0_x <= sx_now;
                h1_fg <= e2_v && e2_fg;            // raw (unclosed) history
                h2_fg <= h1_fg;
            end
        end
    end

    reg [8:0]  lb_ram [0:SW-1];
    reg [9:0]  run_ram [0:1023];
    // run_ram write (label of a finished run of the current row)
    reg        runw_en;
    reg [9:0]  runw_addr;
    reg [9:0]  runw_data;
    always @(posedge clk) begin
        if (emit_v) lb_q <= lb_ram[e2_x];
        if (s2_v) lb_ram[s2_x] <= s2_fg ? run_id + 9'd1 : 9'd0;
        run_q <= run_ram[{!row_bank, lb_q - 9'd1}];
        if (runw_en) run_ram[runw_addr] <= runw_data;
    end
    wire [9:0] up_label = (s2_lb != 0 && srow != 0) ? run_q : 10'd0;
    wire       s2_top = (s2_lb == 0 || srow == 0);    // no foreground sample above

    reg        in_run;
    reg [9:0]  run_x0;
    reg [9:0]  run_label;
    reg [9:0]  run_n;
    reg [18:0] run_sx;
    reg [27:0] run_sxx;
    reg [17:0] run_sg;         // gray sum of the run
    reg [9:0]  run_top;        // samples without a foreground sample above
    reg [7:0]  run_so;         // surrounding sample (left of the run start)
    reg        run_no;         // run_so is valid (run starts at x >= 4)
    // Hole filling: light samples since the previous run ended in this row;
    // they join the next run if it has the same label as the previous one.
    reg        gap_ok;
    reg [9:0]  gap_n, run_gn, ev_gn;
    reg [18:0] gap_sx, run_gsx, ev_gsx;
    reg [27:0] gap_sxx, run_gsxx, ev_gsxx;
    reg [9:0]  row_prev_lab;   // label of the previous run in this row
    reg [9:0]  row_prev_n;     // and its length
    wire       hole_fill;      // the run continues the previous run's object
    reg [18:0] sq;             // x^2 of the stage-2 sample
    reg [19:0] last_pair;
    reg        rowend_1, rowend_2;

    // Run end event and statistics update
    reg        ev_v;
    reg [9:0]  ev_x0, ev_x1, ev_n;
    reg [18:0] ev_sx;
    reg [27:0] ev_sxx;
    reg [9:0]  ev_label;
    reg [8:0]  ev_y;
    reg [17:0] ev_sg;
    reg [9:0]  ev_top;
    reg [7:0]  ev_so;
    reg        ev_no;
    reg        up_v, up_new;
    reg [9:0]  up_x0, up_x1, up_n;
    reg [18:0] up_sx;
    reg [27:0] up_sxx;
    reg [17:0] up_sg;
    reg [9:0]  up_top;
    reg [7:0]  up_so;
    reg        up_no;
    reg [9:0]  up_lab;
    // only gaps no wider than the runs around them (not the inside of a ring);
    // decided one stage early, at the run end event (a run without a label
    // yet gets a new one and is never filled)
    assign     hole_fill = ev_label != 0 && ev_label == row_prev_lab &&
                           {ev_gn, 1'b0} <= {1'b0, row_prev_n} + ev_n;
    reg [9:0]  up_nf;          // run length including a filled gap
    reg [18:0] up_sxf;
    reg [27:0] up_sxxf;
    reg [8:0]  up_y;
    reg [10:0] next_label;     // next free label, 1024 = full
    reg [10:0] npairs;
    reg [25:0] gray_sum;

    // ------------------------------------------------------------------
    // Post-processing
    localparam [4:0] P_IDLE = 0, P_PINIT = 1, P_U_RD = 2, P_U_GOT = 3, P_U_FIND = 4,
                     P_U_FCHK = 5, P_F_RD = 6, P_F_CHK = 7, P_F_GOTC = 8, P_F_RDP = 9,
                     P_F_GOTP = 10, P_C_RD = 11, P_C_CHK = 12, P_C_GOT = 13,
                     P_C_MATH = 14, P_C_STORE = 15, P_DONE = 16, P_F_GAP = 17;
    reg [4:0]  pstate;
    reg        processing, post_done;
    reg [10:0] pidx;
    reg [9:0]  fa, fb, fcur, ra, fpar;
    reg        find_second;
    reg [SWID-1:0] child;

    // RAMs with combinational read address, registered data (valid next clock)
    reg  [SWID-1:0] stats_ram [0:1023];
    reg  [SWID-1:0] stats_q;
    reg             stats_we;
    reg  [9:0]      stats_waddr;
    reg  [SWID-1:0] stats_wdata;
    wire [9:0]      stats_raddr = scanning ? ev_label :
                                  (pstate == P_F_RDP) ? fpar : pidx[9:0];
    always @(posedge clk) begin
        stats_q <= stats_ram[stats_raddr];
        if (stats_we) stats_ram[stats_waddr] <= stats_wdata;
    end
    reg  [19:0] pair_ram [0:1023];
    reg  [19:0] pair_q;
    reg         pair_we;
    reg  [9:0]  pair_waddr;
    reg  [19:0] pair_wdata;
    always @(posedge clk) begin
        pair_q <= pair_ram[pidx[9:0]];
        if (pair_we) pair_ram[pair_waddr] <= pair_wdata;
    end
    reg  [9:0] parent_ram [0:1023];
    reg  [9:0] parent_q;
    reg        parent_we;
    reg  [9:0] parent_waddr, parent_wdata;
    wire [9:0] parent_raddr = (pstate == P_U_FIND) ? fcur : pidx[9:0];
    always @(posedge clk) begin
        parent_q <= parent_ram[parent_raddr];
        if (parent_we) parent_ram[parent_waddr] <= parent_wdata;
    end

    // New or updated statistics word for one run
    function [SWID-1:0] add_run;
        input [SWID-1:0] old;
        input            is_new;
        input [9:0]      x0, x1, n;
        input [18:0]     sxr;
        input [27:0]     sxxr;
        input [8:0]      y;
        input [17:0]     sgr;
        input [9:0]      topr;
        input [7:0]      sor;
        input            no_v;
        input [9:0]      dark;
        reg   [16:0]     ysq;
        reg              border;
        reg              first;
        begin
            ysq = y * y;
            border = (x0 == 0) || (x1 == SW-1) || (y == 0) || (y == SH-1);
            add_run = old;
            add_run[OA   +: WA  ] = (is_new ? 0 : old[OA   +: WA  ]) + n;
            add_run[OSX  +: WSX ] = (is_new ? 0 : old[OSX  +: WSX ]) + sxr;
            add_run[OSY  +: WSY ] = (is_new ? 0 : old[OSY  +: WSY ]) + n * y;
            add_run[OSXX +: WSXX] = (is_new ? 0 : old[OSXX +: WSXX]) + sxxr;
            add_run[OSYY +: WSYY] = (is_new ? 0 : old[OSYY +: WSYY]) + n * ysq;
            add_run[OSXY +: WSXY] = (is_new ? 0 : old[OSXY +: WSXY]) + y * sxr;
            add_run[OX0 +: 10] = (is_new || x0 < old[OX0 +: 10]) ? x0 : old[OX0 +: 10];
            add_run[OX1 +: 10] = (is_new || x1 > old[OX1 +: 10]) ? x1 : old[OX1 +: 10];
            add_run[OY0 +: 9]  = is_new ? y : old[OY0 +: 9];
            add_run[OY1 +: 9]  = y;
            add_run[OFL]       = (is_new ? 1'b0 : old[OFL]) | border;
            add_run[OG  +: 26] = (is_new ? 26'd0 : old[OG  +: 26]) + sgr;
            add_run[OT  +: 18] = (is_new ? 18'd0 : old[OT  +: 18]) + topr;
            add_run[ORN +: 18] = (is_new ? 18'd0 : old[ORN +: 18]) + 18'd1;
            // surroundings: only the object's first run in this row (OY1 = last row)
            first = is_new || old[OY1 +: 9] != y;
            add_run[OSO +: 26] = (is_new ? 26'd0 : old[OSO +: 26]) + ((no_v && first) ? sor : 8'd0);
            add_run[ONO +: 18] = (is_new ? 18'd0 : old[ONO +: 18]) + (no_v && first);
            add_run[OAD +: 18] = (is_new ? 18'd0 : old[OAD +: 18]) + dark;
        end
    endfunction
    // Child folded into its parent
    function [SWID-1:0] merge_stats;
        input [SWID-1:0] p, c;
        begin
            merge_stats = p;
            merge_stats[OA   +: WA  ] = p[OA   +: WA  ] + c[OA   +: WA  ];
            merge_stats[OSX  +: WSX ] = p[OSX  +: WSX ] + c[OSX  +: WSX ];
            merge_stats[OSY  +: WSY ] = p[OSY  +: WSY ] + c[OSY  +: WSY ];
            merge_stats[OSXX +: WSXX] = p[OSXX +: WSXX] + c[OSXX +: WSXX];
            merge_stats[OSYY +: WSYY] = p[OSYY +: WSYY] + c[OSYY +: WSYY];
            merge_stats[OSXY +: WSXY] = p[OSXY +: WSXY] + c[OSXY +: WSXY];
            merge_stats[OX0 +: 10] = (c[OX0 +: 10] < p[OX0 +: 10]) ? c[OX0 +: 10] : p[OX0 +: 10];
            merge_stats[OX1 +: 10] = (c[OX1 +: 10] > p[OX1 +: 10]) ? c[OX1 +: 10] : p[OX1 +: 10];
            merge_stats[OY0 +: 9]  = (c[OY0 +: 9]  < p[OY0 +: 9])  ? c[OY0 +: 9]  : p[OY0 +: 9];
            merge_stats[OY1 +: 9]  = (c[OY1 +: 9]  > p[OY1 +: 9])  ? c[OY1 +: 9]  : p[OY1 +: 9];
            merge_stats[OFL]       = p[OFL] | c[OFL];
            merge_stats[OG  +: 26] = p[OG  +: 26] + c[OG  +: 26];
            merge_stats[OT  +: 18] = p[OT  +: 18] + c[OT  +: 18];
            merge_stats[ORN +: 18] = p[ORN +: 18] + c[ORN +: 18];
            merge_stats[OSO +: 26] = p[OSO +: 26] + c[OSO +: 26];
            merge_stats[ONO +: 18] = p[ONO +: 18] + c[ONO +: 18];
            merge_stats[OAD +: 18] = p[OAD +: 18] + c[OAD +: 18];
        end
    endfunction

    // 64-bit sequential multiplier (stops when the multiplier is exhausted)
    // and restoring divider (64 steps).
    reg        mul_go, div_go;
    reg [63:0] op_a, op_b;
    reg [63:0] mul_acc, mul_a, mul_b;
    reg        mul_busy;
    reg [63:0] div_q, div_r, div_n, div_d;
    reg [6:0]  div_cnt;
    reg        div_busy;
    wire [63:0] div_shift = {div_r[62:0], div_n[63]};
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            mul_busy <= 0; div_busy <= 0; mul_acc <= 0; mul_a <= 0; mul_b <= 0;
            div_q <= 0; div_r <= 0; div_n <= 0; div_d <= 0; div_cnt <= 0;
        end else begin
            if (mul_go) begin
                mul_busy <= 1; mul_acc <= 0; mul_a <= op_a; mul_b <= op_b;
            end else if (mul_busy) begin
                if (mul_b == 0) mul_busy <= 0;
                else begin
                    if (mul_b[0]) mul_acc <= mul_acc + mul_a;
                    mul_a <= mul_a << 1;
                    mul_b <= mul_b >> 1;
                end
            end
            if (div_go) begin
                div_busy <= 1; div_q <= 0; div_r <= 0;
                div_n <= op_a; div_d <= op_b; div_cnt <= 7'd64;
            end else if (div_busy) begin
                if (div_cnt == 0) div_busy <= 0;
                else begin
                    if (div_shift >= div_d) begin
                        div_r <= div_shift - div_d;
                        div_q <= {div_q[62:0], 1'b1};
                    end else begin
                        div_r <= div_shift;
                        div_q <= {div_q[62:0], 1'b0};
                    end
                    div_n <= div_n << 1;
                    div_cnt <= div_cnt - 7'd1;
                end
            end
        end
    end
    wire alu_busy = mul_busy || div_busy || mul_go || div_go;

    reg [63:0] cA, cSx, cSy, cSxx, cSyy, cSxy;
    reg [63:0] t1, c20, c02, c11, aa, m20, m02, m11, p1, p2, j2, dd, qd;
    reg [40:0] cbox;
    // Triangle symmetry test: A*(x0+x1), A*(y0+y1), A*width, A*height
    reg [63:0] t_bx, t_by, t_wx, t_wy;
    reg [4:0]  cstep;
    reg        cwait;
    reg [2:0]  cls;
    reg [5:0]  pend_count;
    reg [MAX_OBJECTS*41-1:0] pend_data;
    // Moments: two banks of 32 entries; the published bank is read, the
    // other is written during PROCESS and becomes published at P_DONE.
    reg [77:0] mom_ram [0:63];
    reg        mom_pub, mom_we;
    reg [5:0]  mom_waddr;
    reg [77:0] mom_wdata;
    always @(posedge clk) begin
        if (mom_we) mom_ram[mom_waddr] <= mom_wdata;
        mom_q <= mom_ram[{mom_pub, mom_raddr}];
    end
    reg        c11_neg;
    reg [63:0] mcx, mcy, mka, mkb, mkc;
    wire [17:0] mka_s = (mka > 64'd262143) ? 18'd262143 : mka[17:0];
    wire [17:0] mkb_s = (mkb > 64'd262143) ? 18'd262143 : mkb[17:0];
    wire [17:0] mkc_s = (mkc > 64'd262143) ? 18'd262143 : mkc[17:0];
    wire [63:0] r_mul = mul_acc, r_div = div_q;
    wire [63:0] d_m = (m20 > m02) ? m20 - m02 : m02 - m20;
    wire [63:0] qn = dd + (p2 << 2);
    wire        rounder = (qn << 10) <= (qd << 3) + (qd << 2) + qd;
    wire [33:0] thr_calc = (gray_sum * 34'd175) >> 26;
    // |2*Sx - A*(x0+x1)| = 2*A*|centroid - box centre|; compare with 5/64*A*width
    wire [63:0] two_sx = cSx << 1, two_sy = cSy << 1;
    wire [63:0] off_x = (two_sx > t_bx) ? two_sx - t_bx : t_bx - two_sx;
    wire [63:0] off_y = (two_sy > t_by) ? two_sy - t_by : t_by - two_sy;
    wire        tri_asym = (off_x >= ((t_wx << 2) + (t_wx << 1)) >> 6) ||
                           (off_y >= ((t_wy << 2) + (t_wy << 1)) >> 6);
    reg [63:0] t_wh, fill;
    wire        fill_c = fill >= FILL_C_MIN && fill <= FILL_C_MAX;
    wire        fill_e = fill >= FILL_E_MIN && fill <= FILL_E_MAX;
    wire        fill_t = fill >= FILL_T_MIN && fill <= FILL_T_MAX;
    // Clutter rejection. cG*cNO vs cSO*cAD: mean inside <= 13/20 of the mean of
    // the surrounding samples; aspect <= ~3.5 (Qn*1024 <= Qd*740); circle,
    // ellipse, square and rectangle centred within 1/16 of the box size.
    reg [63:0] cG, cSO, cNO, cAD, t_g, t_s;
    wire        contrast_ok = (t_g << 4) + (t_g << 2) <= (t_s << 3) + (t_s << 2) + t_s;
    wire        aspect_ok = (qn << 10) <= (qd << 9) + (qd << 7) + (qd << 6) + (qd << 5) + (qd << 2);
    wire        centred = (off_x <= (t_wx >> 4)) && (off_y <= (t_wy >> 4));
    // runs + top edges <= 1.5 x (width + height), from the statistics word
    wire [10:0] q_w = stats_q[OX1 +: 10] - stats_q[OX0 +: 10] + 11'd1;
    wire [9:0]  q_h = stats_q[OY1 +: 9] - stats_q[OY0 +: 9] + 10'd1;
    wire [19:0] q_rt = stats_q[ORN +: 18] + stats_q[OT +: 18];
    wire        convex_ok = (q_rt << 1) <= ({9'd0, q_w} + q_h) * 3;
    reg         c_cvx_ok;
    reg [19:0]  c_rt, c_whs;
    reg [63:0]  rho100, cvx100, dbg_best;
    reg [17:0]  pdbg_area;
    reg [9:0]   pdbg_rho, pdbg_cvx, pdbg_j;
    reg [6:0]   pdbg_fill, pdbg_why;
    wire        band_e = j2 <= K_ELLIPSE_MAX;
    // Class of the object in classification (shapes need A >= A_MIN)
    wire [2:0]  cls_calc =
        (cA < A_MIN || cNO == 0 || !contrast_ok || !aspect_ok) ? CLS_NONE :
        (j2 <= K_ELLIPSE_MAX) ? ((!centred || !(rounder ? fill_c : fill_e)) ? CLS_NONE :
                                 rounder ? CLS_CIRCLE : CLS_ELLIPSE) :
        (j2 >= K_RECT_MIN && j2 <= K_RECT_MAX) ? (!centred ? CLS_NONE :
                                 rounder ? CLS_SQUARE : CLS_RECT) :
        (j2 >= K_TRI_MIN && j2 <= K_TRI_MAX && tri_asym && fill_t && cA >= A_TRI) ? CLS_TRIANGLE : CLS_NONE;
    // Digit candidate box: height >= 12, 1.25 <= h/w <= 6
    wire [10:0] cb_w = cbox[27:18] - cbox[37:28] + 11'd1;
    wire [10:0] cb_h = cbox[8:0] - cbox[17:9] + 11'd1;
    wire        dig_shape = cb_h >= 11'd12 && {cb_h, 2'b0} >= ({2'b0, cb_w} << 2) + cb_w &&
                            cb_h <= ({cb_w, 2'b0} + {1'b0, cb_w, 1'b0});
    reg         dig_ok;
    reg  [2:0]  pend_dcount;
    reg  [MAX_DIGITS*38-1:0] pend_dig;
    wire        band_r = j2 >= K_RECT_MIN && j2 <= K_RECT_MAX;
    wire        band_t = j2 >= K_TRI_MIN && j2 <= K_TRI_MAX;
    wire [6:0]  why = {band_t && !tri_asym,
                       (band_e && !(rounder ? fill_c : fill_e)) || (band_t && !fill_t),
                       (band_e || band_r) && !centred,
                       !band_e && !band_r && !band_t,
                       !aspect_ok,
                       cNO == 0 || !contrast_ok,
                       1'b0};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            scanning <= 0; processing <= 0; post_done <= 1; thr_use <= 8'd100;
            threshold <= 8'd100;
            s1_v <= 0; s2_v <= 0; s1_fg <= 0; s2_fg <= 0; s1_last <= 0; s2_last <= 0;
            s1_x <= 0; s2_x <= 0; s2_lb <= 0;
            row_bank <= 0; run_id <= 0; srow <= 0;
            in_run <= 0; run_x0 <= 0; run_label <= 0; run_n <= 0; run_sx <= 0; run_sxx <= 0;
            sq <= 0; last_pair <= 0; rowend_1 <= 0; rowend_2 <= 0;
            ev_v <= 0; ev_x0 <= 0; ev_x1 <= 0; ev_n <= 0; ev_sx <= 0; ev_sxx <= 0;
            ev_label <= 0; ev_y <= 0;
            up_v <= 0; up_new <= 0; up_x0 <= 0; up_x1 <= 0; up_n <= 0; up_sx <= 0;
            up_sxx <= 0; up_lab <= 0; up_y <= 0;
            next_label <= 11'd1; npairs <= 0; gray_sum <= 0;
            runw_en <= 0; runw_addr <= 0; runw_data <= 0;
            stats_we <= 0; stats_waddr <= 0; stats_wdata <= 0;
            pair_we <= 0; pair_waddr <= 0; pair_wdata <= 0;
            parent_we <= 0; parent_waddr <= 0; parent_wdata <= 0;
            pstate <= P_IDLE; pidx <= 0; fa <= 0; fb <= 0; fcur <= 0; ra <= 0; fpar <= 0;
            find_second <= 0; child <= 0;
            mul_go <= 0; div_go <= 0; op_a <= 0; op_b <= 0;
            cA <= 0; cSx <= 0; cSy <= 0; cSxx <= 0; cSyy <= 0; cSxy <= 0;
            t1 <= 0; c20 <= 0; c02 <= 0; c11 <= 0; aa <= 0; m20 <= 0; m02 <= 0; m11 <= 0;
            p1 <= 0; p2 <= 0; j2 <= 0; dd <= 0; qd <= 0;
            cbox <= 0; cstep <= 0; cwait <= 0; cls <= 0;
            t_bx <= 0; t_by <= 0; t_wx <= 0; t_wy <= 0;
            cG <= 0; cSO <= 0; cNO <= 0; t_g <= 0; t_s <= 0; t_wh <= 0; fill <= 0;
            c_cvx_ok <= 0; c_rt <= 0; c_whs <= 0; rho100 <= 0; cvx100 <= 0; dbg_best <= 0;
            pdbg_area <= 0; pdbg_rho <= 0; pdbg_cvx <= 0; pdbg_j <= 0; pdbg_fill <= 0; pdbg_why <= 0;
            dig_ok <= 0; pend_dcount <= 0; pend_dig <= 0; dig_count <= 0; dig_data <= 0;
            dbg_area <= 0; dbg_rho <= 0; dbg_cvx <= 0; dbg_j <= 0; dbg_fill <= 0; dbg_why <= 0;
            s1_gray <= 0; s2_gray <= 0; g_m1 <= 0; g_m2 <= 0; g_m3 <= 0; g_m4 <= 0;
            run_sg <= 0; run_top <= 0; run_so <= 0; run_no <= 0;
            ev_sg <= 0; ev_top <= 0; ev_so <= 0; ev_no <= 0;
            up_sg <= 0; up_top <= 0; up_so <= 0; up_no <= 0;
            gap_ok <= 0; gap_n <= 0; gap_sx <= 0; gap_sxx <= 0; row_prev_lab <= 0; row_prev_n <= 0;
            run_gn <= 0; run_gsx <= 0; run_gsxx <= 0; ev_gn <= 0; ev_gsx <= 0; ev_gsxx <= 0;
            up_nf <= 0; up_sxf <= 0; up_sxxf <= 0; cAD <= 0;
            pend_count <= 0; pend_data <= 0;
            mom_pub <= 0; mom_we <= 0; mom_waddr <= 0; mom_wdata <= 0;
            c11_neg <= 0; mcx <= 0; mcy <= 0; mka <= 0; mkb <= 0; mkc <= 0;
            obj_count <= 0; obj_data <= 0; obj_strobe <= 0;
        end else begin
            runw_en <= 0; stats_we <= 0; pair_we <= 0; parent_we <= 0; obj_strobe <= 0;
            mom_we <= 0;
            mul_go <= 0; div_go <= 0;

            // ---------------- frame phase ----------------
            if (vs_fall) begin
                if (scanning) begin
                    scanning <= 0;
                    processing <= 1;
                    post_done <= 0;
                    pidx <= 0;
                    pend_count <= 0;
                    pend_dcount <= 0;
                    dbg_best <= 0;
                    pdbg_area <= 0; pdbg_rho <= 0; pdbg_cvx <= 0;
                    pdbg_j <= 0; pdbg_fill <= 0; pdbg_why <= 0;
                    pstate <= P_PINIT;
                    threshold <= (thr_calc < 30) ? 8'd30 : (thr_calc > 200) ? 8'd200 : thr_calc[7:0];
                end else if (post_done) begin
                    processing <= 0;
                    scanning <= 1;
                    thr_use <= threshold;
                    next_label <= 11'd1; npairs <= 0; gray_sum <= 0; last_pair <= 0;
                    row_bank <= 0; run_id <= 0; srow <= 0; in_run <= 0; sq <= 0;
                    gap_ok <= 0; row_prev_lab <= 0;
                end
            end

            // ---------------- scan ----------------
            s1_v <= emit_v;
            s1_fg <= emit_fg;
            s1_x <= e2_x;
            s1_last <= (e2_x == SW-1);
            if (sample) gray_sum <= gray_sum + gray;
            s2_v <= s1_v;
            s2_fg <= s1_fg;
            s2_x <= s1_x;
            s2_last <= s1_last;
            s2_lb <= lb_q;
            s1_gray <= e2_g;
            s2_gray <= s1_gray;

            ev_v <= 0;
            if (s2_v) begin
                g_m1 <= s2_gray;
                g_m2 <= g_m1;
                g_m3 <= g_m2;
                g_m4 <= g_m3;
                if (s2_fg) begin
                    if (!in_run) begin
                        in_run <= 1;
                        run_x0 <= s2_x;
                        run_label <= up_label;
                        run_n <= 10'd1;
                        run_sx <= s2_x;
                        run_sxx <= sq;
                        run_sg <= s2_gray;
                        run_top <= s2_top;
                        run_so <= g_m4;
                        run_no <= (s2_x >= 10'd4);
                        run_gn <= gap_ok ? gap_n : 10'd0;
                        run_gsx <= gap_ok ? gap_sx : 19'd0;
                        run_gsxx <= gap_ok ? gap_sxx : 28'd0;
                    end else begin
                        run_n <= run_n + 10'd1;
                        run_sx <= run_sx + s2_x;
                        run_sxx <= run_sxx + sq;
                        run_sg <= run_sg + s2_gray;
                        run_top <= run_top + s2_top;
                        if (up_label != 0) begin
                            if (run_label == 0) run_label <= up_label;
                            else if (up_label != run_label && {run_label, up_label} != last_pair) begin
                                last_pair <= {run_label, up_label};
                                if (npairs < 11'd1024) begin
                                    pair_we <= 1;
                                    pair_waddr <= npairs[9:0];
                                    pair_wdata <= {run_label, up_label};
                                    npairs <= npairs + 11'd1;
                                end
                            end
                        end
                    end
                    if (s2_last) begin
                        in_run <= 0;
                        ev_v <= 1;
                        ev_x0 <= in_run ? run_x0 : s2_x;
                        ev_x1 <= s2_x;
                        ev_n <= in_run ? run_n + 10'd1 : 10'd1;
                        ev_sx <= in_run ? run_sx + s2_x : {9'd0, s2_x};
                        ev_sxx <= in_run ? run_sxx + sq : {9'd0, sq};
                        ev_label <= (in_run && run_label != 0) ? run_label : up_label;
                        ev_y <= srow;
                        ev_sg <= in_run ? run_sg + s2_gray : {10'd0, s2_gray};
                        ev_top <= in_run ? run_top + s2_top : {9'd0, s2_top};
                        ev_so <= in_run ? run_so : g_m4;
                        ev_no <= in_run ? run_no : (s2_x >= 10'd4);
                        ev_gn <= in_run ? run_gn : gap_ok ? gap_n : 10'd0;
                        ev_gsx <= in_run ? run_gsx : gap_ok ? gap_sx : 19'd0;
                        ev_gsxx <= in_run ? run_gsxx : gap_ok ? gap_sxx : 28'd0;
                    end
                end else if (in_run) begin
                    in_run <= 0;
                    ev_v <= 1;
                    ev_x0 <= run_x0;
                    ev_x1 <= s2_x - 10'd1;
                    ev_n <= run_n;
                    ev_sx <= run_sx;
                    ev_sxx <= run_sxx;
                    ev_label <= run_label;
                    ev_y <= srow;
                    ev_sg <= run_sg;
                    ev_top <= run_top;
                    ev_so <= run_so;
                    ev_no <= run_no;
                    ev_gn <= run_gn; ev_gsx <= run_gsx; ev_gsxx <= run_gsxx;
                    // a gap starts here
                    gap_ok <= 1; gap_n <= 10'd1; gap_sx <= {9'd0, s2_x}; gap_sxx <= {9'd0, sq};
                end else if (gap_ok) begin
                    gap_n <= gap_n + 10'd1;
                    gap_sx <= gap_sx + s2_x;
                    gap_sxx <= gap_sxx + sq;
                end
                sq <= s2_last ? 19'd0 : sq + {8'd0, s2_x, 1'b0} + 19'd1;
            end

            // run end: allocate a label if needed, record the run's label
            up_v <= 0;
            if (ev_v) begin
                up_v <= 1;
                up_x0 <= ev_x0; up_x1 <= ev_x1; up_n <= ev_n;
                up_sx <= ev_sx; up_sxx <= ev_sxx; up_y <= ev_y;
                up_sg <= ev_sg; up_top <= ev_top; up_so <= ev_so; up_no <= ev_no;
                up_nf <= ev_n + (hole_fill ? ev_gn : 10'd0);
                up_sxf <= ev_sx + (hole_fill ? ev_gsx : 19'd0);
                up_sxxf <= ev_sxx + (hole_fill ? ev_gsxx : 28'd0);
                runw_en <= 1;
                runw_addr <= {row_bank, run_id};
                if (ev_label != 0) begin
                    up_lab <= ev_label; up_new <= 0;
                    runw_data <= ev_label;
                end else if (next_label <= 11'd1023) begin
                    up_lab <= next_label[9:0]; up_new <= 1;
                    runw_data <= next_label[9:0];
                    next_label <= next_label + 11'd1;
                end else begin
                    up_lab <= 0; up_new <= 0;
                    runw_data <= 0;
                end
                run_id <= run_id + 9'd1;
            end
            if (up_v) begin row_prev_lab <= up_lab; row_prev_n <= up_n; end
            if (up_v && up_lab != 0) begin
                stats_we <= 1;
                stats_waddr <= up_lab;
                stats_wdata <= add_run(stats_q, up_new, up_x0, up_x1, up_nf, up_sxf, up_sxxf,
                                       up_y, up_sg, up_top, up_so, up_no, up_n);
            end

            // after the last sample of a sampled row (and its run end)
            rowend_1 <= s2_v && s2_last;
            rowend_2 <= rowend_1;
            if (rowend_2) begin
                row_bank <= !row_bank;
                run_id <= 0;
                srow <= srow + 9'd1;
                gap_ok <= 0;
                row_prev_lab <= 0;
            end

            // ---------------- post-processing ----------------
            case (pstate)
                P_IDLE: ;
                P_PINIT: begin
                    parent_we <= 1; parent_waddr <= pidx[9:0]; parent_wdata <= pidx[9:0];
                    if (pidx == 11'd1023) begin pidx <= 0; pstate <= P_U_RD; end
                    else pidx <= pidx + 11'd1;
                end
                // union of the recorded pairs
                P_U_RD: begin
                    if (pidx >= npairs) begin
                        pidx <= next_label - 11'd1;
                        pstate <= P_F_RD;
                    end else pstate <= P_U_GOT;          // pair_q valid next clock
                end
                P_U_GOT: begin
                    fa <= pair_q[19:10]; fb <= pair_q[9:0];
                    fcur <= pair_q[19:10]; find_second <= 0;
                    pstate <= P_U_FIND;
                end
                P_U_FIND: pstate <= P_U_FCHK;           // parent_q of fcur next clock
                P_U_FCHK: begin
                    if (parent_q != fcur) begin
                        fcur <= parent_q;
                        pstate <= P_U_FIND;
                    end else if (!find_second) begin
                        ra <= fcur;
                        fcur <= fb;
                        find_second <= 1;
                        pstate <= P_U_FIND;
                    end else begin
                        if (ra != fcur) begin
                            parent_we <= 1;
                            parent_waddr <= (ra > fcur) ? ra : fcur;
                            parent_wdata <= (ra > fcur) ? fcur : ra;
                        end
                        pidx <= pidx + 11'd1;
                        pstate <= P_U_RD;
                    end
                end
                // fold every non-root label into its parent, highest first
                P_F_RD: begin
                    if (pidx == 0) begin pidx <= 11'd1; pstate <= P_C_RD; end
                    else pstate <= P_F_CHK;              // parent_q and stats_q of pidx next clock
                end
                P_F_CHK: begin
                    if (parent_q == pidx[9:0]) begin
                        pidx <= pidx - 11'd1;
                        pstate <= P_F_RD;
                    end else begin
                        child <= stats_q;
                        fpar <= parent_q;
                        pstate <= P_F_RDP;
                    end
                end
                P_F_RDP: pstate <= P_F_GOTP;             // stats_q of fpar next clock
                P_F_GOTP: begin
                    stats_we <= 1;
                    stats_waddr <= fpar;
                    stats_wdata <= merge_stats(stats_q, child);
                    pidx <= pidx - 11'd1;
                    pstate <= P_F_GAP;          // let the write land before the next read
                end
                // classify every root
                P_C_RD: begin
                    if (pidx >= next_label) pstate <= P_DONE;
                    else pstate <= P_C_CHK;
                end
                P_C_CHK: begin
                    if (parent_q != pidx[9:0] || stats_q[OFL] ||
                        stats_q[OA +: WA] < A_DIG || stats_q[OA +: WA] > A_MAX) begin
                        pidx <= pidx + 11'd1;
                        pstate <= P_C_RD;
                    end else begin
                        // convexity is decided at the end, with the other
                        // tests, so the debug readout sees every candidate
                        c_cvx_ok <= convex_ok;
                        c_rt <= q_rt;
                        c_whs <= {9'd0, q_w} + q_h;
                        cA   <= stats_q[OA   +: WA  ];
                        cSx  <= stats_q[OSX  +: WSX ];
                        cSy  <= stats_q[OSY  +: WSY ];
                        cSxx <= stats_q[OSXX +: WSXX];
                        cSyy <= stats_q[OSYY +: WSYY];
                        cSxy <= stats_q[OSXY +: WSXY];
                        cG   <= stats_q[OG  +: 26];
                        cSO  <= stats_q[OSO +: 26];
                        cNO  <= stats_q[ONO +: 18];
                        cAD  <= stats_q[OAD +: 18];
                        cbox <= {3'd0, stats_q[OX0 +: 10], stats_q[OX1 +: 10],
                                 stats_q[OY0 +: 9], stats_q[OY1 +: 9]};
                        cstep <= 0; cwait <= 0; cls <= CLS_NONE; dig_ok <= 0;
                        pstate <= P_C_MATH;
                    end
                end
                P_C_MATH: begin
                    if (!cwait) begin
                        cwait <= 1;
                        case (cstep)
                            5'd0:  begin op_a <= cA;  op_b <= cSxx; mul_go <= 1; end
                            5'd1:  begin op_a <= cSx; op_b <= cSx;  mul_go <= 1; end
                            5'd2:  begin op_a <= cA;  op_b <= cSyy; mul_go <= 1; end
                            5'd3:  begin op_a <= cSy; op_b <= cSy;  mul_go <= 1; end
                            5'd4:  begin op_a <= cA;  op_b <= cSxy; mul_go <= 1; end
                            5'd5:  begin op_a <= cSx; op_b <= cSy;  mul_go <= 1; end
                            5'd6:  begin op_a <= cA;  op_b <= cA;   mul_go <= 1; end
                            5'd7:  begin op_a <= c20 << 8; op_b <= aa; div_go <= 1; end
                            5'd8:  begin op_a <= c02 << 8; op_b <= aa; div_go <= 1; end
                            5'd9:  begin op_a <= c11 << 8; op_b <= aa; div_go <= 1; end
                            5'd10: begin op_a <= m20; op_b <= m02;  mul_go <= 1; end
                            5'd11: begin op_a <= m11; op_b <= m11;  mul_go <= 1; end
                            5'd12: begin op_a <= (p1 - p2) << 10; op_b <= aa; div_go <= 1; end
                            5'd13: begin op_a <= d_m; op_b <= d_m;  mul_go <= 1; end
                            5'd14: begin op_a <= m20 + m02; op_b <= m20 + m02; mul_go <= 1; end
                            5'd15: begin op_a <= cA; op_b <= cbox[37:28] + cbox[27:18]; mul_go <= 1; end
                            5'd16: begin op_a <= cA; op_b <= cbox[17:9] + cbox[8:0]; mul_go <= 1; end
                            5'd17: begin op_a <= cA; op_b <= cbox[27:18] - cbox[37:28] + 10'd1; mul_go <= 1; end
                            5'd18: begin op_a <= cA; op_b <= cbox[8:0] - cbox[17:9] + 9'd1; mul_go <= 1; end
                            5'd19: begin op_a <= cG;  op_b <= cNO; mul_go <= 1; end
                            5'd20: begin op_a <= cSO; op_b <= cAD; mul_go <= 1; end
                            5'd21: begin op_a <= cbox[27:18] - cbox[37:28] + 10'd1;
                                         op_b <= cbox[8:0] - cbox[17:9] + 9'd1; mul_go <= 1; end
                            5'd22: begin op_a <= cA << 6; op_b <= t_wh; div_go <= 1; end
                            // debug readout only: 100 x inside/outside, 100 x convexity
                            5'd23: begin op_a <= (t_g << 6) + (t_g << 5) + (t_g << 2); op_b <= t_s; div_go <= 1; end
                            5'd24: begin op_a <= c_rt * 7'd100; op_b <= c_whs; div_go <= 1; end
                            // overlay colouring: centroid and inverse moments
                            5'd25: begin op_a <= cSx << 2; op_b <= cA; div_go <= 1; end
                            5'd26: begin op_a <= cSy << 2; op_b <= cA; div_go <= 1; end
                            5'd27: begin op_a <= m02 << 28; op_b <= p1 - p2; div_go <= 1; end
                            5'd28: begin op_a <= m11 << 29; op_b <= p1 - p2; div_go <= 1; end
                            5'd29: begin op_a <= m20 << 28; op_b <= p1 - p2; div_go <= 1; end
                            default: ;
                        endcase
                        if (cstep == 5'd12 && p1 <= p2) begin
                            // degenerate: no shape
                            cwait <= 0; mul_go <= 0; div_go <= 0;
                            cls <= CLS_NONE;
                            pstate <= P_C_STORE;
                        end
                        if (cstep == 5'd30) begin
                            cwait <= 0;
                            if (cA > dbg_best) begin
                                dbg_best <= cA;
                                pdbg_area <= cA[17:0];
                                pdbg_rho <= (rho100 > 64'd999) ? 10'd999 : rho100[9:0];
                                pdbg_cvx <= (cvx100 > 64'd999) ? 10'd999 : cvx100[9:0];
                                pdbg_j <= ((j2 >> 10) > 64'd999) ? 10'd999 : j2[19:10];
                                pdbg_fill <= (fill > 64'd99) ? 7'd99 : fill[6:0];
                                pdbg_why <= why;
                            end
                            cls <= cls_calc;
                            dig_ok <= cls_calc == CLS_NONE && cNO != 0 && contrast_ok && dig_shape;
                            pstate <= P_C_STORE;
                        end
                    end else if (!alu_busy) begin
                        cwait <= 0;
                        cstep <= cstep + 5'd1;
                        case (cstep)
                            5'd0:  t1 <= r_mul;
                            5'd1:  c20 <= (t1 >= r_mul) ? t1 - r_mul : 64'd0;
                            5'd2:  t1 <= r_mul;
                            5'd3:  c02 <= (t1 >= r_mul) ? t1 - r_mul : 64'd0;
                            5'd4:  t1 <= r_mul;
                            5'd5:  begin c11 <= (t1 >= r_mul) ? t1 - r_mul : r_mul - t1; c11_neg <= t1 < r_mul; end
                            5'd6:  aa <= r_mul;
                            5'd7:  m20 <= r_div;
                            5'd8:  m02 <= r_div;
                            5'd9:  m11 <= r_div;
                            5'd10: p1 <= r_mul;
                            5'd11: p2 <= r_mul;
                            5'd12: j2 <= r_div;
                            5'd13: dd <= r_mul;
                            5'd14: qd <= r_mul;
                            5'd15: t_bx <= r_mul;
                            5'd16: t_by <= r_mul;
                            5'd17: t_wx <= r_mul;
                            5'd18: t_wy <= r_mul;
                            5'd19: t_g <= r_mul;
                            5'd20: t_s <= r_mul;
                            5'd21: t_wh <= r_mul;
                            5'd22: fill <= r_div;
                            5'd23: rho100 <= r_div;
                            5'd24: cvx100 <= r_div;
                            5'd25: mcx <= r_div;
                            5'd26: mcy <= r_div;
                            5'd27: mka <= r_div;
                            5'd28: mkb <= r_div;
                            5'd29: mkc <= r_div;
                            default: ;
                        endcase
                    end
                end
                P_F_GAP: pstate <= P_F_RD;
                P_C_STORE: begin
                    if (cls != CLS_NONE && pend_count < MAX_OBJECTS) begin
                        pend_data[pend_count*41 +: 41] <= {cls, cbox[37:0]};
                        mom_we <= 1;
                        mom_waddr <= {!mom_pub, pend_count[4:0]};
                        mom_wdata <= {mcx[11:0], mcy[10:0], mka_s, c11_neg, mkb_s, mkc_s};
                        pend_count <= pend_count + 6'd1;
                    end
                    if (dig_ok && pend_dcount < MAX_DIGITS) begin
                        pend_dig[pend_dcount*38 +: 38] <= cbox[37:0];
                        pend_dcount <= pend_dcount + 3'd1;
                    end
                    dig_ok <= 0;
                    pidx <= pidx + 11'd1;
                    pstate <= P_C_RD;
                end
                P_DONE: begin
                    obj_count <= pend_count;
                    obj_strobe <= 1;
                    dig_count <= pend_dcount;
                    dig_data <= pend_dig;
                    dbg_area <= pdbg_area; dbg_rho <= pdbg_rho; dbg_cvx <= pdbg_cvx;
                    dbg_j <= pdbg_j; dbg_fill <= pdbg_fill; dbg_why <= pdbg_why;
                    obj_data <= pend_data;
                    mom_pub <= !mom_pub;
                    post_done <= 1;
                    pstate <= P_IDLE;
                end
                default: pstate <= P_IDLE;
            endcase
        end
    end
endmodule

`timescale 1ns/1ps

// Multi-object shape recognition by connected components and moments.
// Reference model: tools/models/shape_ccl_model.py (same integer arithmetic).
//
// Frames alternate between SCAN and PROCESS (the 30 fps camera shows every
// image twice at 60 Hz, so this is one analysis per camera frame):
//   SCAN    every second pixel of every second row (640 x 360) is compared
//           with an automatic threshold (0.6 x mean gray of the previous
//           scanned frame). Runs of dark samples are labelled 4-connected:
//           a run takes the label of the first run above it; when it also
//           touches another label the pair is stored and merged later.
//           Each label accumulates area, sums of x, y, x^2, y^2, xy, its
//           bounding box and a border flag.
//   PROCESS union of the stored pairs, folding of every merged label into
//           its parent (highest label first), then classification of every
//           root from J^2 = det(second central moments) / A^4 (ellipse
//           0.0796^2, rectangle 0.0833^2, triangle 0.0962^2) and the moment
//           aspect ratio (round below about 1.12).
// Results: up to MAX_OBJECTS objects, published at the end of PROCESS.
module shape_detector #(
    parameter integer MAX_OBJECTS = 32,
    parameter integer A_MIN = 600,
    parameter integer A_MAX = 100000
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        vsync_n,        // low during vertical sync
    input  wire        de,             // 1280 pixels per row, 720 rows
    input  wire [7:0]  gray,
    output reg  [5:0]  obj_count,
    // per object {cls[2:0], x0[9:0], x1[9:0], y0[8:0], y1[8:0]}, half resolution
    output reg  [MAX_OBJECTS*41-1:0] obj_data,
    output reg  [7:0]  threshold
);
    localparam integer SW = 640, SH = 360;
    localparam [2:0] CLS_NONE = 3'd0, CLS_CIRCLE = 3'd1, CLS_ELLIPSE = 3'd2,
                     CLS_SQUARE = 3'd3, CLS_RECT = 3'd4, CLS_TRIANGLE = 3'd5;
    // J^2 * 2^26 bands
    localparam [63:0] K_ELLIPSE_MAX = 64'd432723, K_RECT_MIN = 64'd452340,
                      K_RECT_MAX = 64'd484861, K_TRI_MIN = 64'd543582,
                      K_TRI_MAX = 64'd711957;

    // ------------------------------------------------------------------
    // Label statistics word
    localparam integer WA = 18, WSX = 28, WSY = 27, WSXX = 37, WSYY = 35, WSXY = 36;
    localparam integer OA = 0, OSX = OA + WA, OSY = OSX + WSX, OSXX = OSY + WSY,
                       OSYY = OSXX + WSXX, OSXY = OSYY + WSYY, OX0 = OSXY + WSXY,
                       OX1 = OX0 + 10, OY0 = OX1 + 10, OY1 = OY0 + 9, OFL = OY1 + 9,
                       SWID = OFL + 1;

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

    reg [8:0]  lb_ram [0:SW-1];
    reg [9:0]  run_ram [0:1023];
    // run_ram write (label of a finished run of the current row)
    reg        runw_en;
    reg [9:0]  runw_addr;
    reg [9:0]  runw_data;
    always @(posedge clk) begin
        if (sample) lb_q <= lb_ram[sx_now];
        if (s2_v) lb_ram[s2_x] <= s2_fg ? run_id + 9'd1 : 9'd0;
        run_q <= run_ram[{!row_bank, lb_q - 9'd1}];
        if (runw_en) run_ram[runw_addr] <= runw_data;
    end
    wire [9:0] up_label = (s2_lb != 0 && srow != 0) ? run_q : 10'd0;

    reg        in_run;
    reg [9:0]  run_x0;
    reg [9:0]  run_label;
    reg [9:0]  run_n;
    reg [18:0] run_sx;
    reg [27:0] run_sxx;
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
    reg        up_v, up_new;
    reg [9:0]  up_x0, up_x1, up_n;
    reg [18:0] up_sx;
    reg [27:0] up_sxx;
    reg [9:0]  up_lab;
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
        reg   [16:0]     ysq;
        reg              border;
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
    wire [63:0] r_mul = mul_acc, r_div = div_q;
    wire [63:0] d_m = (m20 > m02) ? m20 - m02 : m02 - m20;
    wire [63:0] qn = dd + (p2 << 2);
    wire        rounder = (qn << 10) <= (qd << 3) + (qd << 2) + qd;
    wire [33:0] thr_calc = (gray_sum * 34'd175) >> 26;
    // |2*Sx - A*(x0+x1)| = 2*A*|centroid - box centre|; compare with 5/64*A*width
    wire [63:0] two_sx = cSx << 1, two_sy = cSy << 1;
    wire [63:0] off_x = (two_sx > t_bx) ? two_sx - t_bx : t_bx - two_sx;
    wire [63:0] off_y = (two_sy > t_by) ? two_sy - t_by : t_by - two_sy;
    wire        tri_asym = (off_x >= ((t_wx << 2) + t_wx) >> 6) ||
                           (off_y >= ((t_wy << 2) + t_wy) >> 6);

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
            pend_count <= 0; pend_data <= 0;
            obj_count <= 0; obj_data <= 0;
        end else begin
            runw_en <= 0; stats_we <= 0; pair_we <= 0; parent_we <= 0;
            mul_go <= 0; div_go <= 0;

            // ---------------- frame phase ----------------
            if (vs_fall) begin
                if (scanning) begin
                    scanning <= 0;
                    processing <= 1;
                    post_done <= 0;
                    pidx <= 0;
                    pend_count <= 0;
                    pstate <= P_PINIT;
                    threshold <= (thr_calc < 30) ? 8'd30 : (thr_calc > 200) ? 8'd200 : thr_calc[7:0];
                end else if (post_done) begin
                    processing <= 0;
                    scanning <= 1;
                    thr_use <= threshold;
                    next_label <= 11'd1; npairs <= 0; gray_sum <= 0; last_pair <= 0;
                    row_bank <= 0; run_id <= 0; srow <= 0; in_run <= 0; sq <= 0;
                end
            end

            // ---------------- scan ----------------
            s1_v <= sample;
            s1_fg <= gray < thr_use;
            s1_x <= sx_now;
            s1_last <= (sx_now == SW-1);
            if (sample) gray_sum <= gray_sum + gray;
            s2_v <= s1_v;
            s2_fg <= s1_fg;
            s2_x <= s1_x;
            s2_last <= s1_last;
            s2_lb <= lb_q;

            ev_v <= 0;
            if (s2_v) begin
                if (s2_fg) begin
                    if (!in_run) begin
                        in_run <= 1;
                        run_x0 <= s2_x;
                        run_label <= up_label;
                        run_n <= 10'd1;
                        run_sx <= s2_x;
                        run_sxx <= sq;
                    end else begin
                        run_n <= run_n + 10'd1;
                        run_sx <= run_sx + s2_x;
                        run_sxx <= run_sxx + sq;
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
                end
                sq <= s2_last ? 19'd0 : sq + {8'd0, s2_x, 1'b0} + 19'd1;
            end

            // run end: allocate a label if needed, record the run's label
            up_v <= 0;
            if (ev_v) begin
                up_v <= 1;
                up_x0 <= ev_x0; up_x1 <= ev_x1; up_n <= ev_n;
                up_sx <= ev_sx; up_sxx <= ev_sxx; up_y <= ev_y;
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
            if (up_v && up_lab != 0) begin
                stats_we <= 1;
                stats_waddr <= up_lab;
                stats_wdata <= add_run(stats_q, up_new, up_x0, up_x1, up_n, up_sx, up_sxx, up_y);
            end

            // after the last sample of a sampled row (and its run end)
            rowend_1 <= s2_v && s2_last;
            rowend_2 <= rowend_1;
            if (rowend_2) begin
                row_bank <= !row_bank;
                run_id <= 0;
                srow <= srow + 9'd1;
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
                        stats_q[OA +: WA] < A_MIN || stats_q[OA +: WA] > A_MAX) begin
                        pidx <= pidx + 11'd1;
                        pstate <= P_C_RD;
                    end else begin
                        cA   <= stats_q[OA   +: WA  ];
                        cSx  <= stats_q[OSX  +: WSX ];
                        cSy  <= stats_q[OSY  +: WSY ];
                        cSxx <= stats_q[OSXX +: WSXX];
                        cSyy <= stats_q[OSYY +: WSYY];
                        cSxy <= stats_q[OSXY +: WSXY];
                        cbox <= {3'd0, stats_q[OX0 +: 10], stats_q[OX1 +: 10],
                                 stats_q[OY0 +: 9], stats_q[OY1 +: 9]};
                        cstep <= 0; cwait <= 0; cls <= CLS_NONE;
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
                            default: ;
                        endcase
                        if (cstep == 5'd12 && p1 <= p2) begin
                            // degenerate: no shape
                            cwait <= 0; mul_go <= 0; div_go <= 0;
                            cls <= CLS_NONE;
                            pstate <= P_C_STORE;
                        end
                        if (cstep == 5'd19) begin
                            cwait <= 0;
                            if (j2 <= K_ELLIPSE_MAX) cls <= rounder ? CLS_CIRCLE : CLS_ELLIPSE;
                            else if (j2 >= K_RECT_MIN && j2 <= K_RECT_MAX) cls <= rounder ? CLS_SQUARE : CLS_RECT;
                            else if (j2 >= K_TRI_MIN && j2 <= K_TRI_MAX && tri_asym) cls <= CLS_TRIANGLE;
                            else cls <= CLS_NONE;
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
                            5'd5:  c11 <= (t1 >= r_mul) ? t1 - r_mul : r_mul - t1;
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
                            default: ;
                        endcase
                    end
                end
                P_F_GAP: pstate <= P_F_RD;
                P_C_STORE: begin
                    if (cls != CLS_NONE && pend_count < MAX_OBJECTS) begin
                        pend_data[pend_count*41 +: 41] <= {cls, cbox[37:0]};
                        pend_count <= pend_count + 6'd1;
                    end
                    pidx <= pidx + 11'd1;
                    pstate <= P_C_RD;
                end
                P_DONE: begin
                    obj_count <= pend_count;
                    obj_data <= pend_data;
                    post_done <= 1;
                    pstate <= P_IDLE;
                end
                default: pstate <= P_IDLE;
            endcase
        end
    end
endmodule

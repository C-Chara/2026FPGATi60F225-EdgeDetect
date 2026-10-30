`timescale 1ns/1ps

// Printed digit recognition (1-9) for the shape_detector's digit candidates.
// Reference model: tools/models/digit_study.py (grid_bits, classify).
//
// One candidate box per frame, in turn: during the frame every sample inside
// the box adds +1 (dark under the detector's local threshold) or -1 to the
// counter of its cell in a 7 x 9 grid over the box; a cell is dark when its
// counter is >= 0 (at least half of its samples dark). In the vertical
// blanking the 63 cells are compared with 30 templates (Arial Bold digits
// 0-9 at -8, 0, +8 degrees, src/edge/digit_templates.v): distance = cells
// that differ among the template's sure cells; per digit the best rotation.
// Accepted: best distance <= DMAX, the next digit at least 2 further, digit
// not 0. Each read goes to the display slot whose box contains its centre
// (the candidate list order may change between analyses); a slot shows a
// digit once two reads in a row agree, and is dropped after AGE_MAX reads
// of other candidates without one of its own.
// No RAM blocks: counters and templates are logic.
module digit_reader #(
    parameter integer N = 4,
    parameter integer DMAX = 8,
    parameter integer AGE_MAX = 12
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        vsync_n,
    input  wire        smp_v,
    input  wire [9:0]  smp_x,
    input  wire [8:0]  smp_y,
    input  wire        smp_dark,
    input  wire        cand_strobe,
    input  wire [2:0]  cand_count,
    input  wire [N*38-1:0] cand_data,         // {x0, x1, y0, y1} per candidate
    output reg  [2:0]  slot_count,
    output reg  [N*38-1:0] slot_box,
    output reg  [N*4-1:0]  slot_digit          // 15: none
);
    localparam integer GW = 7, GH = 9, NC = GW * GH;
    reg  [4:0]  t;
    wire [NC-1:0] tmpl_bits, tmpl_care;
    digit_templates u_templates (.t(t), .bits(tmpl_bits), .care(tmpl_care));

    reg  [N*38-1:0] lst;
    reg  [2:0]  lcnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin lst <= 0; lcnt <= 0; end
        else if (cand_strobe) begin lst <= cand_data; lcnt <= cand_count; end
    end

    reg vs_d;
    wire vs_fall = vs_d && !vsync_n;

    localparam [2:0] S_IDLE = 0, S_SETUP = 1, S_DIV = 2, S_ARM = 3, S_CLS = 4,
                     S_BEST = 5, S_STORE = 6;
    reg  [2:0]  state;
    reg  [1:0]  idx;
    reg  [37:0] cur;
    wire [9:0]  c_x0 = cur[37:28], c_x1 = cur[27:18];
    wire [8:0]  c_y0 = cur[17:9],  c_y1 = cur[8:0];
    reg  [18:0] kw, kh;

    // restoring divider (20-bit numerator): (GW << 16) / w, then (GH << 16) / h
    reg  [19:0] dq, dr, dn;
    reg  [9:0]  dd;
    reg  [4:0]  dcnt;
    reg         dsec;
    wire [20:0] dshift = {dr, dn[19]};

    // accumulation pipeline
    reg  [13:0] acc [0:NC-1];
    reg         a1_v, a1_dark, a2_v, a2_dark;
    reg  [9:0]  a1_dx;
    reg  [8:0]  a1_dy;
    reg  [2:0]  a2_cx;
    reg  [3:0]  a2_cy;
    wire [28:0] mx = a1_dx * kw;
    wire [27:0] my = a1_dy * kh;
    wire [5:0]  a2_k = a2_cy * 3'd7 + a2_cx;

    // classification
    reg  [NC-1:0] bits;
    reg  [3:0]  tdig;
    reg  [1:0]  trot;
    reg         m_v;
    reg  [3:0]  m_dig;
    reg  [NC-1:0] mm;
    reg  [6:0]  dmin [0:9];
    reg  [3:0]  bi;
    reg  [6:0]  b1, b2;
    reg  [3:0]  c1;
    reg  [3:0]  last [0:N-1];
    reg  [3:0]  age  [0:N-1];
    reg  [N-1:0] s_ok;
    // slot of the current read: the valid slot whose box holds the centre of
    // the read box, else a free slot, else the oldest one
    wire [10:0] c_cx2 = c_x0 + c_x1;
    wire [9:0]  c_cy2 = c_y0 + c_y1;
    reg  [1:0]  ps;
    reg         pfound;
    integer     z;
    always @* begin
        pfound = 1'b0; ps = 2'd0;
        for (z = N - 1; z >= 0; z = z - 1)
            if (s_ok[z] && {1'b0, slot_box[z*38+28 +: 10]} * 2 <= c_cx2 &&
                c_cx2 <= {1'b0, slot_box[z*38+18 +: 10]} * 2 + 1 &&
                {1'b0, slot_box[z*38+9 +: 9]} * 2 <= c_cy2 &&
                c_cy2 <= {1'b0, slot_box[z*38 +: 9]} * 2 + 1) begin
                pfound = 1'b1; ps = z[1:0];
            end
        if (!pfound) begin
            for (z = N - 1; z >= 0; z = z - 1)
                if (!s_ok[z]) begin pfound = 1'b1; ps = z[1:0]; end
        end
        if (!pfound) begin
            ps = 2'd0;
            for (z = 1; z < N; z = z + 1)
                if (age[z] > age[ps]) ps = z[1:0];
        end
    end
    function [6:0] popcount;
        input [NC-1:0] v;
        integer i;
        begin
            popcount = 0;
            for (i = 0; i < NC; i = i + 1) popcount = popcount + v[i];
        end
    endfunction
    wire [6:0] pc = popcount(mm);

    integer q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vs_d <= 1; state <= S_IDLE; idx <= 0; cur <= 0; kw <= 0; kh <= 0;
            dq <= 0; dr <= 0; dn <= 0; dd <= 0; dcnt <= 0; dsec <= 0;
            a1_v <= 0; a1_dark <= 0; a2_v <= 0; a2_dark <= 0; a1_dx <= 0; a1_dy <= 0;
            a2_cx <= 0; a2_cy <= 0; bits <= 0; t <= 0; tdig <= 0; trot <= 0;
            m_v <= 0; m_dig <= 0; mm <= 0; bi <= 0; b1 <= 0; b2 <= 0; c1 <= 0;
            slot_count <= 0; slot_box <= 0; slot_digit <= {N{4'hf}};
            for (q = 0; q < NC; q = q + 1) acc[q] <= 0;
            for (q = 0; q < 10; q = q + 1) dmin[q] <= 0;
            for (q = 0; q < N; q = q + 1) begin last[q] <= 4'hf; age[q] <= 0; end
            s_ok <= 0;
        end else begin
            vs_d <= vsync_n;
            // ---- accumulation (one update per sample, samples 2 clocks apart)
            a1_v <= state == S_ARM && smp_v && smp_x >= c_x0 && smp_x <= c_x1 &&
                    smp_y >= c_y0 && smp_y <= c_y1;
            a1_dark <= smp_dark;
            a1_dx <= smp_x - c_x0;
            a1_dy <= smp_y - c_y0;
            a2_v <= a1_v;
            a2_dark <= a1_dark;
            a2_cx <= mx[18:16];
            a2_cy <= my[19:16];
            if (a2_v) acc[a2_k] <= a2_dark ? acc[a2_k] + 14'd1 : acc[a2_k] - 14'd1;

            case (state)
                S_IDLE: if (vs_fall) state <= S_SETUP;
                S_SETUP: begin
                    if (lcnt == 0) begin
                        s_ok <= 0;
                        slot_digit <= {N{4'hf}};
                        state <= S_IDLE;
                    end else begin
                        cur <= lst[(idx + 2'd1 >= lcnt ? 2'd0 : idx + 2'd1) * 38 +: 38];
                        idx <= (idx + 2'd1 >= lcnt) ? 2'd0 : idx + 2'd1;
                        for (q = 0; q < NC; q = q + 1) acc[q] <= 0;
                        dsec <= 0; dcnt <= 0;
                        state <= S_DIV;
                    end
                end
                S_DIV: begin
                    if (dcnt == 0) begin
                        dq <= 0; dr <= 0;
                        dn <= dsec ? (20'd9 << 16) : (20'd7 << 16);
                        dd <= dsec ? (c_y1 - c_y0 + 10'd1) : (c_x1 - c_x0 + 10'd1);
                        dcnt <= 5'd1;
                    end else if (dcnt <= 5'd20) begin
                        if (dshift >= {11'd0, dd}) begin
                            dr <= dshift - dd; dq <= {dq[18:0], 1'b1};
                        end else begin
                            dr <= dshift[19:0]; dq <= {dq[18:0], 1'b0};
                        end
                        dn <= dn << 1;
                        dcnt <= dcnt + 5'd1;
                    end else begin
                        if (dsec) begin kh <= dq[18:0]; state <= S_ARM; end
                        else begin kw <= dq[18:0]; dsec <= 1; dcnt <= 0; end
                    end
                end
                S_ARM: if (vs_fall) begin
                    for (q = 0; q < NC; q = q + 1) bits[q] <= !acc[q][13];
                    t <= 0; tdig <= 0; trot <= 0; m_v <= 0;
                    for (q = 0; q < 10; q = q + 1) dmin[q] <= 7'd127;
                    state <= S_CLS;
                end
                S_CLS: begin
                    // stage 1: masked difference of template t
                    if (t < 5'd30) begin
                        mm <= (bits ^ tmpl_bits) & tmpl_care;
                        m_dig <= tdig;
                        m_v <= 1;
                        t <= t + 5'd1;
                        if (trot == 2'd2) begin trot <= 0; tdig <= tdig + 4'd1; end
                        else trot <= trot + 2'd1;
                    end else m_v <= 0;
                    // stage 2: count, keep the best rotation per digit
                    if (m_v && pc < dmin[m_dig]) dmin[m_dig] <= pc;
                    if (t == 5'd30 && !m_v) begin
                        bi <= 0; b1 <= 7'd127; b2 <= 7'd127; c1 <= 0;
                        state <= S_BEST;
                    end
                end
                S_BEST: begin
                    if (dmin[bi] < b1) begin b2 <= b1; b1 <= dmin[bi]; c1 <= bi; end
                    else if (dmin[bi] < b2) b2 <= dmin[bi];
                    if (bi == 4'd9) state <= S_STORE;
                    else bi <= bi + 4'd1;
                end
                S_STORE: begin
                    slot_count <= N;
                    for (q = 0; q < N; q = q + 1)
                        if (s_ok[q] && q != ps) begin
                            if (age[q] >= AGE_MAX) begin
                                s_ok[q] <= 0; slot_digit[q*4 +: 4] <= 4'hf; last[q] <= 4'hf;
                            end else age[q] <= age[q] + 4'd1;
                        end
                    slot_box[ps*38 +: 38] <= cur;
                    age[ps] <= 0;
                    // accepted digit, shown once two reads in a row agree
                    begin : decide
                        reg [3:0] dg;
                        dg = (b1 <= DMAX && b2 >= b1 + 7'd2 && c1 != 0) ? c1 : 4'hf;
                        if (s_ok[ps] && dg == last[ps]) slot_digit[ps*4 +: 4] <= dg;
                        else if (!s_ok[ps]) slot_digit[ps*4 +: 4] <= 4'hf;
                        last[ps] <= dg;
                    end
                    s_ok[ps] <= 1'b1;
                    state <= S_SETUP;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule

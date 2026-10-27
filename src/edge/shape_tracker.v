`timescale 1ns/1ps

// Cross-frame voting for the shape_detector results.
// Reference model: tools/models/shape_tracker_model.py (bit-exact).
//
// Each detector result (in_strobe) updates up to N tracks:
//   match   a detection takes the nearest unmatched track whose box centre is
//           within half the larger box size and whose size is within 2x;
//   update  the box follows; the shown class changes only after SWITCH
//           consecutive detections of the same new class;
//   new     an unmatched detection opens the first free track;
//   age     a track missed MISS_MAX+1 times in a row is dropped, until then it
//           keeps its last box (no blinking on a missed analysis);
//   show    a track is shown once it was detected SHOW times (single-frame
//           false detections never appear).
// One track per clock in the search: about 34 * detections + 40 clocks per
// result, far below one frame. Same object format as shape_detector.
module shape_tracker #(
    parameter integer N = 32,
    parameter integer SHOW = 2,
    parameter integer SWITCH = 3,
    parameter integer MISS_MAX = 2
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        in_strobe,           // in_count / in_data are new
    input  wire [5:0]  in_count,
    input  wire [N*41-1:0] in_data,         // {cls, x0, x1, y0, y1}
    output reg  [5:0]  obj_count,
    output reg  [N*41-1:0] obj_data
);
    localparam [2:0] S_IDLE = 0, S_INIT = 1, S_SCAN = 2, S_APPLY = 3, S_AGE = 4,
                     S_OUT = 5, S_PUB = 6;
    reg [2:0]  state;

    reg [N-1:0] t_valid, matched;
    reg [37:0] t_box  [0:N-1];
    reg [2:0]  t_cls  [0:N-1];
    reg [2:0]  t_cand [0:N-1];
    reg [1:0]  t_ccnt [0:N-1];
    reg [1:0]  t_hits [0:N-1];
    reg [1:0]  t_miss [0:N-1];

    reg [5:0]  cnt, di, k;
    reg [5:0]  j, fj, ff;
    reg        found, free_ok;
    reg [11:0] best;
    reg [N*41-1:0] out_buf;

    // Current detection and the track under test
    wire [40:0] det = in_data[di*41 +: 41];
    wire [2:0]  d_cls = det[40:38];
    wire [9:0]  d_x0 = det[37:28], d_x1 = det[27:18];
    wire [8:0]  d_y0 = det[17:9],  d_y1 = det[8:0];
    wire [37:0] tb = t_box[j];
    wire [9:0]  t_x0 = tb[37:28], t_x1 = tb[27:18];
    wire [8:0]  t_y0 = tb[17:9],  t_y1 = tb[8:0];
    wire [10:0] dcx = d_x0 + d_x1, tcx = t_x0 + t_x1;
    wire [9:0]  dcy = d_y0 + d_y1, tcy = t_y0 + t_y1;
    wire [10:0] ex = (dcx > tcx) ? dcx - tcx : tcx - dcx;
    wire [9:0]  ey = (dcy > tcy) ? dcy - tcy : tcy - dcy;
    wire [10:0] dw = d_x1 - d_x0 + 11'd1, tw = t_x1 - t_x0 + 11'd1;
    wire [9:0]  dh = d_y1 - d_y0 + 10'd1, th = t_y1 - t_y0 + 10'd1;
    wire [10:0] mw = (dw > tw) ? dw : tw;
    wire [9:0]  mh = (dh > th) ? dh : th;
    wire [10:0] sw = (dw > tw) ? dw - tw : tw - dw;
    wire [9:0]  sh = (dh > th) ? dh - th : th - dh;
    wire [11:0] dsum = ex + ey;
    wire        gate = t_valid[j] && !matched[j] && ex <= mw && ey <= mh &&
                       {sw, 1'b0} <= {1'b0, mw} && {sh, 1'b0} <= {1'b0, mh};

    integer q;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE;
            t_valid <= 0; matched <= 0;
            cnt <= 0; di <= 0; k <= 0; j <= 0; fj <= 0; ff <= 0;
            found <= 0; free_ok <= 0; best <= 0; out_buf <= 0;
            obj_count <= 0; obj_data <= 0;
            for (q = 0; q < N; q = q + 1) begin
                t_box[q] <= 0; t_cls[q] <= 0; t_cand[q] <= 0;
                t_ccnt[q] <= 0; t_hits[q] <= 0; t_miss[q] <= 0;
            end
        end else begin
            case (state)
                S_IDLE: if (in_strobe) begin
                    cnt <= in_count;
                    di <= 0;
                    matched <= 0;
                    state <= (in_count == 0) ? S_AGE : S_INIT;
                end
                S_INIT: begin
                    j <= 0; found <= 0; free_ok <= 0;
                    state <= S_SCAN;
                end
                S_SCAN: begin
                    if (gate && (!found || dsum < best)) begin
                        found <= 1; fj <= j; best <= dsum;
                    end
                    if (!t_valid[j] && !free_ok) begin
                        free_ok <= 1; ff <= j;
                    end
                    if (j == N - 1) state <= S_APPLY;
                    else j <= j + 6'd1;
                end
                S_APPLY: begin
                    if (found) begin
                        t_box[fj] <= det[37:0];
                        if (d_cls == t_cls[fj]) begin
                            t_cand[fj] <= d_cls; t_ccnt[fj] <= 0;
                        end else if (d_cls == t_cand[fj]) begin
                            if (t_ccnt[fj] + 2'd1 >= SWITCH) begin
                                t_cls[fj] <= d_cls; t_ccnt[fj] <= 0;
                            end else t_ccnt[fj] <= t_ccnt[fj] + 2'd1;
                        end else begin
                            t_cand[fj] <= d_cls; t_ccnt[fj] <= 2'd1;
                        end
                        if (t_hits[fj] != 2'd3) t_hits[fj] <= t_hits[fj] + 2'd1;
                        t_miss[fj] <= 0;
                        matched[fj] <= 1;
                    end else if (free_ok) begin
                        t_valid[ff] <= 1;
                        t_box[ff] <= det[37:0];
                        t_cls[ff] <= d_cls; t_cand[ff] <= d_cls;
                        t_ccnt[ff] <= 0; t_hits[ff] <= 2'd1; t_miss[ff] <= 0;
                        matched[ff] <= 1;
                    end
                    di <= di + 6'd1;
                    state <= (di + 6'd1 == cnt) ? S_AGE : S_INIT;
                end
                S_AGE: begin
                    for (q = 0; q < N; q = q + 1)
                        if (t_valid[q] && !matched[q]) begin
                            if (t_miss[q] >= MISS_MAX) begin
                                t_valid[q] <= 0; t_hits[q] <= 0; t_miss[q] <= 0;
                            end else t_miss[q] <= t_miss[q] + 2'd1;
                        end
                    j <= 0; k <= 0;
                    state <= S_OUT;
                end
                S_OUT: begin
                    if (t_valid[j] && t_hits[j] >= SHOW) begin
                        out_buf[k*41 +: 41] <= {t_cls[j], t_box[j]};
                        k <= k + 6'd1;
                    end
                    if (j == N - 1) state <= S_PUB;
                    else j <= j + 6'd1;
                end
                S_PUB: begin
                    obj_count <= k;
                    obj_data <= out_buf;
                    state <= S_IDLE;
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule

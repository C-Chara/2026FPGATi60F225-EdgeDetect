`timescale 1ns/1ps

// 3x3 median with the classic three-level selection network:
//   level 1: sort each window row       -> row min, row median, row max
//   level 2: max of the three row mins, median of the three row medians,
//            min of the three row maxima
//   level 3: median of those three values = median of all nine pixels
// 19 compare-and-select operations instead of a full sort. The line buffers
// and window are the same as median3x3_video.
// One pixel per clock; data/HS/VS/DE latency = 3 (window) + 3 (levels) = 6.
module median3x3_fast #(
    parameter integer H_ACTIVE = 1280
)(
    input wire clk, rst_n, hs_in, vs_in, de_in,
    input wire [7:0] gray_in,
    output wire hs_out, vs_out, de_out,
    output wire [7:0] gray_out,
    output wire [7:0] gray_center_out
);
    reg [7:0] line_1 [0:H_ACTIVE-1];
    reg [7:0] line_2 [0:H_ACTIVE-1];
    reg [7:0] line_1_q, line_2_q;
    reg [10:0] column, column_q;
    reg [1:0] completed_rows;
    reg valid_q, valid_qq, candidate_q, candidate_qq, window_valid;
    reg [7:0] gray_q, middle_q, bottom_q;
    reg [7:0] p00,p01,p02,p10,p11,p12,p20,p21,p22;
    reg [5:0] hs_pipe, vs_pipe, de_pipe;
    always @(posedge clk) begin
        if (de_in) begin
            line_1_q <= line_1[column];
            line_1[column] <= gray_in;
        end
        if (valid_q) begin
            line_2_q <= line_2[column_q];
            line_2[column_q] <= line_1_q;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            column<=0; column_q<=0; completed_rows<=0;
            valid_q<=0; valid_qq<=0; candidate_q<=0; candidate_qq<=0; window_valid<=0;
            gray_q<=0; middle_q<=0; bottom_q<=0;
            p00<=0;p01<=0;p02<=0;p10<=0;p11<=0;p12<=0;p20<=0;p21<=0;p22<=0;
            hs_pipe<=6'h3f;vs_pipe<=6'h3f;de_pipe<=0;
        end else begin
            hs_pipe<={hs_pipe[4:0],hs_in};
            vs_pipe<={vs_pipe[4:0],vs_in};
            de_pipe<={de_pipe[4:0],de_in};
            valid_q<=de_in;valid_qq<=valid_q;
            column_q<=column;gray_q<=gray_in;
            middle_q<=line_1_q;bottom_q<=gray_q;
            candidate_q<=de_in && completed_rows>=2 && column>=2;
            candidate_qq<=candidate_q;
            if (!vs_in) begin column<=0;completed_rows<=0;end
            else if (de_in) begin
                if (column==H_ACTIVE-1) begin
                    column<=0;
                    if(completed_rows!=3) completed_rows<=completed_rows+1'b1;
                end else column<=column+1'b1;
            end else column<=0;
            if (valid_qq) begin
                p00<=p01;p01<=p02;p02<=line_2_q;
                p10<=p11;p11<=p12;p12<=middle_q;
                p20<=p21;p21<=p22;p22<=bottom_q;
                window_valid<=candidate_qq;
            end else begin
                p00<=0;p01<=0;p02<=0;p10<=0;p11<=0;p12<=0;p20<=0;p21<=0;p22<=0;
                window_valid<=0;
            end
        end
    end

    function [7:0] min2; input [7:0] a, b; min2 = a < b ? a : b; endfunction
    function [7:0] max2; input [7:0] a, b; max2 = a < b ? b : a; endfunction
    function [7:0] med3;
        input [7:0] a, b, c;
        med3 = max2(min2(a, b), min2(max2(a, b), c));
    endfunction

    // Level 1: each row sorted into min / median / max.
    reg [7:0] r0_lo, r0_md, r0_hi, r1_lo, r1_md, r1_hi, r2_lo, r2_md, r2_hi;
    // Level 2: the three candidates for the overall median.
    reg [7:0] lo_max, md_med, hi_min;
    // Level 3: the median.
    reg [7:0] median_q;
    always @(posedge clk) begin
        r0_lo <= min2(min2(p00, p01), p02);
        r0_md <= med3(p00, p01, p02);
        r0_hi <= max2(max2(p00, p01), p02);
        r1_lo <= min2(min2(p10, p11), p12);
        r1_md <= med3(p10, p11, p12);
        r1_hi <= max2(max2(p10, p11), p12);
        r2_lo <= min2(min2(p20, p21), p22);
        r2_md <= med3(p20, p21, p22);
        r2_hi <= max2(max2(p20, p21), p22);
        lo_max <= max2(max2(r0_lo, r1_lo), r2_lo);
        md_med <= med3(r0_md, r1_md, r2_md);
        hi_min <= min2(min2(r0_hi, r1_hi), r2_hi);
        median_q <= med3(lo_max, md_med, hi_min);
    end

    // Carry the valid flag and the original centre pixel through the levels.
    reg [2:0] candidate_pipe;
    reg [7:0] center_pipe [0:2];
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) candidate_pipe<=0;
        else candidate_pipe<={candidate_pipe[1:0],window_valid};
    end
    always @(posedge clk) begin
        center_pipe[0] <= p11;
        center_pipe[1] <= center_pipe[0];
        center_pipe[2] <= center_pipe[1];
    end
    assign hs_out=hs_pipe[5];assign vs_out=vs_pipe[5];assign de_out=de_pipe[5];
    assign gray_out=candidate_pipe[2] ? median_q : 8'd0;
    assign gray_center_out=candidate_pipe[2] ? center_pipe[2] : 8'd0;
endmodule

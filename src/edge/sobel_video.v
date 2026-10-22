`timescale 1ns/1ps

// The project file keeps this legacy source registered. Include the active
// streaming modules here so Efinity also sees them after it normalizes the
// XML design-file list.
`include "gaussian_stream.v"
`include "median3x3_video.v"
`include "sobel_stream.v"
`include "hysteresis_stream.v"
`include "edge_frame_hold.v"

// RGB565 -> luma -> optional 3x3 median -> two line RAMs -> 3x3 Sobel.
// Controls/data latency = 20 clocks with median, 8 clocks when bypassed.
// The first four rows/columns are black with median (two when bypassed).
module sobel_video #(
    parameter integer H_ACTIVE = 1280,
    parameter [11:0] THRESHOLD = 12'd120,
    parameter [1:0] DISPLAY_MODE = 2'd2, // 0 gray, 1 binary, 2 overlay
    parameter MEDIAN_ENABLE = 1'b1,
    parameter RUNTIME_THRESHOLD = 1'b0
)(
    input wire clk, rst_n,
    input wire hs_in, vs_in, de_in,
    input wire [15:0] rgb565_in,
    input wire [11:0] threshold_in,
    output wire hs_out, vs_out, de_out,
    output wire [23:0] rgb_out,
    output reg [7:0] gray_out,
    output reg [7:0] edge_out
);
    wire [7:0] gray_comb;
    rgb565_gray u_gray (.rgb565(rgb565_in), .gray(gray_comb));
    reg [7:0] gray_reg;
    reg valid_gray, vs_gray;
    localparam integer LATENCY=MEDIAN_ENABLE ? 20:8;
    localparam integer BORDER=MEDIAN_ENABLE ? 4:2;
    reg [LATENCY-1:0] hs_pipe, vs_pipe, de_pipe;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            gray_reg <= 0; valid_gray <= 0; vs_gray <= 1;
            hs_pipe <= {LATENCY{1'b1}}; vs_pipe <= {LATENCY{1'b1}}; de_pipe <= 0;
        end else begin
            gray_reg <= gray_comb;
            valid_gray <= de_in; vs_gray <= vs_in;
            hs_pipe <= {hs_pipe[LATENCY-2:0], hs_in};
            vs_pipe <= {vs_pipe[LATENCY-2:0], vs_in};
            de_pipe <= {de_pipe[LATENCY-2:0], de_in};
        end
    end
    assign hs_out = hs_pipe[LATENCY-1];
    assign vs_out = vs_pipe[LATENCY-1];
    assign de_out = de_pipe[LATENCY-1];
    wire [7:0] stream_gray;
    wire stream_valid,stream_vs;
    generate if(MEDIAN_ENABLE) begin: median_enabled
        median3x3_video #(.H_ACTIVE(H_ACTIVE)) u_median (
            .clk(clk),.rst_n(rst_n),.hs_in(hs_pipe[0]),.vs_in(vs_gray),
            .de_in(valid_gray),.gray_in(gray_reg),.hs_out(),
            .vs_out(stream_vs),.de_out(stream_valid),.gray_out(stream_gray)
        );
    end else begin: median_bypass
        assign stream_gray=gray_reg;
        assign stream_valid=valid_gray;
        assign stream_vs=vs_gray;
    end endgenerate

    reg [7:0] line_1 [0:H_ACTIVE-1];
    reg [7:0] line_2 [0:H_ACTIVE-1];
    reg [7:0] line_1_q, line_2_q;
    reg [10:0] column, column_q;
    reg [2:0] completed_rows;
    reg valid_q, valid_qq, candidate_q, candidate_qq, window_valid;
    reg [7:0] gray_q, middle_q, bottom_q;
    reg [7:0] p00,p01,p02,p10,p11,p12,p20,p21,p22;
    // Read-before-write synchronous RAMs. Do not reset RAM or its read FFs.
    always @(posedge clk) begin
        if (stream_valid) begin
            line_1_q <= line_1[column];
            line_1[column] <= stream_gray;
        end
        if (valid_q) begin
            line_2_q <= line_2[column_q];
            line_2[column_q] <= line_1_q;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            column <= 0; column_q <= 0; completed_rows <= 0;
            valid_q <= 0; valid_qq <= 0;
            candidate_q <= 0; candidate_qq <= 0; window_valid <= 0;
            gray_q <= 0; middle_q <= 0; bottom_q <= 0;
            p00<=0; p01<=0; p02<=0; p10<=0; p11<=0; p12<=0;
            p20<=0; p21<=0; p22<=0;
        end else begin
            valid_q <= stream_valid; valid_qq <= valid_q;
            column_q <= column; gray_q <= stream_gray;
            middle_q <= line_1_q; bottom_q <= gray_q;
            candidate_q <= stream_valid && completed_rows >= BORDER && column >= BORDER;
            candidate_qq <= candidate_q;
            if (!stream_vs) begin
                column <= 0; completed_rows <= 0;
            end else if (stream_valid) begin
                if (column == H_ACTIVE-1) begin
                    column <= 0;
                    if (completed_rows != 7) completed_rows <= completed_rows + 1'b1;
                end else column <= column + 1'b1;
            end else column <= 0;
            if (valid_qq) begin
                p00<=p01; p01<=p02; p02<=line_2_q;
                p10<=p11; p11<=p12; p12<=middle_q;
                p20<=p21; p21<=p22; p22<=bottom_q;
                window_valid <= candidate_qq;
            end else begin
                p00<=0; p01<=0; p02<=0; p10<=0; p11<=0; p12<=0;
                p20<=0; p21<=0; p22<=0; window_valid <= 0;
            end
        end
    end
    reg [9:0] left_sum, right_sum, top_sum, bottom_sum;
    reg signed [10:0] gx, gy;
    wire [10:0] abs_gx = gx[10] ? -gx : gx;
    wire [10:0] abs_gy = gy[10] ? -gy : gy;
    reg [11:0] magnitude;
    reg partial_valid, gradient_valid, magnitude_valid;
    reg [7:0] partial_gray, gradient_gray, magnitude_gray;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            left_sum<=0; right_sum<=0; top_sum<=0; bottom_sum<=0;
            gx<=0; gy<=0; magnitude<=0;
            partial_valid<=0; gradient_valid<=0; magnitude_valid<=0;
            partial_gray<=0; gradient_gray<=0; magnitude_gray<=0;
            gray_out<=0; edge_out<=0;
        end else begin
            left_sum <= {2'd0,p00}+{1'b0,p10,1'b0}+{2'd0,p20};
            right_sum <= {2'd0,p02}+{1'b0,p12,1'b0}+{2'd0,p22};
            top_sum <= {2'd0,p00}+{1'b0,p01,1'b0}+{2'd0,p02};
            bottom_sum <= {2'd0,p20}+{1'b0,p21,1'b0}+{2'd0,p22};
            gx <= $signed({1'b0,right_sum})-$signed({1'b0,left_sum});
            gy <= $signed({1'b0,bottom_sum})-$signed({1'b0,top_sum});
            magnitude <= {1'b0,abs_gx}+{1'b0,abs_gy};
            partial_valid<=window_valid; gradient_valid<=partial_valid;
            magnitude_valid<=gradient_valid;
            partial_gray<=p11; gradient_gray<=partial_gray;
            magnitude_gray<=gradient_gray;
            gray_out <= magnitude_valid ? magnitude_gray : 8'd0;
            edge_out <= magnitude_valid && magnitude >= (RUNTIME_THRESHOLD ? threshold_in:THRESHOLD) ? 8'hff : 8'h00;
        end
    end
    wire [7:0] display_pixel = DISPLAY_MODE == 0 ? gray_out :
        DISPLAY_MODE == 1 ? edge_out :
        edge_out != 0 ? 8'hff : {1'b0,gray_out[7:1]};
    assign rgb_out = de_out ? {display_pixel,display_pixel,display_pixel} : 24'd0;
endmodule

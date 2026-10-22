`timescale 1ns/1ps

// 3x3 Gaussian smoothing: [1 2 1; 2 4 2; 1 2 1] / 16.
// The output valid stream starts on the third active image row. Its timing is
// delayed by three pixel clocks; the downstream Sobel stage uses this valid.
module gaussian_stream #(
    parameter integer H_ACTIVE = 1280
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       vsync_n,
    input  wire       pixel_valid,
    input  wire [7:0] gray_in,
    output wire [7:0] gray_out,
    output wire [7:0] gray_center_out,
    output reg        pixel_valid_out
);
    reg [7:0] line_1 [0:H_ACTIVE-1];
    reg [7:0] line_2 [0:H_ACTIVE-1];
    reg [7:0] line_1_q;
    reg [7:0] line_2_q;
    reg [10:0] column;
    reg [10:0] column_q;
    reg [1:0] rows_seen;
    reg valid_d;
    reg valid_q;
    reg valid_qq;
    reg row_ready_q;
    reg row_ready_qq;
    reg candidate_q;
    reg candidate_qq;
    reg window_valid;
    reg [7:0] gray_q;
    reg [7:0] middle_q;
    reg [7:0] bottom_q;

    reg [7:0] p00, p01, p02;
    reg [7:0] p10, p11, p12;
    reg [7:0] p20, p21, p22;

    // No reset on RAM read registers: this is the synchronous BRAM template.
    always @(posedge clk) begin
        if (pixel_valid) begin
            line_1[column] <= gray_in;
            line_1_q <= line_1[column];
        end
        if (valid_q) begin
            line_2[column_q] <= line_1_q;
            line_2_q <= line_2[column_q];
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            column         <= 11'd0;
            column_q       <= 11'd0;
            rows_seen      <= 2'd0;
            valid_d        <= 1'b0;
            valid_q        <= 1'b0;
            valid_qq       <= 1'b0;
            row_ready_q    <= 1'b0;
            row_ready_qq   <= 1'b0;
            candidate_q    <= 1'b0;
            candidate_qq   <= 1'b0;
            window_valid   <= 1'b0;
            pixel_valid_out <= 1'b0;
            gray_q         <= 8'd0;
            middle_q       <= 8'd0;
            bottom_q       <= 8'd0;
            p00 <= 8'd0; p01 <= 8'd0; p02 <= 8'd0;
            p10 <= 8'd0; p11 <= 8'd0; p12 <= 8'd0;
            p20 <= 8'd0; p21 <= 8'd0; p22 <= 8'd0;
        end else begin
            valid_d      <= pixel_valid;
            valid_q      <= pixel_valid;
            valid_qq     <= valid_q;
            column_q     <= column;
            gray_q       <= gray_in;
            middle_q     <= line_1_q;
            bottom_q     <= gray_q;
            row_ready_q  <= pixel_valid && (rows_seen >= 2'd2);
            row_ready_qq <= row_ready_q;
            candidate_q  <= pixel_valid && (rows_seen >= 2'd2) && (column >= 11'd2);
            candidate_qq <= candidate_q;

            if (!vsync_n) begin
                column    <= 11'd0;
                rows_seen <= 2'd0;
            end else if (pixel_valid) begin
                if (column == H_ACTIVE-1)
                    column <= 11'd0;
                else
                    column <= column + 11'd1;
                if (!valid_d && rows_seen != 2'd3)
                    rows_seen <= rows_seen + 2'd1;
            end else begin
                column <= 11'd0;
            end

            pixel_valid_out <= valid_qq && row_ready_qq;
            if (valid_qq) begin
                p00 <= p01; p01 <= p02; p02 <= line_2_q;
                p10 <= p11; p11 <= p12; p12 <= middle_q;
                p20 <= p21; p21 <= p22; p22 <= bottom_q;
                window_valid <= candidate_qq;
            end else begin
                window_valid <= 1'b0;
                p00 <= 8'd0; p01 <= 8'd0; p02 <= 8'd0;
                p10 <= 8'd0; p11 <= 8'd0; p12 <= 8'd0;
                p20 <= 8'd0; p21 <= 8'd0; p22 <= 8'd0;
            end
        end
    end

    wire [11:0] weighted_sum =
        {4'd0, p00} + {3'd0, p01, 1'b0} + {4'd0, p02} +
        {3'd0, p10, 1'b0} + {2'd0, p11, 2'b00} + {3'd0, p12, 1'b0} +
        {4'd0, p20} + {3'd0, p21, 1'b0} + {4'd0, p22};
    wire [11:0] rounded_sum = weighted_sum + 12'd8;
    assign gray_out = window_valid ? rounded_sum[11:4] : 8'd0;
    // Original grayscale pixel at the centre of this Gaussian window.
    // Carry it through the Sobel stage for pixel-accurate edge overlay.
    assign gray_center_out = window_valid ? p11 : 8'd0;
endmodule

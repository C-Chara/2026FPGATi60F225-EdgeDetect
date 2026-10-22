`timescale 1ns/1ps

// Streaming 3x3 Sobel filter for the active HDMI pixel stream.
// The result is intentionally delayed by one line and a few pixels;
// HDMI timing itself remains unchanged. The first two rows/columns are black.
module sobel_stream #(
    parameter integer H_ACTIVE = 1280,
    parameter [11:0] THRESHOLD = 12'd220
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       vsync_n,
    input  wire       pixel_valid,
    input  wire [7:0] gray_in,
    input  wire [7:0] gray_center_in,
    output wire [7:0] edge_out,
    output wire [11:0] magnitude_out,
    output wire [1:0] direction_out,
    output wire        window_valid_out,
    output reg  [7:0] gray_center_out
);
    // One byte per active pixel in each of the two preceding lines.
    // Keep RAM read registers out of the resettable control process so
    // Efinity can infer synchronous block RAM instead of thousands of FFs.
    reg [7:0] line_1 [0:H_ACTIVE-1];
    reg [7:0] line_2 [0:H_ACTIVE-1];
    reg [7:0] line_1_q;
    reg [7:0] line_2_q;
    reg [7:0] center_line [0:H_ACTIVE-1];
    reg [7:0] center_line_q;
    reg [10:0] column;
    reg [10:0] column_q;
    reg [1:0] rows_seen;
    reg valid_d;
    reg valid_q;
    reg valid_qq;
    reg candidate_q;
    reg candidate_qq;
    reg window_valid;
    reg [7:0] gray_q;
    reg [7:0] middle_q;
    reg [7:0] bottom_q;
    reg [7:0] center_middle_q;
    reg [7:0] center_right;

    reg [7:0] p00, p01, p02;
    reg [7:0] p10, p11, p12;
    reg [7:0] p20, p21, p22;

    // First RAM supplies the previous row. One cycle later, that byte is
    // written into the second RAM at its delayed column address.
    always @(posedge clk) begin
        if (pixel_valid) begin
            line_1[column] <= gray_in;
            line_1_q <= line_1[column];
            center_line[column] <= gray_center_in;
            center_line_q <= center_line[column];
        end
        if (valid_q) begin
            line_2[column_q] <= line_1_q;
            line_2_q <= line_2[column_q];
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            column       <= 11'd0;
            column_q     <= 11'd0;
            rows_seen    <= 2'd0;
            valid_d      <= 1'b0;
            valid_q      <= 1'b0;
            valid_qq     <= 1'b0;
            candidate_q  <= 1'b0;
            candidate_qq <= 1'b0;
            window_valid <= 1'b0;
            gray_q       <= 8'd0;
            middle_q     <= 8'd0;
            bottom_q     <= 8'd0;
            center_middle_q <= 8'd0;
            center_right <= 8'd0;
            gray_center_out <= 8'd0;
            p00 <= 8'd0; p01 <= 8'd0; p02 <= 8'd0;
            p10 <= 8'd0; p11 <= 8'd0; p12 <= 8'd0;
            p20 <= 8'd0; p21 <= 8'd0; p22 <= 8'd0;
        end else begin
            valid_d <= pixel_valid;
            valid_q <= pixel_valid;
            valid_qq <= valid_q;
            column_q <= column;
            gray_q <= gray_in;
            middle_q <= line_1_q;
            bottom_q <= gray_q;
            center_middle_q <= center_line_q;
            candidate_q <= pixel_valid && (rows_seen >= 2'd2) && (column >= 11'd2);
            candidate_qq <= candidate_q;

            if (!vsync_n) begin
                column       <= 11'd0;
                rows_seen    <= 2'd0;
            end else if (pixel_valid) begin
                if (column == H_ACTIVE-1)
                    column <= 11'd0;
                else
                    column <= column + 11'd1;

                if (!valid_d && rows_seen != 2'd3)
                    rows_seen <= rows_seen + 2'd1;
            end else begin
                column       <= 11'd0;
            end

            if (valid_qq) begin
                p00 <= p01; p01 <= p02; p02 <= line_2_q;
                p10 <= p11; p11 <= p12; p12 <= middle_q;
                p20 <= p21; p21 <= p22; p22 <= bottom_q;
                gray_center_out <= center_right;
                center_right <= center_middle_q;
                window_valid <= candidate_qq;
            end else begin
                window_valid <= 1'b0;
                gray_center_out <= 8'd0;
                center_right <= 8'd0;
                p00 <= 8'd0; p01 <= 8'd0; p02 <= 8'd0;
                p10 <= 8'd0; p11 <= 8'd0; p12 <= 8'd0;
                p20 <= 8'd0; p21 <= 8'd0; p22 <= 8'd0;
            end
        end
    end

    wire [9:0] left_sum   = {2'd0, p00} + {1'd0, p10, 1'b0} + {2'd0, p20};
    wire [9:0] right_sum  = {2'd0, p02} + {1'd0, p12, 1'b0} + {2'd0, p22};
    wire [9:0] top_sum   = {2'd0, p00} + {1'd0, p01, 1'b0} + {2'd0, p02};
    wire [9:0] bottom_sum = {2'd0, p20} + {1'd0, p21, 1'b0} + {2'd0, p22};

    wire signed [10:0] gx = $signed({1'b0, right_sum}) - $signed({1'b0, left_sum});
    wire signed [10:0] gy = $signed({1'b0, bottom_sum}) - $signed({1'b0, top_sum});
    wire [10:0] abs_gx = gx[10] ? -gx : gx;
    wire [10:0] abs_gy = gy[10] ? -gy : gy;
    wire [11:0] magnitude = {1'b0, abs_gx} + {1'b0, abs_gy};
    // Coarse gradient direction for non-maximum suppression: horizontal,
    // vertical, NW-SE or NE-SW. This only routes the existing Sobel result.
    assign direction_out = ({abs_gy, 1'b0} <= {1'b0, abs_gx}) ? 2'd0 :
                           ({abs_gx, 1'b0} <= {1'b0, abs_gy}) ? 2'd1 :
                           (gx[10] == gy[10]) ? 2'd2 : 2'd3;

    assign edge_out = window_valid && (magnitude >= THRESHOLD) ? 8'hff : 8'h00;
    assign magnitude_out = magnitude;
    assign window_valid_out = window_valid;
endmodule

`timescale 1ns/1ps

// Streaming 3x3 non-maximum suppression on Sobel magnitude. The direction
// selects the two neighbours on either side of the gradient. A one-sided
// strict comparison gives a deterministic one-pixel winner on flat peaks.
module nms_stream #(
    parameter integer H_ACTIVE = 1278
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        vsync_n,
    input  wire        pixel_valid,
    input  wire [11:0] magnitude_in,
    input  wire [1:0]  direction_in,
    input  wire [7:0]  gray_in,
    output wire [11:0] magnitude_out,
    output wire [11:0] raw_magnitude_out,
    output wire [11:0] neighbor_peak_out,
    output wire [11:0] neighbor_a_out,
    output wire [11:0] neighbor_b_out,
    output reg         pixel_valid_out,
    output wire [7:0]  gray_out,
    output wire [1:0]  direction_out
);
    // Previous row also carries the direction and original gray value of
    // the centre pixel. Only magnitude is needed from two rows back.
    reg [21:0] line_1 [0:H_ACTIVE-1];
    reg [11:0] line_2 [0:H_ACTIVE-1];
    reg [21:0] line_1_q;
    reg [11:0] line_2_q;
    reg [10:0] column;
    reg [10:0] column_q;
    reg [1:0] rows_seen;
    reg valid_d, valid_q, valid_qq;
    reg candidate_q, candidate_qq;
    reg [11:0] magnitude_q, middle_magnitude_q, bottom_magnitude_q;
    reg [1:0] middle_direction_q, center_direction_right, center_direction;
    reg [7:0] middle_gray_q, center_gray_right, center_gray;
    reg [11:0] p00, p01, p02;
    reg [11:0] p10, p11, p12;
    reg [11:0] p20, p21, p22;

    // Separate non-resettable RAM process is required for block-RAM inference.
    always @(posedge clk) begin
        if (pixel_valid) begin
            line_1[column] <= {magnitude_in, direction_in, gray_in};
            line_1_q <= line_1[column];
        end
        if (valid_q) begin
            line_2[column_q] <= line_1_q[21:10];
            line_2_q <= line_2[column_q];
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            column <= 11'd0;
            column_q <= 11'd0;
            rows_seen <= 2'd0;
            valid_d <= 1'b0;
            valid_q <= 1'b0;
            valid_qq <= 1'b0;
            candidate_q <= 1'b0;
            candidate_qq <= 1'b0;
            pixel_valid_out <= 1'b0;
            magnitude_q <= 12'd0;
            middle_magnitude_q <= 12'd0;
            bottom_magnitude_q <= 12'd0;
            middle_direction_q <= 2'd0;
            center_direction_right <= 2'd0;
            center_direction <= 2'd0;
            middle_gray_q <= 8'd0;
            center_gray_right <= 8'd0;
            center_gray <= 8'd0;
            p00 <= 12'd0; p01 <= 12'd0; p02 <= 12'd0;
            p10 <= 12'd0; p11 <= 12'd0; p12 <= 12'd0;
            p20 <= 12'd0; p21 <= 12'd0; p22 <= 12'd0;
        end else begin
            valid_d <= pixel_valid;
            valid_q <= pixel_valid;
            valid_qq <= valid_q;
            column_q <= column;
            magnitude_q <= magnitude_in;
            middle_magnitude_q <= line_1_q[21:10];
            bottom_magnitude_q <= magnitude_q;
            middle_direction_q <= line_1_q[9:8];
            middle_gray_q <= line_1_q[7:0];
            candidate_q <= pixel_valid && (rows_seen >= 2'd2) && (column >= 11'd2);
            candidate_qq <= candidate_q;

            if (!vsync_n) begin
                column <= 11'd0;
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

            if (valid_qq) begin
                p00 <= p01; p01 <= p02; p02 <= line_2_q;
                p10 <= p11; p11 <= p12; p12 <= middle_magnitude_q;
                p20 <= p21; p21 <= p22; p22 <= bottom_magnitude_q;
                center_direction <= center_direction_right;
                center_direction_right <= middle_direction_q;
                center_gray <= center_gray_right;
                center_gray_right <= middle_gray_q;
                pixel_valid_out <= candidate_qq;
            end else begin
                p00 <= 12'd0; p01 <= 12'd0; p02 <= 12'd0;
                p10 <= 12'd0; p11 <= 12'd0; p12 <= 12'd0;
                p20 <= 12'd0; p21 <= 12'd0; p22 <= 12'd0;
                center_direction <= 2'd0;
                center_direction_right <= 2'd0;
                center_gray <= 8'd0;
                center_gray_right <= 8'd0;
                pixel_valid_out <= 1'b0;
            end
        end
    end

    reg [11:0] neighbor_a, neighbor_b;
    always @* begin
        case (center_direction)
            2'd0: begin neighbor_a = p10; neighbor_b = p12; end
            2'd1: begin neighbor_a = p01; neighbor_b = p21; end
            2'd2: begin neighbor_a = p00; neighbor_b = p22; end
            default: begin neighbor_a = p02; neighbor_b = p20; end
        endcase
    end
    wire local_maximum = (p11 != 12'd0) &&
                         (p11 >= neighbor_a) && (p11 > neighbor_b);
    assign magnitude_out = pixel_valid_out && local_maximum ? p11 : 12'd0;
    assign raw_magnitude_out = pixel_valid_out ? p11 : 12'd0;
    assign neighbor_peak_out = pixel_valid_out ?
        ((neighbor_a > neighbor_b) ? neighbor_a : neighbor_b) : 12'd0;
    assign neighbor_a_out = pixel_valid_out ? neighbor_a : 12'd0;
    assign neighbor_b_out = pixel_valid_out ? neighbor_b : 12'd0;
    assign gray_out = pixel_valid_out ? center_gray : 8'd0;
    assign direction_out = pixel_valid_out ? center_direction : 2'd0;
endmodule

`timescale 1ns/1ps

// Raster-order, one-pass local edge linking. This is a lightweight
// hysteresis approximation, not full recursive Canny connectivity.
// Strong pixels are always retained. Weak pixels may connect to a retained
// pixel within two columns in the previous row, across a one-pixel horizontal
// gap, or to a strong pixel immediately to the right in the same row.
module hysteresis_stream #(
    parameter integer H_ACTIVE = 1278,
    parameter [11:0] LOW_THRESHOLD = 12'd60,
    parameter [11:0] HIGH_THRESHOLD = 12'd120,
    parameter NMS_BRIDGE_ENABLE = 1'b0
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        vsync_n,
    input  wire        pixel_valid,
    input  wire [11:0] magnitude_in,
    input  wire [11:0] raw_magnitude_in,
    input  wire [7:0]  gray_in,
    input  wire [11:0] low_threshold_in,
    input  wire [11:0] high_threshold_in,
    output reg  [7:0]  edge_out,
    output reg  [7:0]  gray_out,
    output reg         pixel_valid_out
);
    reg prev_edge [0:H_ACTIVE-1];
    reg prev_edge_q;
    reg [10:0] column;
    reg [10:0] column_d;
    reg valid_d;
    reg strong_d;
    reg weak_d;
    reg bridge_d;
    reg [7:0] gray_d;
    reg prior_row_available;
    reg prior_d;
    reg left_kept;
    reg left2_kept;
    reg up_right_kept;
    reg up_kept;
    reg up_left_kept;
    reg up_left2_kept;

    wire [10:0] read_column = (column >= H_ACTIVE-2) ? H_ACTIVE-1 : column + 11'd2;
    wire linked_to_prior = prior_d &&
        (prev_edge_q || up_right_kept || up_kept || up_left_kept || up_left2_kept);
    wire [11:0] low_threshold_used = (low_threshold_in == 12'd0) ? LOW_THRESHOLD : low_threshold_in;
    wire [11:0] high_threshold_used = (high_threshold_in == 12'd0) ? HIGH_THRESHOLD : high_threshold_in;
    // The input stream is one pixel ahead of strong_d/weak_d here. Looking
    // at that right-hand pixel lets a strong edge retain the weak pixel just
    // before it; the original raster-only link could propagate only after
    // the strong pixel had already been seen.
    wire right_strong = pixel_valid && (magnitude_in >= high_threshold_used);
    // A single pixel suppressed by NMS may bridge two supported edge
    // samples. Require its original Sobel response and a strong pixel on
    // the right, so this cannot grow an edge into a flat background.
    wire bridge_keep = NMS_BRIDGE_ENABLE && bridge_d && right_strong &&
        (left_kept || linked_to_prior);
    wire keep = strong_d ||
        (weak_d && (left_kept || left2_kept || linked_to_prior || right_strong)) ||
        bridge_keep;

    // Read two pixels ahead. While deciding column x on the following
    // clock, the read value and four shift registers cover x+2 through x-2.
    // No reset on the RAM read register so it infers block RAM.
    always @(posedge clk) begin
        if (pixel_valid)
            prev_edge_q <= prev_edge[read_column];
        if (valid_d)
            prev_edge[column_d] <= keep;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            column              <= 11'd0;
            column_d            <= 11'd0;
            valid_d             <= 1'b0;
            strong_d            <= 1'b0;
            weak_d              <= 1'b0;
            bridge_d            <= 1'b0;
            gray_d              <= 8'd0;
            prior_row_available <= 1'b0;
            prior_d             <= 1'b0;
            left_kept           <= 1'b0;
            left2_kept          <= 1'b0;
            up_right_kept       <= 1'b0;
            up_kept             <= 1'b0;
            up_left_kept        <= 1'b0;
            up_left2_kept       <= 1'b0;
            edge_out            <= 8'd0;
            gray_out            <= 8'd0;
            pixel_valid_out    <= 1'b0;
        end else begin
            valid_d <= pixel_valid;
            if (!vsync_n) begin
                column              <= 11'd0;
                prior_row_available <= 1'b0;
            end else if (pixel_valid) begin
                if (column == H_ACTIVE-1)
                    column <= 11'd0;
                else
                    column <= column + 11'd1;
            end else begin
                column <= 11'd0;
                if (valid_d)
                    prior_row_available <= 1'b1;
            end

            if (pixel_valid) begin
                column_d <= column;
                strong_d <= magnitude_in >= high_threshold_used;
                weak_d <= magnitude_in >= low_threshold_used;
                bridge_d <= NMS_BRIDGE_ENABLE &&
                    (magnitude_in < low_threshold_used) &&
                    (raw_magnitude_in >= low_threshold_used);
                gray_d <= gray_in;
                prior_d <= prior_row_available;
            end else begin
                strong_d <= 1'b0;
                weak_d <= 1'b0;
                bridge_d <= 1'b0;
                prior_d <= 1'b0;
            end

            if (valid_d) begin
                edge_out <= keep ? 8'hff : 8'h00;
                gray_out <= gray_d;
                pixel_valid_out <= 1'b1;
                left2_kept <= left_kept;
                left_kept <= keep;
                up_left2_kept <= up_left_kept;
                up_left_kept <= up_kept;
                up_kept <= up_right_kept;
                up_right_kept <= prev_edge_q;
            end else begin
                edge_out <= 8'd0;
                gray_out <= 8'd0;
                pixel_valid_out <= 1'b0;
                left_kept <= 1'b0;
                left2_kept <= 1'b0;
                up_right_kept <= 1'b0;
                up_left_kept <= 1'b0;
                up_left2_kept <= 1'b0;
                up_kept <= 1'b0;
            end
        end
    end
endmodule

`timescale 1ns/1ps

// Temporal hysteresis for a binary edge stream. A newly detected edge turns
// on immediately. A previously accepted edge stays on while its raw Sobel
// magnitude remains above the lower release threshold, even if the spatial
// edge detector temporarily rejects it. The stored bit is the stable state,
// rather than the raw edge from the preceding frame.
module edge_frame_hold #(
    parameter integer H_ACTIVE = 1278,
    parameter integer V_ACTIVE = 720,
    parameter PEAK_GUARD_ENABLE = 1'b0,
    parameter [12:0] PEAK_TOLERANCE = 13'd8,
    // When enabled, a new edge must be present at the same pixel in two
    // consecutive frames. This is a one-frame temporal de-speckle filter.
    // It uses the existing frame RAM and therefore adds no full-frame RAM.
    parameter TEMPORAL_CONFIRM_ENABLE = 1'b0
)(
    input  wire       clk,
    input  wire       rst_n,
    input  wire       vsync_n,
    input  wire       pixel_valid,
    input  wire [7:0] edge_in,
    input  wire [7:0] gray_in,
    input  wire [11:0] magnitude_in,
    input  wire [11:0] neighbor_peak_in,
    input  wire [11:0] release_threshold_in,
    output reg  [7:0] edge_out,
    output reg  [7:0] gray_out
);
    localparam integer FRAME_PIXELS = H_ACTIVE * V_ACTIVE;
    reg prev_edge [0:FRAME_PIXELS-1];
    reg [20:0] frame_addr;
    reg [20:0] frame_addr_d;
    reg prev_edge_q;
    reg prev_frame_ready;
    reg frame_seen;
    reg vsync_n_d;
    reg valid_d;
    reg [7:0] edge_d;
    reg [7:0] gray_d;
    reg [11:0] magnitude_d;
    reg [11:0] neighbor_peak_d;
    wire near_local_peak = !PEAK_GUARD_ENABLE ||
        ({1'b0, magnitude_d} + PEAK_TOLERANCE >= {1'b0, neighbor_peak_d});
    wire stable_keep = (edge_d != 8'd0) ||
        (prev_frame_ready && prev_edge_q &&
         (magnitude_d >= release_threshold_in) && near_local_peak);
    wire temporal_keep = !TEMPORAL_CONFIRM_ENABLE ? stable_keep :
        (prev_frame_ready && prev_edge_q && (edge_d != 8'd0));
    wire temporal_state_write = TEMPORAL_CONFIRM_ENABLE ?
        (edge_d != 8'd0) : stable_keep;

    // Read the old state at the current pixel, then write the new state one
    // clock later at the registered address. Keep the RAM read register out
    // of reset to preserve block-RAM inference.
    always @(posedge clk) begin
        if (pixel_valid)
            prev_edge_q <= prev_edge[frame_addr];
        if (valid_d)
            prev_edge[frame_addr_d] <= temporal_state_write;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_addr <= 21'd0;
            frame_addr_d <= 21'd0;
            prev_frame_ready <= 1'b0;
            frame_seen       <= 1'b0;
            vsync_n_d        <= 1'b1;
            valid_d    <= 1'b0;
            edge_d     <= 8'd0;
            gray_d     <= 8'd0;
            magnitude_d <= 12'd0;
            neighbor_peak_d <= 12'd0;
            edge_out   <= 8'd0;
            gray_out   <= 8'd0;
        end else begin
            valid_d <= pixel_valid;
            edge_d  <= edge_in;
            gray_d  <= gray_in;
            magnitude_d <= magnitude_in;
            neighbor_peak_d <= neighbor_peak_in;
            vsync_n_d <= vsync_n;
            if (pixel_valid)
                frame_addr_d <= frame_addr;

            if (!vsync_n) begin
                frame_addr <= 21'd0;
                // lcd_vs is low for several clocks. Latch the completed
                // frame only on its falling edge, rather than clearing the
                // flag again on every low clock.
                if (vsync_n_d) begin
                    prev_frame_ready <= frame_seen;
                    frame_seen       <= 1'b0;
                end
            end else if (pixel_valid) begin
                frame_seen <= 1'b1;
                if (frame_addr == FRAME_PIXELS-1)
                    frame_addr <= 21'd0;
                else
                    frame_addr <= frame_addr + 21'd1;
            end

            if (valid_d) begin
                edge_out <= temporal_keep ? 8'hff : 8'd0;
                gray_out <= gray_d;
            end else begin
                edge_out <= 8'd0;
                gray_out <= 8'd0;
            end
        end
    end
endmodule

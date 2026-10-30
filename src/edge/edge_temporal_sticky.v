`timescale 1ns/1ps

// Temporal ridge hysteresis for the NMS-thinned binary edge stream.
//
// A real edge that falls between two pixel columns gives two almost equal
// Sobel responses, so camera noise makes NMS pick a different winner from
// frame to frame and the one-pixel line shimmers sideways. This stage makes
// the previous winner sticky:
//   held       = on last frame, raw gradient still above the low threshold
//                and still close to the larger of its two gradient neighbours
//   challenger = new edge pixel with a gradient neighbour that was on last
//                frame, is still above the low threshold and is still about
//                as strong as the new pixel; the challenger is suppressed
//   onset      = a pixel that was off may only turn on when its raw gradient
//                reaches onset_threshold_in, one of its eight neighbours
//                was on last frame, or its left or upper neighbour is on in
//                this frame; marginal pixels cannot pop in alone, while a
//                weak line attached to a strong pixel fills in at once
//   keep       = held | (edge_in & ~challenger & onset)
// "Close" is relative: value + value/2^TOLERANCE_SHIFT + TOLERANCE_BASE.
// neighbor_a_in/neighbor_b_in are the two raw magnitudes NMS compared
// against, in the same order as nms_stream (left/up side first).
//
// The rule only reads the previous displayed state, so showing the same DDR
// frame twice (30 fps camera, 60 Hz display) reproduces the same output
// instead of alternating between a filtered and an unfiltered picture.
//
// The frame RAM is read one row ahead of the pixel being decided; two
// one-bit line RAMs supply the current and upper rows, so all nine state
// bits come from the previous pass. Latency: 3 clocks, no added rows.
// The first row of the stream has no stored state and passes edge_in.
// HOLD_ENABLE = 0 switches the previous-frame terms off: the output is the
// current frame's edge with the same latency (the state is still stored,
// so toggle_out still measures flicker).
module edge_temporal_sticky #(
    parameter integer H_ACTIVE = 1276,
    parameter integer V_ACTIVE = 720,
    parameter integer TOLERANCE_SHIFT = 2,
    parameter [11:0] TOLERANCE_BASE = 12'd8,
    parameter ONSET_GATE_ENABLE = 1'b1,
    parameter HOLD_ENABLE = 1'b1
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        vsync_n,
    input  wire        pixel_valid,
    input  wire [7:0]  edge_in,
    input  wire [7:0]  gray_in,
    input  wire [11:0] magnitude_in,
    input  wire [11:0] neighbor_a_in,
    input  wire [11:0] neighbor_b_in,
    input  wire [1:0]  direction_in,
    input  wire [11:0] release_threshold_in,
    input  wire [11:0] onset_threshold_in,
    output reg  [7:0]  edge_out,
    output reg  [7:0]  gray_out,
    output reg  [1:0]  direction_out,
    // 1 for one clock when this pixel's decision differs from the
    // previous pass (an edge pixel appeared or disappeared).
    output reg         toggle_out
);
    localparam integer FRAME_PIXELS = H_ACTIVE * V_ACTIVE;
    reg state_ram [0:FRAME_PIXELS-1];
    reg line_mid [0:H_ACTIVE-1];
    reg line_top [0:H_ACTIVE-1];
    reg below_q, mid_q, top_q;

    reg [20:0] frame_addr, read_addr;
    reg [20:0] write_addr_1, write_addr_2;
    reg [10:0] column, column_1, column_2;
    reg line_now [0:H_ACTIVE-1];
    reg now_q, now_l, now_c, keep_left;
    reg [9:0] row, frame_rows;
    reg prev_frame_ready, frame_seen, vsync_n_d;
    reg valid_1, valid_2;
    reg edge_1, edge_2;
    reg [7:0] gray_1, gray_2;
    reg [1:0] direction_1, direction_2;
    reg hold_ok_1, hold_ok_2;
    reg rival_a_ok_1, rival_a_ok_2;
    reg rival_b_ok_1, rival_b_ok_2;
    reg onset_strong_1, onset_strong_2;
    reg mid_ok_1, mid_ok_2;
    reg top_ok_1, top_ok_2;
    reg bottom_ok_1, bottom_ok_2;
    reg top_l, top_c, mid_l, mid_c, bottom_l, bottom_c;

    wire [13:0] magnitude_reach = {2'b00, magnitude_in} +
        ({2'b00, magnitude_in} >> TOLERANCE_SHIFT) + {2'b00, TOLERANCE_BASE};
    wire [13:0] neighbor_a_reach = {2'b00, neighbor_a_in} +
        ({2'b00, neighbor_a_in} >> TOLERANCE_SHIFT) + {2'b00, TOLERANCE_BASE};
    wire [13:0] neighbor_b_reach = {2'b00, neighbor_b_in} +
        ({2'b00, neighbor_b_in} >> TOLERANCE_SHIFT) + {2'b00, TOLERANCE_BASE};
    wire hold_ok = (magnitude_in >= release_threshold_in) &&
        (magnitude_reach >= {2'b00, neighbor_a_in}) &&
        (magnitude_reach >= {2'b00, neighbor_b_in});
    wire rival_a_ok = (neighbor_a_in >= release_threshold_in) &&
        (neighbor_a_reach >= {2'b00, magnitude_in});
    wire rival_b_ok = (neighbor_b_in >= release_threshold_in) &&
        (neighbor_b_reach >= {2'b00, magnitude_in});

    // Stage 2 sees the centre column in *_c, the left column in *_l and the
    // right column still on the RAM outputs (valid while stage 1 is valid).
    wire mid_use = prev_frame_ready && mid_ok_2;
    wire top_use = prev_frame_ready && top_ok_2;
    wire bottom_use = prev_frame_ready && bottom_ok_2;
    wire state_c = mid_use && mid_c;
    wire state_l = mid_use && mid_l;
    wire state_r = mid_use && valid_1 && mid_q;
    wire above_l = top_use && top_l;
    wire above_c = top_use && top_c;
    wire above_r = top_use && valid_1 && top_q;
    wire below_l = bottom_use && bottom_l;
    wire below_c = bottom_use && bottom_c;
    wire below_r = bottom_use && valid_1 && below_q;
    reg side_a_state, side_b_state;
    always @* begin
        case (direction_2)
            2'd0: begin side_a_state = state_l; side_b_state = state_r; end
            2'd1: begin side_a_state = above_c; side_b_state = below_c; end
            2'd2: begin side_a_state = above_l; side_b_state = below_r; end
            default: begin side_a_state = above_r; side_b_state = below_l; end
        endcase
    end
    wire held = state_c && hold_ok_2;
    wire challenger = edge_2 && !state_c &&
        ((side_a_state && rival_a_ok_2) || (side_b_state && rival_b_ok_2));
    wire any_neighbor_state = state_l || state_r || above_l || above_c ||
        above_r || below_l || below_c || below_r;
    // Decisions already made in this pass: the pixel to the left and the
    // three pixels of the row above.
    wire now_neighbor = keep_left || (mid_ok_2 &&
        (now_l || now_c || (valid_1 && now_q)));
    wire onset_ok = !ONSET_GATE_ENABLE || state_c || onset_strong_2 ||
        any_neighbor_state || now_neighbor;
    wire keep = HOLD_ENABLE ? (held || (edge_2 && !challenger && onset_ok)) : edge_2;

    // RAM read registers stay out of reset to preserve block-RAM inference.
    always @(posedge clk) begin
        if (pixel_valid)
            below_q <= state_ram[read_addr];
        if (valid_2)
            state_ram[write_addr_2] <= keep;
    end
    always @(posedge clk) begin
        if (pixel_valid)
            mid_q <= line_mid[column];
        if (valid_1)
            line_mid[column_1] <= below_q;
    end
    always @(posedge clk) begin
        if (pixel_valid)
            top_q <= line_top[column];
        if (valid_1)
            line_top[column_1] <= mid_q;
    end
    always @(posedge clk) begin
        if (pixel_valid)
            now_q <= line_now[column];
        if (valid_2)
            line_now[column_2] <= keep;
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_addr <= 21'd0;
            read_addr <= H_ACTIVE;
            write_addr_1 <= 21'd0;
            write_addr_2 <= 21'd0;
            column <= 11'd0;
            column_1 <= 11'd0;
            column_2 <= 11'd0;
            now_l <= 1'b0; now_c <= 1'b0; keep_left <= 1'b0;
            row <= 10'd0;
            frame_rows <= 10'd0;
            prev_frame_ready <= 1'b0;
            frame_seen <= 1'b0;
            vsync_n_d <= 1'b1;
            valid_1 <= 1'b0;
            valid_2 <= 1'b0;
            edge_1 <= 1'b0;
            edge_2 <= 1'b0;
            gray_1 <= 8'd0;
            gray_2 <= 8'd0;
            direction_1 <= 2'd0;
            direction_2 <= 2'd0;
            hold_ok_1 <= 1'b0;
            hold_ok_2 <= 1'b0;
            rival_a_ok_1 <= 1'b0;
            rival_a_ok_2 <= 1'b0;
            rival_b_ok_1 <= 1'b0;
            rival_b_ok_2 <= 1'b0;
            onset_strong_1 <= 1'b0;
            onset_strong_2 <= 1'b0;
            mid_ok_1 <= 1'b0;
            mid_ok_2 <= 1'b0;
            top_ok_1 <= 1'b0;
            top_ok_2 <= 1'b0;
            bottom_ok_1 <= 1'b0;
            bottom_ok_2 <= 1'b0;
            top_l <= 1'b0; top_c <= 1'b0;
            mid_l <= 1'b0; mid_c <= 1'b0;
            bottom_l <= 1'b0; bottom_c <= 1'b0;
            edge_out <= 8'd0;
            gray_out <= 8'd0;
            direction_out <= 2'd0;
            toggle_out <= 1'b0;
        end else begin
            vsync_n_d <= vsync_n;
            valid_1 <= pixel_valid;
            valid_2 <= valid_1;

            if (!vsync_n) begin
                frame_addr <= 21'd0;
                read_addr <= H_ACTIVE;
                column <= 11'd0;
                row <= 10'd0;
                // lcd_vs stays low for several clocks; latch once.
                if (vsync_n_d) begin
                    prev_frame_ready <= frame_seen;
                    frame_seen <= 1'b0;
                    frame_rows <= row;
                end
            end else if (pixel_valid) begin
                frame_seen <= 1'b1;
                frame_addr <= frame_addr + 21'd1;
                read_addr <= read_addr + 21'd1;
                column <= column + 11'd1;
            end else begin
                column <= 11'd0;
                if (valid_1 && row != 10'd1023)
                    row <= row + 10'd1;
            end

            if (pixel_valid) begin
                column_1 <= column;
                write_addr_1 <= frame_addr;
                edge_1 <= edge_in != 8'd0;
                gray_1 <= gray_in;
                direction_1 <= direction_in;
                hold_ok_1 <= hold_ok;
                rival_a_ok_1 <= rival_a_ok;
                rival_b_ok_1 <= rival_b_ok;
                onset_strong_1 <= magnitude_in >= onset_threshold_in;
                mid_ok_1 <= row != 10'd0;
                top_ok_1 <= row >= 10'd2;
                bottom_ok_1 <= (row + 10'd1) != frame_rows;
            end

            write_addr_2 <= write_addr_1;
            column_2 <= column_1;
            edge_2 <= edge_1;
            gray_2 <= gray_1;
            direction_2 <= direction_1;
            hold_ok_2 <= hold_ok_1;
            rival_a_ok_2 <= rival_a_ok_1;
            rival_b_ok_2 <= rival_b_ok_1;
            onset_strong_2 <= onset_strong_1;
            mid_ok_2 <= mid_ok_1;
            top_ok_2 <= top_ok_1;
            bottom_ok_2 <= bottom_ok_1;

            if (valid_1) begin
                top_l <= top_c; top_c <= top_q;
                mid_l <= mid_c; mid_c <= mid_q;
                bottom_l <= bottom_c; bottom_c <= below_q;
                now_l <= now_c; now_c <= now_q;
            end else begin
                now_l <= 1'b0; now_c <= 1'b0;
                top_l <= 1'b0; top_c <= 1'b0;
                mid_l <= 1'b0; mid_c <= 1'b0;
                bottom_l <= 1'b0; bottom_c <= 1'b0;
            end

            if (valid_2) begin
                edge_out <= keep ? 8'hff : 8'd0;
                keep_left <= keep;
                toggle_out <= mid_use && (keep != mid_c);
                gray_out <= gray_2;
                direction_out <= direction_2;
            end else begin
                edge_out <= 8'd0;
                gray_out <= 8'd0;
                direction_out <= 2'd0;
                keep_left <= 1'b0;
                toggle_out <= 1'b0;
            end
        end
    end
endmodule

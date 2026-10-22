`timescale 1ns/1ps

// Removes isolated edge fragments from the binary edge stream.
// An edge pixel is kept when its 7x5 neighbourhood (7 columns, 5 rows,
// centred on it, the pixel included) holds at least MIN_COUNT edge pixels.
// With MIN_COUNT = 4, single dots and fragments of up to three pixels go;
// a line keeps its body, only the last pixel of a vertical line end drops.
//
// Timing: the output for a centre pixel appears two active rows and
// LATENCY clocks after that pixel's input. The horizontal window shifts every
// clock (blanking shifts in zeros), the same way the RGB align pipeline
// delays the colour image, so delaying the image by 2 rows + LATENCY keeps
// edges and image aligned.
//
// toggle_in (from the temporal stage) is carried to the centre pixel and
// reported only for pixels that pass the filter.
module edge_fragment_filter #(
    parameter integer H_ACTIVE = 1280,
    parameter integer MIN_COUNT = 4
)(
    input  wire clk,
    input  wire rst_n,
    input  wire vsync_n,
    input  wire enable,
    input  wire pixel_valid,
    input  wire edge_in,
    input  wire toggle_in,
    output reg  edge_out,
    output reg  toggle_out
);
    localparam integer LATENCY = 6;

    // Line buffer word: edge bits of rows r-1..r-4 and toggle bits of rows
    // r-1, r-2 at this column.
    reg [5:0] line_buf [0:H_ACTIVE-1];
    reg [5:0] line_q;
    reg [10:0] column, column_d1;
    reg [2:0] rows_seen;
    reg valid_d1, edge_d1, toggle_d1;

    always @(posedge clk) begin
        if (pixel_valid)
            line_q <= line_buf[column];
        if (valid_d1)
            line_buf[column_d1] <= {line_q[4], toggle_d1, line_q[2:0], edge_d1};
    end

    // Column of 5 rows at this clock, top (r-4) to bottom (r).
    wire [4:0] col_bits = valid_d1 ?
        {line_q[3] & (rows_seen >= 3'd4), line_q[2] & (rows_seen >= 3'd3),
         line_q[1] & (rows_seen >= 3'd2), line_q[0] & (rows_seen >= 3'd1), edge_d1} : 5'd0;
    wire centre_bit = valid_d1 && rows_seen >= 3'd2 && line_q[1];
    wire centre_toggle = valid_d1 && rows_seen >= 3'd2 && line_q[5];
    wire [2:0] col_count = col_bits[0] + col_bits[1] + col_bits[2] + col_bits[3] + col_bits[4];

    reg [2:0] count_sh [0:6];
    reg [6:0] centre_sh, toggle_sh;
    wire [5:0] window_sum = count_sh[0] + count_sh[1] + count_sh[2] + count_sh[3] +
                            count_sh[4] + count_sh[5] + count_sh[6];
    integer i;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            column <= 11'd0; column_d1 <= 11'd0; rows_seen <= 3'd0;
            valid_d1 <= 1'b0; edge_d1 <= 1'b0; toggle_d1 <= 1'b0;
            centre_sh <= 7'd0; toggle_sh <= 7'd0;
            for (i = 0; i < 7; i = i + 1) count_sh[i] <= 3'd0;
            edge_out <= 1'b0; toggle_out <= 1'b0;
        end else begin
            valid_d1 <= pixel_valid;
            edge_d1 <= pixel_valid && edge_in;
            toggle_d1 <= pixel_valid && toggle_in;
            column_d1 <= column;
            if (!vsync_n) begin
                column <= 11'd0;
                rows_seen <= 3'd0;
            end else if (pixel_valid) begin
                if (column == H_ACTIVE-1) begin
                    column <= 11'd0;
                    if (rows_seen != 3'd7) rows_seen <= rows_seen + 3'd1;
                end else begin
                    column <= column + 11'd1;
                end
            end else begin
                column <= 11'd0;
            end

            count_sh[0] <= col_count;
            for (i = 1; i < 7; i = i + 1) count_sh[i] <= count_sh[i-1];
            centre_sh <= {centre_sh[5:0], centre_bit};
            toggle_sh <= {toggle_sh[5:0], centre_toggle};

            // count_sh[3] / centre_sh[3] is the window centre.
            if (!enable) begin
                edge_out <= centre_sh[3];
                toggle_out <= toggle_sh[3];
            end else begin
                edge_out <= centre_sh[3] && window_sum >= MIN_COUNT;
                toggle_out <= toggle_sh[3] && window_sum >= MIN_COUNT;
            end
        end
    end
endmodule

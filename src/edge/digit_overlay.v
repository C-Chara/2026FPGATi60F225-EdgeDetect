`timescale 1ns/1ps

// Draws the digit_reader results: an orange outline around each recognised
// digit and the digit itself (5 x 7 font, 3x) above the box (below it near
// the top of the picture). Two-clock pipeline; de/hs/vs are delayed with it.
module digit_overlay #(
    parameter integer N = 4,
    // Screen position of detector sample (0, 0), as in shape_overlay
    parameter integer X_OFF = 0,
    parameter integer Y_OFF = 0
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    input  wire        vs_in, hs_in, de_in,      // vs active low
    input  wire [23:0] rgb_in,
    input  wire [2:0]  slot_count,
    input  wire [N*38-1:0] slot_box,
    input  wire [N*4-1:0]  slot_digit,
    output reg         vs_out, hs_out, de_out,
    output reg  [23:0] rgb_out
);
    reg [10:0] x;
    reg [9:0]  y;
    reg        de_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin x <= 0; y <= 0; de_d <= 0; end
        else if (!vs_in) begin x <= 0; y <= 0; de_d <= 0; end
        else begin
            de_d <= de_in;
            if (de_in) x <= x + 11'd1;
            else begin
                x <= 0;
                if (de_d) y <= y + 10'd1;
            end
        end
    end

    function [34:0] glyph;
        input [3:0] n;
        case (n)
            1: glyph = 35'b00100_01100_00100_00100_00100_00100_01110;
            2: glyph = 35'b01110_10001_00001_00010_00100_01000_11111;
            3: glyph = 35'b11110_00001_00001_01110_00001_00001_11110;
            4: glyph = 35'b00010_00110_01010_10010_11111_00010_00010;
            5: glyph = 35'b11111_10000_10000_11110_00001_00001_11110;
            6: glyph = 35'b01110_10000_10000_11110_10001_10001_01110;
            7: glyph = 35'b11111_00001_00010_00100_01000_01000_01000;
            8: glyph = 35'b01110_10001_10001_01110_10001_10001_01110;
            9: glyph = 35'b01110_10001_10001_01111_00001_00001_01110;
            default: glyph = 35'd0;
        endcase
    endfunction

    // Stage 1: outline, label background and label ink per slot
    reg        line1, bg1, ink1;
    reg        v1, h1, d1;
    reg [23:0] rgb1;
    integer i;
    reg [10:0] bx0, bx1, lx;
    reg [9:0]  by0, by1, ly;
    reg [3:0]  dg;
    reg [10:0] rx;
    reg [9:0]  ry;
    reg [34:0] gb;
    reg        ln, bg, ink;
    always @(posedge clk) begin
        ln = 0; bg = 0; ink = 0;
        for (i = 0; i < N; i = i + 1) begin
            dg  = slot_digit[i*4 +: 4];
            bx0 = {slot_box[i*38+28 +: 10], 1'b0} + X_OFF;
            bx1 = {slot_box[i*38+18 +: 10], 1'b1} + X_OFF;
            by0 = {slot_box[i*38+9 +: 9], 1'b0} + Y_OFF;
            by1 = {slot_box[i*38 +: 9], 1'b1} + Y_OFF;
            if (enable && i < slot_count && dg >= 4'd1 && dg <= 4'd9) begin
                // 2-pixel outline just outside the box
                if (x + 11'd2 >= bx0 && x <= bx1 + 11'd2 && y + 10'd2 >= by0 && y <= by1 + 10'd2 &&
                    !(x >= bx0 && x <= bx1 && y >= by0 && y <= by1))
                    ln = 1;
                // label 19 x 23 above the box (below it near the top)
                lx = bx0;
                ly = (by0 >= 10'd27) ? by0 - 10'd27 : by1 + 10'd4;
                if (x >= lx && x < lx + 11'd19 && y >= ly && y < ly + 10'd23) begin
                    bg = 1;
                    rx = x - lx - 11'd2;
                    ry = y - ly - 10'd1;
                    gb = glyph(dg);
                    if (x >= lx + 11'd2 && rx < 11'd15 && y >= ly + 10'd1 && ry < 10'd21 &&
                        gb[34 - ((ry / 3) * 5 + rx / 3)])
                        ink = 1;
                end
            end
        end
        line1 <= ln; bg1 <= bg; ink1 <= ink;
        v1 <= vs_in; h1 <= hs_in; d1 <= de_in; rgb1 <= rgb_in;
    end

    // Stage 2: colour
    always @(posedge clk) begin
        vs_out <= v1; hs_out <= h1; de_out <= d1;
        rgb_out <= ink1 ? 24'hff9000 : bg1 ? 24'h202020 : line1 ? 24'hff9000 : rgb1;
    end
endmodule

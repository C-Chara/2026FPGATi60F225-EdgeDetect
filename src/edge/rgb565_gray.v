`timescale 1ns/1ps

// RGB565 to 8-bit luma, rounded. Coefficients sum to 256 and are
// implemented explicitly with shifts and additions (no divider).
module rgb565_gray (
    input  wire [15:0] rgb565,
    output wire [7:0]  gray
);
    wire [7:0] red   = {rgb565[15:11], rgb565[15:13]};
    wire [7:0] green = {rgb565[10:5],  rgb565[10:9]};
    wire [7:0] blue  = {rgb565[4:0],   rgb565[4:2]};

    wire [15:0] r = {8'd0, red};
    wire [15:0] g = {8'd0, green};
    wire [15:0] b = {8'd0, blue};

    // 77/256 R + 150/256 G + 29/256 B.
    wire [15:0] r77  = (r << 6) + (r << 3) + (r << 2) + r;
    wire [15:0] g150 = (g << 7) + (g << 4) + (g << 2) + (g << 1);
    wire [15:0] b29  = (b << 4) + (b << 3) + (b << 2) + b;
    wire [15:0] sum  = r77 + g150 + b29 + 16'd128;

    assign gray = sum[15:8];
endmodule

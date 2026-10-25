`timescale 1ns/1ps

// Draws the shape_detector results on the video: a 2-pixel outline around
// every object in its class colour, and (when there are at most LABELS
// objects) the class name above the box:
//   circle 圆形 yellow, ellipse 椭圆 orange, square 正方形 cyan,
//   rectangle 矩形 green, triangle 三角形 magenta.
// Three-clock pipeline; de/hs/vs are delayed with the colour so the picture
// keeps its position.
module shape_overlay #(
    parameter integer MAX_OBJECTS = 32,
    parameter integer LABELS = 8
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    input  wire        vs_in, hs_in, de_in,      // vs active low (lcd_vs)
    input  wire [23:0] rgb_in,
    input  wire [5:0]  obj_count,
    input  wire [MAX_OBJECTS*41-1:0] obj_data,
    output reg         vs_out, hs_out, de_out,
    output reg  [23:0] rgb_out
);
    // Display position of the incoming pixel
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

    function [23:0] cls_rgb;
        input [2:0] c;
        case (c)
            3'd1: cls_rgb = 24'hffff00;
            3'd2: cls_rgb = 24'hff8000;
            3'd3: cls_rgb = 24'h00ffff;
            3'd4: cls_rgb = 24'h00ff00;
            3'd5: cls_rgb = 24'hff00ff;
            default: cls_rgb = 24'hffffff;
        endcase
    endfunction
    function [1:0] cls_len;           // glyphs in the name minus one
        input [2:0] c;
        cls_len = (c == 3'd3 || c == 3'd5) ? 2'd2 : 2'd1;
    endfunction
    function [2:0] cls_glyph;         // glyph code of character k of the name
        input [2:0] c;
        input [1:0] k;
        case (c)
            3'd1: cls_glyph = (k == 0) ? 3'd0 : 3'd1;                       // 圆形
            3'd2: cls_glyph = (k == 0) ? 3'd2 : 3'd0;                       // 椭圆
            3'd3: cls_glyph = (k == 0) ? 3'd3 : (k == 1) ? 3'd4 : 3'd1;    // 正方形
            3'd4: cls_glyph = (k == 0) ? 3'd5 : 3'd1;                       // 矩形
            default: cls_glyph = (k == 0) ? 3'd6 : (k == 1) ? 3'd7 : 3'd1;  // 三角形
        endcase
    endfunction

    // ------------------------------------------------------------------
    // Stage 1: per-object outline hits and per-label box hits.
    reg [MAX_OBJECTS-1:0] hit1;
    reg [LABELS-1:0]      lab1;
    reg [10:0] x1r;
    reg [9:0]  y1r;
    reg        v1, h1, d1;
    reg [23:0] rgb1;
    wire       show_labels = obj_count <= LABELS;
    integer i;
    reg [10:0] bx0, bx1, lx, lw;
    reg [9:0]  by0, by1, ly;
    reg [2:0]  bc;
    always @(posedge clk) begin
        for (i = 0; i < MAX_OBJECTS; i = i + 1) begin
            bc  = obj_data[i*41+38 +: 3];
            bx0 = {obj_data[i*41+28 +: 10], 1'b0};
            bx1 = {obj_data[i*41+18 +: 10], 1'b1};
            by0 = {obj_data[i*41+9 +: 9], 1'b0};
            by1 = {obj_data[i*41 +: 9], 1'b1};
            hit1[i] <= enable && i < obj_count &&
                       x + 11'd2 >= bx0 && x <= bx1 + 11'd2 && y + 10'd2 >= by0 && y <= by1 + 10'd2 &&
                       !(x >= bx0 + 11'd1 && x + 11'd1 <= bx1 && y >= by0 + 10'd1 && y + 10'd1 <= by1);
        end
        for (i = 0; i < LABELS; i = i + 1) begin
            bc  = obj_data[i*41+38 +: 3];
            lx  = {obj_data[i*41+28 +: 10], 1'b0};
            by0 = {obj_data[i*41+9 +: 9], 1'b0};
            by1 = {obj_data[i*41 +: 9], 1'b1};
            ly  = (by0 >= 10'd26) ? by0 - 10'd26 : by1 + 10'd4;
            lw  = (cls_len(bc) == 2'd2) ? 11'd64 : 11'd44;
            lab1[i] <= enable && show_labels && i < obj_count &&
                       x >= lx && x < lx + lw && y >= ly && y < ly + 10'd22;
        end
        x1r <= x; y1r <= y;
        v1 <= vs_in; h1 <= hs_in; d1 <= de_in;
        rgb1 <= rgb_in;
    end

    // Stage 2: first hit wins; label position inside its box.
    reg        out2, txt2;
    reg [2:0]  ocls2, tcls2;
    reg [10:0] tx2;
    reg [9:0]  ty2;
    reg        v2, h2, d2;
    reg [23:0] rgb2;
    reg        found;
    reg [2:0]  fc;
    reg [10:0] flx;
    reg [9:0]  fly, fby0, fby1;
    always @(posedge clk) begin
        found = 1'b0; fc = 3'd0;
        for (i = MAX_OBJECTS-1; i >= 0; i = i - 1)
            if (hit1[i]) begin found = 1'b1; fc = obj_data[i*41+38 +: 3]; end
        out2 <= found;
        ocls2 <= fc;
        found = 1'b0; fc = 3'd0; flx = 0; fly = 0;
        for (i = LABELS-1; i >= 0; i = i - 1)
            if (lab1[i]) begin
                found = 1'b1;
                fc = obj_data[i*41+38 +: 3];
                flx = {obj_data[i*41+28 +: 10], 1'b0};
                fby0 = {obj_data[i*41+9 +: 9], 1'b0};
                fby1 = {obj_data[i*41 +: 9], 1'b1};
                fly = (fby0 >= 10'd26) ? fby0 - 10'd26 : fby1 + 10'd4;
            end
        txt2 <= found;
        tcls2 <= fc;
        tx2 <= x1r - flx;
        ty2 <= y1r - fly;
        v2 <= v1; h2 <= h1; d2 <= d1;
        rgb2 <= rgb1;
    end

    // Stage 3: glyph lookup and colour.
    wire [10:0] gx_all = (tx2 >= 11'd2) ? tx2 - 11'd2 : 11'd60;
    wire [1:0]  gk = (gx_all < 11'd20) ? 2'd0 : (gx_all < 11'd40) ? 2'd1 : 2'd2;
    wire [4:0]  gx = gx_all - {gk, 4'd0} - {gk, 2'd0};
    wire [4:0]  gy = ty2[4:0] - 5'd1;
    wire        in_glyph = gx_all < 11'd60 && gk <= cls_len(tcls2) && ty2 >= 10'd1 && ty2 < 10'd21;
    wire [19:0] glyph_pixels;
    shape_font_rom u_shape_font_rom (.glyph(cls_glyph(tcls2, gk)), .row(gy), .pixels(glyph_pixels));
    wire        ink = in_glyph && glyph_pixels[5'd19 - gx];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vs_out <= 1; hs_out <= 0; de_out <= 0; rgb_out <= 0;
        end else begin
            vs_out <= v2; hs_out <= h2; de_out <= d2;
            rgb_out <= txt2 ? (ink ? cls_rgb(tcls2) : 24'h101010) :
                       out2 ? cls_rgb(ocls2) : rgb2;
        end
    end
endmodule

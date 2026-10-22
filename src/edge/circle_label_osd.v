`timescale 1ns/1ps

// Display-only annotation. The detector updates its result at VSYNC, so the
// label position remains fixed for an entire HDMI frame.
module circle_label_osd #(
    parameter integer H_ACTIVE = 1280,
    parameter integer V_ACTIVE = 720
)(
    input wire clk,
    input wire rst_n,
    input wire vsync_n,
    input wire de,
    input wire [23:0] rgb_in,
    input wire found,
    input wire [10:0] center_x,
    input wire [9:0] center_y,
    input wire [9:0] radius_px,
    output wire [23:0] rgb_out
);
    reg [10:0] x;
    reg [9:0] y;
    reg de_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin x<=0; y<=0; de_d<=0; end
        else if (!vsync_n) begin x<=0; y<=0; de_d<=0; end
        else begin
            de_d<=de;
            if (de) x<=x+11'd1;
            else begin
                x<=0;
                if (de_d) y<=y+10'd1;
            end
        end
    end

    wire [11:0] proposed_right = {1'b0,center_x} + {2'b0,radius_px} + 12'd12;
    wire [11:0] proposed_left = {1'b0,center_x} - {2'b0,radius_px} - 12'd120;
    wire [10:0] label_x = (proposed_right + 12'd108 < H_ACTIVE) ?
                           proposed_right[10:0] :
                           (center_x > radius_px + 10'd120 ? proposed_left[10:0] : 11'd0);
    wire [9:0] label_y = (center_y < 10'd12) ? 10'd0 :
                         (center_y > V_ACTIVE-12) ? V_ACTIVE-24 : center_y-10'd12;
    wire in_box = found && de && x >= label_x && x < label_x+11'd108 &&
                  y >= label_y && y < label_y+10'd24;
    wire [6:0] box_x = x-label_x;
    wire [4:0] box_y = y-label_y;
    wire border = in_box && (box_x==0 || box_x==107 || box_y==0 || box_y==23);
    wire text_area = in_box && box_x>=4 && box_x<104 && box_y>=2 && box_y<22;
    wire [6:0] text_x = box_x-7'd4;
    wire [2:0] character = text_x / 7'd20;
    wire [4:0] glyph_x = text_x % 7'd20;
    wire [4:0] glyph_y = box_y-5'd2;
    wire [19:0] glyph_pixels;
    circle_font_rom u_circle_font_rom (
        .character(character), .row(glyph_y), .pixels(glyph_pixels)
    );
    wire ink = text_area && glyph_pixels[19-glyph_x];
    assign rgb_out = border ? 24'h00ffff :
                     ink ? 24'hffff00 :
                     in_box ? 24'h101820 : rgb_in;
endmodule


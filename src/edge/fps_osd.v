`timescale 1ns/1ps

// Status text in the top-left corner; combinational RGB, no video latency.
//   FPS dd    camera frames per second (camera VSYNC)
//   OUT dd    processed/displayed frames per second (output VSYNC)
//   LAT dd    milliseconds from the end of a camera frame in DDR to the
//             start of its first display frame ("--" until measured)
//   THR dddd  edge threshold
//   FOC dddd  lens focus code (yellow while K1/K2 adjust focus)
//   MED ON / MED OFF, TNR ON / TNR OFF (temporal noise reduction),
//   NOISE ON (only while salt/pepper injection is on)
module fps_osd #(
    parameter integer PIXEL_HZ = 74400000,
    // 0 hides the FOC line and moves the lines below it up.
    parameter SHOW_FOCUS = 1'b1
)(
    input wire clk, rst_n, vs, de,
    input wire [23:0] rgb_in,
    input wire [7:0] fps_bcd,
    input wire fps_valid,
    input wire [11:0] threshold_in,
    input wire [7:0] latency_ms,
    input wire latency_valid,
    input wire median_on,
    input wire noise_on,
    input wire [9:0] focus_code,
    input wire focus_mode,
    input wire tnr_on,
    output wire [23:0] rgb_out
);
    reg [10:0] x = 0;
    reg [9:0] y = 0;
    reg de_d = 0;
    always @(posedge clk) begin
        if (!rst_n || !vs) begin x<=0; y<=0; de_d<=0; end
        else begin
            de_d<=de;
            if (de) x<=x+1'b1;
            else begin x<=0; if (de_d) y<=y+1'b1; end
        end
    end

    // Output frame rate: count VSYNC falling edges over one second.
    reg vs_d = 1;
    reg [26:0] tick = 0;
    reg [6:0] out_count = 0;
    reg [6:0] out_fps = 0;
    always @(posedge clk) begin
        if (!rst_n) begin
            vs_d<=1; tick<=0; out_count<=0; out_fps<=0;
        end else begin
            vs_d<=vs;
            if (tick == PIXEL_HZ-1) begin
                tick<=0;
                out_fps<=out_count + (vs_d && !vs);
                out_count<=0;
            end else begin
                tick<=tick+1'b1;
                if (vs_d && !vs && out_count != 7'd99) out_count<=out_count+1'b1;
            end
        end
    end

    reg [3:0] thousands,thousands_d,hundreds;
    reg [9:0] rem_1000;
    reg [6:0] rem_100;
    reg [15:0] threshold_bcd;
    reg [7:0] out_bcd, latency_bcd;
    reg latency_shown;
    reg [3:0] focus_thousands, focus_thousands_d, focus_hundreds;
    reg [9:0] focus_rem_1000;
    reg [6:0] focus_rem_100;
    reg [15:0] focus_bcd;
    wire [6:0] latency_clip = latency_ms > 8'd99 ? 7'd99 : latency_ms[6:0];
    wire [6:0] out_tens = out_fps / 7'd10, out_ones = out_fps % 7'd10;
    wire [6:0] latency_tens = latency_clip / 7'd10, latency_ones = latency_clip % 7'd10;
    always @(posedge clk) begin
        if(!rst_n) begin
            thousands<=0;thousands_d<=0;hundreds<=0;
            rem_1000<=0;rem_100<=0;threshold_bcd<=0;
            out_bcd<=0;latency_bcd<=0;latency_shown<=0;
            focus_thousands<=0;focus_thousands_d<=0;focus_hundreds<=0;
            focus_rem_1000<=0;focus_rem_100<=0;focus_bcd<=0;
        end else if(!vs) begin
            thousands<=threshold_in/12'd1000;
            rem_1000<=threshold_in%12'd1000;
            thousands_d<=thousands;
            hundreds<=rem_1000/10'd100;
            rem_100<=rem_1000%10'd100;
            threshold_bcd[15:12]<=thousands_d;
            threshold_bcd[11:8]<=hundreds;
            threshold_bcd[7:4]<=rem_100/7'd10;
            threshold_bcd[3:0]<=rem_100%7'd10;
            out_bcd<={out_tens[3:0], out_ones[3:0]};
            latency_shown<=latency_valid;
            latency_bcd<={latency_tens[3:0], latency_ones[3:0]};
            focus_thousands<=focus_code/10'd1000;
            focus_rem_1000<=focus_code%10'd1000;
            focus_thousands_d<=focus_thousands;
            focus_hundreds<=focus_rem_1000/10'd100;
            focus_rem_100<=focus_rem_1000%10'd100;
            focus_bcd[15:12]<=focus_thousands_d;
            focus_bcd[11:8]<=focus_hundreds;
            focus_bcd[7:4]<=focus_rem_100/7'd10;
            focus_bcd[3:0]<=focus_rem_100%7'd10;
        end
    end

    localparam [4:0] G_F=10, G_P=11, G_S=12, G_T=13, G_H=14, G_R=15,
                     G_O=16, G_U=17, G_L=18, G_A=19, G_M=20, G_E=21,
                     G_D=22, G_N=23, G_I=24, G_DASH=25, G_C=26, G_BLANK=31;
    function [34:0] glyph;
        input [4:0] n;
        begin
            case(n)
                0:glyph=35'b01110_10001_10011_10101_11001_10001_01110;
                1:glyph=35'b00100_01100_00100_00100_00100_00100_01110;
                2:glyph=35'b01110_10001_00001_00010_00100_01000_11111;
                3:glyph=35'b11110_00001_00001_01110_00001_00001_11110;
                4:glyph=35'b00010_00110_01010_10010_11111_00010_00010;
                5:glyph=35'b11111_10000_10000_11110_00001_00001_11110;
                6:glyph=35'b01110_10000_10000_11110_10001_10001_01110;
                7:glyph=35'b11111_00001_00010_00100_01000_01000_01000;
                8:glyph=35'b01110_10001_10001_01110_10001_10001_01110;
                9:glyph=35'b01110_10001_10001_01111_00001_00001_01110;
                G_F:glyph=35'b11111_10000_10000_11110_10000_10000_10000;
                G_P:glyph=35'b11110_10001_10001_11110_10000_10000_10000;
                G_S:glyph=35'b01111_10000_10000_01110_00001_00001_11110;
                G_T:glyph=35'b11111_00100_00100_00100_00100_00100_00100;
                G_H:glyph=35'b10001_10001_10001_11111_10001_10001_10001;
                G_R:glyph=35'b11110_10001_10001_11110_10100_10010_10001;
                G_O:glyph=35'b01110_10001_10001_10001_10001_10001_01110;
                G_U:glyph=35'b10001_10001_10001_10001_10001_10001_01110;
                G_L:glyph=35'b10000_10000_10000_10000_10000_10000_11111;
                G_A:glyph=35'b01110_10001_10001_11111_10001_10001_10001;
                G_M:glyph=35'b10001_11011_10101_10101_10001_10001_10001;
                G_E:glyph=35'b11111_10000_10000_11110_10000_10000_11111;
                G_D:glyph=35'b11110_10001_10001_10001_10001_10001_11110;
                G_N:glyph=35'b10001_11001_10101_10011_10001_10001_10001;
                G_I:glyph=35'b01110_00100_00100_00100_00100_00100_01110;
                G_C:glyph=35'b01110_10001_10000_10000_10000_10001_01110;
                G_DASH:glyph=35'b00000_00000_00000_11111_00000_00000_00000;
                default:glyph=0;
            endcase
        end
    endfunction

    // Rows are 22 pixels tall on a 26-pixel pitch, starting at y = 16.
    wire [9:0] rel_row_y = y - 10'd16;
    wire [4:0] screen_row = rel_row_y / 26;
    wire [4:0] row = (SHOW_FOCUS || screen_row < 5'd4) ? screen_row : screen_row + 5'd1;
    wire [4:0] row_y = rel_row_y % 26;
    wire [3:0] row_letters = (row == 5'd3 || row == 5'd4) ? 4'd8 :
                             (row == 5'd5) ? (median_on ? 4'd6 : 4'd7) :
                             (row == 5'd6) ? (tnr_on ? 4'd6 : 4'd7) :
                             (row == 5'd7) ? 4'd8 : 4'd6;
    wire row_shown = (row <= 5'd6) || (row == 5'd7 && noise_on);
    wire [10:0] rel_x = x - 11'd16;
    wire box = de && y >= 10'd16 && row <= 5'd7 && row_shown && row_y < 5'd22 &&
               x >= 11'd16 && rel_x < row_letters * 12;
    wire [3:0] letter = rel_x / 12;
    wire [3:0] gx = (rel_x % 12) >> 1;
    wire [3:0] gy = row_y >> 1;
    reg [4:0] symbol;
    always @* begin
        symbol = G_BLANK;
        case(row)
            5'd0: case(letter)
                0:symbol=G_F; 1:symbol=G_P; 2:symbol=G_S;
                4:symbol=fps_valid ? {1'b0,fps_bcd[7:4]} : G_DASH;
                5:symbol=fps_valid ? {1'b0,fps_bcd[3:0]} : G_DASH;
                default:symbol=G_BLANK;
            endcase
            5'd1: case(letter)
                0:symbol=G_O; 1:symbol=G_U; 2:symbol=G_T;
                4:symbol={1'b0,out_bcd[7:4]};
                5:symbol={1'b0,out_bcd[3:0]};
                default:symbol=G_BLANK;
            endcase
            5'd2: case(letter)
                0:symbol=G_L; 1:symbol=G_A; 2:symbol=G_T;
                4:symbol=latency_shown ? {1'b0,latency_bcd[7:4]} : G_DASH;
                5:symbol=latency_shown ? {1'b0,latency_bcd[3:0]} : G_DASH;
                default:symbol=G_BLANK;
            endcase
            5'd3: case(letter)
                0:symbol=G_T; 1:symbol=G_H; 2:symbol=G_R;
                4:symbol={1'b0,threshold_bcd[15:12]};
                5:symbol={1'b0,threshold_bcd[11:8]};
                6:symbol={1'b0,threshold_bcd[7:4]};
                7:symbol={1'b0,threshold_bcd[3:0]};
                default:symbol=G_BLANK;
            endcase
            5'd4: case(letter)
                0:symbol=G_F; 1:symbol=G_O; 2:symbol=G_C;
                4:symbol={1'b0,focus_bcd[15:12]};
                5:symbol={1'b0,focus_bcd[11:8]};
                6:symbol={1'b0,focus_bcd[7:4]};
                7:symbol={1'b0,focus_bcd[3:0]};
                default:symbol=G_BLANK;
            endcase
            5'd5: case(letter)
                0:symbol=G_M; 1:symbol=G_E; 2:symbol=G_D;
                4:symbol=G_O;
                5:symbol=median_on ? G_N : G_F;
                6:symbol=median_on ? G_BLANK : G_F;
                default:symbol=G_BLANK;
            endcase
            5'd6: case(letter)
                0:symbol=G_T; 1:symbol=G_N; 2:symbol=G_R;
                4:symbol=G_O;
                5:symbol=tnr_on ? G_N : G_F;
                6:symbol=tnr_on ? G_BLANK : G_F;
                default:symbol=G_BLANK;
            endcase
            default: case(letter)
                0:symbol=G_N; 1:symbol=G_O; 2:symbol=G_I; 3:symbol=G_S;
                4:symbol=G_E; 6:symbol=G_O; 7:symbol=G_N;
                default:symbol=G_BLANK;
            endcase
        endcase
    end
    wire [34:0] bits = glyph(symbol);
    wire ink = gx<5 && gy<7 && bits[34-(gy*5+gx)];
    wire [23:0] ink_rgb = (row == 5'd4 && focus_mode) ? 24'hffff00 : 24'h00ff80;
    assign rgb_out = box ? (ink ? ink_rgb : 24'h101010) : rgb_in;
endmodule

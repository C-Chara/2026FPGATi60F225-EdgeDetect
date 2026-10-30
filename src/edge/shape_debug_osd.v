`timescale 1ns/1ps

// Recognition readout under the status text (only while enable):
//   DET nn     objects found by shape_detector in the last analysis
//   TRK nn     objects shown after cross-frame voting
//   ARE nnnnn  area (samples, 640x360 grid) of the largest candidate
//   RHO nnn    100 x its mean gray / mean of its surroundings
//   EDG nnnnn  edge pixels in the picture centre, last frame (automatic threshold)
//   MOM nnn    J^2 * 2^16 (circle/ellipse 415, rectangle 455, triangle 607)
//   FIL nn     box fill x 64 (circle 50)
//   ERR nnn    reject bits (shape_detector dbg_why), 0 = accepted
// Values are converted to decimal one bit per clock and taken over at VSYNC.
module shape_debug_osd (
    input  wire        clk, rst_n, vs, de, enable,
    input  wire [23:0] rgb_in,
    input  wire [5:0]  det_count, trk_count,
    input  wire [17:0] area,
    input  wire [9:0]  rho, mom,
    input  wire [19:0] edges,
    input  wire [6:0]  fill, why,
    output wire [23:0] rgb_out
);
    reg [10:0] x = 0;
    reg [9:0]  y = 0;
    reg        de_d = 0;
    always @(posedge clk) begin
        if (!rst_n || !vs) begin x <= 0; y <= 0; de_d <= 0; end
        else begin
            de_d <= de;
            if (de) x <= x + 1'b1;
            else begin x <= 0; if (de_d) y <= y + 1'b1; end
        end
    end

    // Sequential binary -> BCD (double dabble), 17 bits, 5 digits per value.
    reg [2:0]  idx;
    reg [4:0]  cnt;
    reg [36:0] sh;                     // {bcd[19:0], bin[16:0]}
    reg [19:0] bcd_work [0:7];
    reg [19:0] bcd_show [0:7];
    wire [16:0] area_clip = (area > 18'd99999) ? 17'd99999 : area[16:0];
    reg  [16:0] value;
    always @* begin
        case (idx)
            3'd0: value = {11'd0, det_count};
            3'd1: value = {11'd0, trk_count};
            3'd2: value = area_clip;
            3'd3: value = {7'd0, rho};
            3'd4: value = (edges > 20'd99999) ? 17'd99999 : edges[16:0];
            3'd5: value = {7'd0, mom};
            3'd6: value = {10'd0, fill};
            default: value = {10'd0, why};
        endcase
    end
    function [3:0] adj;
        input [3:0] d;
        adj = (d >= 4'd5) ? d + 4'd3 : d;
    endfunction
    wire [36:0] sh_adj = {adj(sh[36:33]), adj(sh[32:29]), adj(sh[28:25]),
                          adj(sh[24:21]), adj(sh[20:17]), sh[16:0]};
    reg vs_d2 = 1;
    integer q;
    always @(posedge clk) begin
        if (!rst_n) begin
            idx <= 0; cnt <= 0; sh <= 0; vs_d2 <= 1;
            for (q = 0; q < 8; q = q + 1) begin bcd_work[q] <= 0; bcd_show[q] <= 0; end
        end else begin
            vs_d2 <= vs;
            if (cnt == 0) begin
                sh <= {20'd0, value};
                cnt <= 5'd17;
            end else begin
                sh <= sh_adj << 1;
                cnt <= cnt - 5'd1;
                if (cnt == 5'd1) begin
                    bcd_work[idx] <= sh_adj[35:16];
                    idx <= idx + 3'd1;
                end
            end
            if (vs_d2 && !vs)
                for (q = 0; q < 8; q = q + 1) bcd_show[q] <= bcd_work[q];
        end
    end

    localparam [4:0] G_F=10, G_P=11, G_S=12, G_T=13, G_H=14, G_R=15,
                     G_O=16, G_E=17, G_D=18, G_A=19, G_M=20, G_K=21,
                     G_I=22, G_L=23, G_G=24, G_BLANK=31;
    function [34:0] glyph;
        input [4:0] n;
        case (n)
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
            G_E:glyph=35'b11111_10000_10000_11110_10000_10000_11111;
            G_D:glyph=35'b11110_10001_10001_10001_10001_10001_11110;
            G_A:glyph=35'b01110_10001_10001_11111_10001_10001_10001;
            G_M:glyph=35'b10001_11011_10101_10101_10001_10001_10001;
            G_K:glyph=35'b10001_10010_10100_11000_10100_10010_10001;
            G_I:glyph=35'b01110_00100_00100_00100_00100_00100_01110;
            G_L:glyph=35'b10000_10000_10000_10000_10000_10000_11111;
            G_G:glyph=35'b01110_10001_10000_10111_10001_10001_01111;
            default:glyph=0;
        endcase
    endfunction

    // 8 rows, 22 pixels tall on a 26-pixel pitch, from y = 330.
    localparam [9:0] Y0 = 10'd330;
    wire [9:0]  rel_y = y - Y0;
    wire [3:0]  row = rel_y / 26;
    wire [4:0]  row_y = rel_y % 26;
    wire [10:0] rel_x = x - 11'd16;
    wire [3:0]  letter = rel_x / 12;
    wire [3:0]  gx = (rel_x % 12) >> 1;
    wire [3:0]  gy = row_y >> 1;
    // digits shown per row
    reg  [2:0]  ndig;
    reg  [4:0]  n0, n1, n2;
    always @* begin
        case (row)
            4'd0: begin n0 = G_D; n1 = G_E; n2 = G_T; ndig = 2; end
            4'd1: begin n0 = G_T; n1 = G_R; n2 = G_K; ndig = 2; end
            4'd2: begin n0 = G_A; n1 = G_R; n2 = G_E; ndig = 5; end
            4'd3: begin n0 = G_R; n1 = G_H; n2 = G_O; ndig = 3; end
            4'd4: begin n0 = G_E; n1 = G_D; n2 = G_G; ndig = 5; end
            4'd5: begin n0 = G_M; n1 = G_O; n2 = G_M; ndig = 3; end
            4'd6: begin n0 = G_F; n1 = G_I; n2 = G_L; ndig = 2; end
            default: begin n0 = G_E; n1 = G_R; n2 = G_R; ndig = 3; end
        endcase
    end
    wire [19:0] digits = bcd_show[row[2:0]];
    wire [3:0]  dpos = letter - 4'd4;            // 0 = leftmost shown digit
    wire [2:0]  dsel = ndig - 3'd1 - dpos[2:0];  // nibble index, 0 = ones
    reg  [4:0]  symbol;
    always @* begin
        if (letter == 0) symbol = n0;
        else if (letter == 1) symbol = n1;
        else if (letter == 2) symbol = n2;
        else if (letter >= 4 && dpos < ndig) symbol = {1'b0, digits[dsel*4 +: 4]};
        else symbol = G_BLANK;
    end
    wire box = enable && de && y >= Y0 && row <= 4'd7 && row_y < 5'd22 &&
               x >= 11'd16 && rel_x < (4 + ndig) * 12;
    wire [34:0] bits = glyph(symbol);
    wire ink = gx < 5 && gy < 7 && bits[34 - (gy * 5 + gx)];
    assign rgb_out = box ? (ink ? 24'h00ffff : 24'h101010) : rgb_in;
endmodule

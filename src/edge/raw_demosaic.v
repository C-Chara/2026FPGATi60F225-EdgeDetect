`timescale 1ns/1ps

// Bayer RAW8 -> RGB565 for the 60 fps colour capture (camera pixel clock).
//
// Demosaic: every output pixel takes the 2x2 block made of itself, its left
// neighbour, the pixel above and the pixel above-left. Such a block always
// holds one R, two G and one B sample, so R and B are copied and G is the
// mean of the two greens. One line buffer, one pixel in -> one pixel out, the
// same number of pixels per line and per frame as the input (the picture is
// shifted by half a pixel, which is not visible). The first row and column
// reuse the current row / pixel.
//
// White balance: grey world. Every frame the sums of R*gain_r, G and B*gain_b
// are compared; at the end of the frame gain_r and gain_b move one step
// (2/256) towards the green sum unless they are within 1/64 of it.
// Gains are 8.8 fixed point, 0.5 .. 4.0.
//
// Gamma: gamma_lut (1/2.2 with a linear toe) on each channel.
//
// phase selects the Bayer order of pixel (0,0): 0 RGGB, 1 GRBG, 2 GBRG, 3 BGGR.
// Latency: 4 clocks (data and de_out).
module raw_demosaic #(
    parameter integer H_ACTIVE = 1280
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        frame_valid,    // high during the frame, low in vsync
    input  wire        de,             // one RAW8 sample per clock
    input  wire [7:0]  raw,
    input  wire [1:0]  phase,
    input  wire        gamma_on,
    output reg         de_out,
    output reg  [15:0] rgb565,
    output reg  [9:0]  gain_r,
    output reg  [9:0]  gain_b
);
    // ------------------------------------------------------------------
    // Position counters
    reg [10:0] x;
    reg [9:0]  y;
    reg        de_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin x <= 0; y <= 0; de_d <= 0; end
        else begin
            de_d <= de;
            if (!frame_valid) begin x <= 0; y <= 0; end
            else if (de) x <= x + 11'd1;
            else begin
                x <= 0;
                if (de_d) y <= y + 10'd1;
            end
        end
    end

    // Line buffer: read at x in stage 0, write the same address in stage 1.
    reg [7:0]  line_buf [0:H_ACTIVE-1];
    reg [7:0]  above;              // row above at x (valid in stage 1)
    reg [10:0] x1;
    reg [9:0]  y1;
    reg        v1;
    reg [7:0]  e1;                 // current sample in stage 1
    always @(posedge clk) begin
        if (de) above <= line_buf[x];
        if (v1) line_buf[x1] <= e1;
    end

    // Stage 1 -> 2: the 2x2 block and its colours
    reg [7:0]  d_left, a_left;     // previous current / above samples
    reg        v2;
    reg [7:0]  r2, g2, b2;
    wire [7:0] e  = e1;
    wire [7:0] d  = (x1 == 0) ? e1 : d_left;
    wire [7:0] b  = (y1 == 0) ? e  : above;
    wire [7:0] a  = (y1 == 0) ? d  : ((x1 == 0) ? b : a_left);
    wire       ry = y1[0] ^ phase[1];
    wire       rx = x1[0] ^ phase[0];
    wire [8:0] g_bd = {1'b0, b} + {1'b0, d};
    wire [8:0] g_ea = {1'b0, e} + {1'b0, a};

    // Stage 2 -> 3: white balance; stage 3 -> 4: gamma and packing
    reg        v3;
    reg [7:0]  r3, g3, b3;
    wire [17:0] r_mul = r2 * gain_r;
    wire [17:0] b_mul = b2 * gain_b;
    wire [7:0]  gr_out, gg_out, gb_out;
    gamma_lut u_gamma_r (.in(r3), .out(gr_out));
    gamma_lut u_gamma_g (.in(g3), .out(gg_out));
    gamma_lut u_gamma_b (.in(b3), .out(gb_out));
    wire [7:0] ro = gamma_on ? gr_out : r3;
    wire [7:0] go = gamma_on ? gg_out : g3;
    wire [7:0] bo = gamma_on ? gb_out : b3;

    // Grey-world sums (after the gains, before gamma)
    reg [29:0] sum_r, sum_g, sum_b;
    reg        fv_d;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            v1 <= 0; x1 <= 0; y1 <= 0; e1 <= 0;
            d_left <= 0; a_left <= 0;
            v2 <= 0; r2 <= 0; g2 <= 0; b2 <= 0;
            v3 <= 0; r3 <= 0; g3 <= 0; b3 <= 0;
            de_out <= 0; rgb565 <= 0;
            gain_r <= 10'd256; gain_b <= 10'd256;
            sum_r <= 0; sum_g <= 0; sum_b <= 0; fv_d <= 0;
        end else begin
            // stage 1
            v1 <= de;
            x1 <= x;
            y1 <= y;
            e1 <= raw;
            // stage 2
            v2 <= v1;
            if (v1) begin
                d_left <= e;
                a_left <= b;
                case ({ry, rx})
                    2'b00: begin r2 <= e; b2 <= a; g2 <= g_bd[8:1]; end   // e is R
                    2'b11: begin b2 <= e; r2 <= a; g2 <= g_bd[8:1]; end   // e is B
                    2'b01: begin r2 <= d; b2 <= b; g2 <= g_ea[8:1]; end   // G on an R row
                    default: begin b2 <= d; r2 <= b; g2 <= g_ea[8:1]; end // G on a B row
                endcase
            end
            // stage 3
            v3 <= v2;
            r3 <= (r_mul[17:8] > 10'd255) ? 8'd255 : r_mul[15:8];
            g3 <= g2;
            b3 <= (b_mul[17:8] > 10'd255) ? 8'd255 : b_mul[15:8];
            if (v3) begin
                sum_r <= sum_r + r3;
                sum_g <= sum_g + g3;
                sum_b <= sum_b + b3;
            end
            // stage 4
            de_out <= v3;
            rgb565 <= v3 ? {ro[7:3], go[7:2], bo[7:3]} : 16'd0;

            // end of frame: one white-balance step
            fv_d <= frame_valid;
            if (fv_d && !frame_valid) begin
                if (sum_r + (sum_g >> 6) < sum_g && gain_r < 10'd1022) gain_r <= gain_r + 10'd2;
                else if (sum_r > sum_g + (sum_g >> 6) && gain_r > 10'd129) gain_r <= gain_r - 10'd2;
                if (sum_b + (sum_g >> 6) < sum_g && gain_b < 10'd1022) gain_b <= gain_b + 10'd2;
                else if (sum_b > sum_g + (sum_g >> 6) && gain_b > 10'd129) gain_b <= gain_b - 10'd2;
                sum_r <= 0; sum_g <= 0; sum_b <= 0;
            end
        end
    end
endmodule

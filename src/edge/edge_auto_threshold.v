`timescale 1ns/1ps

// Automatic edge threshold: keeps the share of edge pixels in the displayed
// edge map near TARGET. Every frame the final edge pixels are counted; at
// VSYNC the threshold moves one step up when there were more than HI edge
// pixels and one step down when there were fewer than LO (four steps when
// far outside), within MIN..MAX. Low-contrast scenes (faces, dim light) get
// a lower threshold, busy textures a higher one. The threshold changes at
// most 4 per frame, so the edge map does not pump.
module edge_auto_threshold #(
    parameter [11:0] INITIAL = 12'd88,
    parameter [11:0] MIN = 12'd48,
    parameter [11:0] MAX = 12'd160,
    parameter [19:0] TARGET_LO = 20'd19000,   // ~2.1 % of 1276 x 720
    parameter [19:0] TARGET_HI = 20'd30000    // ~3.3 %
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        vs,            // active low
    input  wire        edge_pix,      // one clock per displayed edge pixel
    output reg  [11:0] threshold,
    output reg  [19:0] edge_count     // edge pixels of the last frame
);
    reg [19:0] cnt;
    reg        vs_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 0; vs_d <= 1; threshold <= INITIAL; edge_count <= 0;
        end else begin
            vs_d <= vs;
            if (vs_d && !vs) begin
                cnt <= 0;
                edge_count <= cnt;
                if (cnt > {TARGET_HI[18:0], 1'b0})
                    threshold <= (threshold + 12'd4 > MAX) ? MAX : threshold + 12'd4;
                else if (cnt > TARGET_HI)
                    threshold <= (threshold >= MAX) ? MAX : threshold + 12'd1;
                else if (cnt < {1'b0, TARGET_LO[19:1]})
                    threshold <= (threshold < MIN + 12'd4) ? MIN : threshold - 12'd4;
                else if (cnt < TARGET_LO)
                    threshold <= (threshold <= MIN) ? MIN : threshold - 12'd1;
            end else if (edge_pix && cnt != 20'hfffff) begin
                cnt <= cnt + 20'd1;
            end
        end
    end
endmodule

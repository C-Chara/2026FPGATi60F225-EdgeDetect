`timescale 1ns/1ps
// fps_osd: prints the top-right mode name for every display mode as text.
module tb_mode_label;
    reg clk = 0; always #5 clk = ~clk;
    reg rst_n = 0, vs = 0, de = 0;
    reg [2:0] mode = 0;
    wire [23:0] rgb;
    fps_osd #(.PIXEL_HZ(1000), .COMPACT(1'b1), .SHOW_MODE(1'b1)) dut (
        .clk(clk), .rst_n(rst_n), .vs(vs), .de(de), .rgb_in(24'h000000),
        .fps_bcd(8'h60), .fps_valid(1'b1), .threshold_in(12'd60), .threshold_auto(1'b1),
        .latency_ms(8'd0), .latency_valid(1'b0), .median_on(1'b1), .noise_on(1'b0),
        .focus_code(10'd0), .focus_mode(1'b0), .tnr_mode(2'd1), .recognition_on(1'b0),
        .bayer_phase(2'd0), .change_pct(7'd0), .change_valid(1'b0), .flicker(12'd0),
        .frozen(1'b0), .playing(1'b0), .replay_back(8'd0), .display_mode(mode),
        .rgb_out(rgb));
    integer m, row, col;
    reg [1279:0] line;
    initial begin
        repeat (3) @(negedge clk); rst_n = 1;
        for (m = 0; m < 5; m = m + 1) begin
            mode = m;
            vs = 0; repeat (3) @(negedge clk); vs = 1;
            $display("mode %0d:", m);
            for (row = 0; row < 32; row = row + 1) begin
                for (col = 0; col < 1280; col = col + 1) begin
                    de = 1; @(negedge clk);
                    line[col] = (rgb == 24'h00ff80);
                end
                de = 0; repeat (4) @(negedge clk);
                if (row >= 16 && row < 30 && row % 2 == 0) begin : pr
                    reg [8*40-1:0] s; integer k;
                    s = "";
                    for (k = 1192; k < 1264; k = k + 2) s = {s, line[k] ? "#" : "."};
                    $display("  %0s", s);
                end
            end
        end
        $finish;
    end
endmodule

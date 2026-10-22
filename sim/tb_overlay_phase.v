`timescale 1ns/1ps

// Measure the RGB sideband delay needed by the exact live edge chain.
module tb_overlay_phase;
    localparam integer W = 64;
    localparam integer H = 8;
    localparam integer BLANK = 80;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0, vs = 1, de = 0;
    reg [7:0] gray = 0;
    integer input_x = 0, input_y = 0;
    integer cycle = 0;
    integer input_time [0:H-1][0:W-1];
    integer measured = 0, min_delay = 1000000, max_delay = 0;

    wire median_vs, median_valid;
    wire [7:0] median_gray;
    median3x3_video #(.H_ACTIVE(W)) median (
        .clk(clk), .rst_n(rst_n), .hs_in(1'b1), .vs_in(vs),
        .de_in(de), .gray_in(gray), .hs_out(), .vs_out(median_vs),
        .de_out(median_valid), .gray_out(median_gray)
    );
    wire [7:0] gaussian_gray, gaussian_center;
    wire gaussian_valid;
    gaussian_stream #(.H_ACTIVE(W)) gaussian (
        .clk(clk), .rst_n(rst_n), .vsync_n(median_vs),
        .pixel_valid(median_valid), .gray_in(median_gray),
        .gray_out(gaussian_gray), .gray_center_out(gaussian_center),
        .pixel_valid_out(gaussian_valid)
    );
    wire [7:0] sobel_edge, sobel_gray;
    wire [11:0] magnitude;
    wire [1:0] direction;
    wire sobel_valid;
    sobel_stream #(.H_ACTIVE(W)) sobel (
        .clk(clk), .rst_n(rst_n), .vsync_n(vs),
        .pixel_valid(gaussian_valid), .gray_in(gaussian_gray),
        .gray_center_in(gaussian_center), .edge_out(sobel_edge),
        .magnitude_out(magnitude), .direction_out(direction),
        .window_valid_out(sobel_valid), .gray_center_out(sobel_gray)
    );
    wire [7:0] hysteresis_edge, hysteresis_gray;
    wire hysteresis_valid;
    hysteresis_stream #(.H_ACTIVE(W-2)) hysteresis (
        .clk(clk), .rst_n(rst_n), .vsync_n(vs),
        .pixel_valid(sobel_valid), .magnitude_in(magnitude),
        .gray_in(sobel_gray), .low_threshold_in(12'd60),
        .high_threshold_in(12'd120), .edge_out(hysteresis_edge),
        .gray_out(hysteresis_gray), .pixel_valid_out(hysteresis_valid)
    );
    reg [11:0] magnitude_d1 = 0, magnitude_d2 = 0;
    always @(posedge clk) begin
        magnitude_d1 <= magnitude;
        magnitude_d2 <= magnitude_d1;
    end
    wire [7:0] stable_edge, stable_gray;
    edge_frame_hold #(.H_ACTIVE(W-2), .V_ACTIVE(H)) hold_edges (
        .clk(clk), .rst_n(rst_n), .vsync_n(vs),
        .pixel_valid(hysteresis_valid), .edge_in(hysteresis_edge),
        .gray_in(hysteresis_gray), .magnitude_in(magnitude_d2),
        .release_threshold_in(12'd30),
        .edge_out(stable_edge), .gray_out(stable_gray)
    );

    wire [15:0] aligned_rgb565;
    wire aligned_valid;
    rgb565_frame_align #(.H_ACTIVE(W), .PIXEL_DELAY(24)) color_align (
        .clk(clk), .rst_n(rst_n), .vsync_n(vs),
        .pixel_valid(de), .rgb565_in({8'd0, gray}),
        .rgb565_out(aligned_rgb565), .pixel_valid_out(aligned_valid)
    );

    integer px, py, delay_cycles;
    always @(posedge clk) begin
        cycle = cycle + 1;
        if (de) input_time[input_y][input_x] = cycle;
        #1;
        px = stable_gray & 8'h1f;
        py = stable_gray >> 5;
        if (de && stable_gray != 0 && py >= 2 && py <= 4 && px >= 10 && px <= 17 &&
            input_time[py][px] > 0) begin
            delay_cycles = cycle - input_time[py][px];
            if (delay_cycles < min_delay) min_delay = delay_cycles;
            if (delay_cycles > max_delay) max_delay = delay_cycles;
            if (!aligned_valid || aligned_rgb565[7:0] !== stable_gray)
                $fatal(1, "RGB alignment mismatch at (%0d,%0d): gray=%0d RGB=%0d valid=%b",
                       px, py, stable_gray, aligned_rgb565[7:0], aligned_valid);
            if (measured < 8)
                $display("center (%0d,%0d) delay=%0d clocks", px, py, delay_cycles);
            measured = measured + 1;
        end
    end

    integer x, y, b;
    initial begin
        for (y = 0; y < H; y = y + 1)
            for (x = 0; x < W; x = x + 1)
                input_time[y][x] = -1;
        repeat (5) @(negedge clk);
        rst_n = 1;
        vs = 0;
        repeat (30) @(negedge clk);
        vs = 1;
        for (y = 0; y < H; y = y + 1) begin
            for (x = 0; x < W; x = x + 1) begin
                de = 1;
                gray = y*32 + (x & 31);
                input_x = x;
                input_y = y;
                @(negedge clk);
            end
            de = 0;
            gray = 0;
            for (b = 0; b < BLANK; b = b + 1)
                @(negedge clk);
        end
        repeat (50) @(negedge clk);
        if (measured < 8 || min_delay != max_delay)
            $fatal(1, "inconsistent phase: n=%0d min=%0d max=%0d", measured, min_delay, max_delay);
        $display("PASS: %0d samples share %0d-clock total delay", measured, min_delay);
        $finish;
    end
endmodule

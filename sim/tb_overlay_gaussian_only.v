`timescale 1ns/1ps

// Measure the RGB sideband delay needed by the exact live edge chain.
module tb_overlay_gaussian_only;
    localparam integer W = 32;
    localparam integer H = 8;
    localparam integer BLANK = 80;
    parameter integer RGB_DELAY = 11;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0, vs = 1, de = 0;
    reg [7:0] gray = 0;
    integer input_x = 0, input_y = 0;
    integer cycle = 0;
    integer input_time_by_gray [0:255];
    integer input_x_by_gray [0:255];
    integer input_y_by_gray [0:255];
    integer measured = 0, min_delay = 1000000, max_delay = 0;
    reg [3:0] measured_directions = 0;

    wire [7:0] gaussian_gray, gaussian_center;
    wire gaussian_valid;
    gaussian_stream #(.H_ACTIVE(W)) gaussian (
        .clk(clk), .rst_n(rst_n), .vsync_n(vs),
        .pixel_valid(de), .gray_in(gray),
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
    reg [1:0] direction_d1=0, direction_d2=0, direction_d3=0, direction_d4=0;
    reg [1:0] expected_direction [0:255];
    reg direction_seen [0:255];
    integer gray_id;
    always @(posedge clk) begin
        direction_d1 <= direction;
        direction_d2 <= direction_d1;
        direction_d3 <= direction_d2;
        direction_d4 <= direction_d3;
        if (sobel_valid && sobel_gray != 0) begin
            expected_direction[sobel_gray] = direction;
            direction_seen[sobel_gray] = 1;
        end
    end

    wire [15:0] aligned_rgb565;
    wire aligned_valid;
    rgb565_frame_align #(.H_ACTIVE(W), .ROW_DELAY(2), .PIXEL_DELAY(RGB_DELAY)) color_align (
        .clk(clk), .rst_n(rst_n), .vsync_n(vs),
        .pixel_valid(de), .rgb565_in({8'd0, gray}),
        .rgb565_out(aligned_rgb565), .pixel_valid_out(aligned_valid)
    );

    integer px, py, delay_cycles;
    always @(posedge clk) begin
        cycle = cycle + 1;
        if (de) begin
            input_time_by_gray[gray] = cycle;
            input_x_by_gray[gray] = input_x;
            input_y_by_gray[gray] = input_y;
        end
        #1;
        px = input_x_by_gray[stable_gray];
        py = input_y_by_gray[stable_gray];
        if (de && stable_gray != 0 && py >= 2 && py <= 4 && px >= 10 && px <= 17 &&
            input_time_by_gray[stable_gray] > 0) begin
            delay_cycles = cycle - input_time_by_gray[stable_gray];
            if (delay_cycles < min_delay) min_delay = delay_cycles;
            if (delay_cycles > max_delay) max_delay = delay_cycles;
            if (!aligned_valid || aligned_rgb565[7:0] !== stable_gray)
                $fatal(1, "RGB alignment mismatch at (%0d,%0d): gray=%0d RGB=%0d valid=%b",
                       px, py, stable_gray, aligned_rgb565[7:0], aligned_valid);
            if (!direction_seen[stable_gray] || direction_d4 !== expected_direction[stable_gray])
                $fatal(1, "Sobel direction sideband mismatch at (%0d,%0d)",px,py);
            measured_directions[direction_d4] = 1;
            if (measured < 8)
                $display("center (%0d,%0d) delay=%0d clocks", px, py, delay_cycles);
            measured = measured + 1;
        end
    end

    integer x, y, b;
    initial begin
        for (gray_id = 0; gray_id < 256; gray_id = gray_id + 1) begin
            direction_seen[gray_id] = 0;
            input_time_by_gray[gray_id] = -1;
            input_x_by_gray[gray_id] = -1;
            input_y_by_gray[gray_id] = -1;
        end
        repeat (5) @(negedge clk);
        rst_n = 1;
        vs = 0;
        repeat (30) @(negedge clk);
        vs = 1;
        for (y = 0; y < H; y = y + 1) begin
            for (x = 0; x < W; x = x + 1) begin
                de = 1;
                gray = (y*32 + x)*73;
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
        if (measured < 8 || min_delay != max_delay ||
            measured_directions == 4'b0001 || measured_directions == 4'b0010 ||
            measured_directions == 4'b0100 || measured_directions == 4'b1000)
            $fatal(1, "inconsistent phase: n=%0d min=%0d max=%0d", measured, min_delay, max_delay);
        $display("PASS: %0d samples share %0d-clock total delay, directions=%b",
                 measured, min_delay, measured_directions);
        $finish;
    end
endmodule





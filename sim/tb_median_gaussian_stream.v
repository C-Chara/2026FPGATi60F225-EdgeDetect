`timescale 1ns/1ps

// Exercise the exact median -> Gaussian handshake used by example_top.
// An isolated bright pixel must disappear without changing the flat interior.
module tb_median_gaussian_stream;
    localparam integer W = 16;
    localparam integer H = 8;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0, hs = 1, vs = 1, de = 0;
    reg [7:0] gray = 0;
    wire median_vs, median_valid;
    wire [7:0] median_gray;
    wire gaussian_valid;
    wire [7:0] gaussian_gray, gaussian_center;
    integer mx = 0, my = 0, gx = 0, gy = 0;
    integer median_count = 0, gaussian_count = 0;

    median3x3_video #(.H_ACTIVE(W)) u_median (
        .clk(clk), .rst_n(rst_n), .hs_in(hs), .vs_in(vs),
        .de_in(de), .gray_in(gray), .hs_out(), .vs_out(median_vs),
        .de_out(median_valid), .gray_out(median_gray)
    );
    gaussian_stream #(.H_ACTIVE(W)) u_gaussian (
        .clk(clk), .rst_n(rst_n), .vsync_n(median_vs),
        .pixel_valid(median_valid), .gray_in(median_gray),
        .gray_out(gaussian_gray), .gray_center_out(gaussian_center),
        .pixel_valid_out(gaussian_valid)
    );

    always @(posedge clk) begin
        #1;
        if (median_valid) begin
            if (my >= 2 && mx >= 2 && median_gray !== 8'd100)
                $fatal(1, "median mismatch at (%0d,%0d): %0d", mx, my, median_gray);
            median_count = median_count + 1;
            if (mx == W-1) begin mx = 0; my = my + 1; end
            else mx = mx + 1;
        end
        if (gaussian_valid) begin
            if (gy >= 3 && gx >= 4 && gx <= 14 &&
                (gaussian_gray !== 8'd100 || gaussian_center !== 8'd100))
                $fatal(1, "Gaussian mismatch at (%0d,%0d): %0d/%0d",
                       gx, gy, gaussian_gray, gaussian_center);
            gaussian_count = gaussian_count + 1;
            if (gx == W-1) begin gx = 0; gy = gy + 1; end
            else gx = gx + 1;
        end
    end

    integer x, y, blank;
    initial begin
        repeat (5) @(negedge clk);
        rst_n = 1;
        vs = 0;
        repeat (20) @(negedge clk);
        vs = 1;
        for (y = 0; y < H; y = y + 1) begin
            for (x = 0; x < W; x = x + 1) begin
                de = 1;
                gray = (x == 8 && y == 4) ? 8'd255 : 8'd100;
                @(negedge clk);
            end
            de = 0;
            gray = 0;
            for (blank = 0; blank < 20; blank = blank + 1)
                @(negedge clk);
        end
        repeat (30) @(negedge clk);
        if (median_count != W*H || gaussian_count < W*(H-2))
            $fatal(1, "valid count mismatch: median=%0d gaussian=%0d", median_count, gaussian_count);
        $display("PASS: median removes isolated impulse, Gaussian interior remains flat");
        $finish;
    end
endmodule

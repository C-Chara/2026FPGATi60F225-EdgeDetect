`timescale 1ns/1ps

// Feeds the same 1280x720 image for several frames and prints the objects
// found after the second analysis (the first scan uses the start-up
// threshold). Compare with tools/models/shape_ccl_model.py through
// tools/models/gen_shape_tb_data.py.
module tb_shape_detector;
    localparam integer HA = 1280, VA = 720, HB = 220, VB = 12;
    reg clk = 0, rst_n = 0, vsync_n = 1, de = 0;
    reg [7:0] gray = 0;
    reg [7:0] img [0:HA*VA-1];
    wire [5:0] obj_count;
    wire [32*41-1:0] obj_data;
    wire [7:0] threshold;
    shape_detector dut (
        .clk(clk), .rst_n(rst_n), .vsync_n(vsync_n), .de(de), .gray(gray),
        .obj_count(obj_count), .obj_data(obj_data), .threshold(threshold)
    );
    always #6.72 clk = ~clk;

    integer f, x, y, k;
    task frame;
        begin
            vsync_n <= 0;
            repeat (5 * (HA + HB)) @(posedge clk);
            vsync_n <= 1;
            repeat ((VB - 5) * (HA + HB)) @(posedge clk);
            for (y = 0; y < VA; y = y + 1) begin
                for (x = 0; x < HA; x = x + 1) begin
                    de <= 1; gray <= img[y*HA + x];
                    @(posedge clk);
                end
                de <= 0; gray <= 0;
                repeat (HB) @(posedge clk);
            end
        end
    endtask

    initial begin
        $readmemh("sim/out/shape_img.hex", img);
        repeat (10) @(posedge clk);
        rst_n = 1;
        for (f = 0; f < 5; f = f + 1) frame;
        $display("threshold %0d", threshold);
        $display("objects %0d", obj_count);
        for (k = 0; k < obj_count; k = k + 1)
            $display("obj %0d %0d %0d %0d %0d", obj_data[k*41+38 +: 3],
                     obj_data[k*41+28 +: 10], obj_data[k*41+18 +: 10],
                     obj_data[k*41+9 +: 9], obj_data[k*41 +: 9]);
        $finish;
    end
endmodule

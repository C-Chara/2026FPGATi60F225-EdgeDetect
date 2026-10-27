`timescale 1ns/1ps

// shape_detector + digit_reader on a repeated 1280x720 image
// (tools/models/gen_digit_tb_data.py); prints the digit slots after enough
// frames for every candidate to be read twice, and the shape objects, in
// the format of sim/out/digit_expected.txt.
module tb_digits;
    localparam integer HA = 1280, VA = 720, HB = 220, VB = 12, FRAMES = 16;
    reg clk = 0, rst_n = 0, vsync_n = 1, de = 0;
    reg [7:0] gray = 0;
    reg [7:0] img [0:HA*VA-1];
    wire [5:0] obj_count;
    wire [32*41-1:0] obj_data;
    wire strobe, smp_v, smp_dark;
    wire [9:0] smp_x;
    wire [8:0] smp_y;
    wire [2:0] dig_count, slot_count;
    wire [4*38-1:0] dig_data, slot_box;
    wire [4*4-1:0] slot_digit;
    shape_detector dut (
        .clk(clk), .rst_n(rst_n), .vsync_n(vsync_n), .de(de), .gray(gray),
        .obj_count(obj_count), .obj_data(obj_data), .threshold(), .obj_strobe(strobe),
        .dbg_area(), .dbg_rho(), .dbg_cvx(), .dbg_j(), .dbg_fill(), .dbg_why(),
        .dig_count(dig_count), .dig_data(dig_data),
        .smp_v(smp_v), .smp_x(smp_x), .smp_y(smp_y), .smp_dark(smp_dark)
    );
    digit_reader rd (
        .clk(clk), .rst_n(rst_n), .vsync_n(vsync_n),
        .smp_v(smp_v), .smp_x(smp_x), .smp_y(smp_y), .smp_dark(smp_dark),
        .cand_strobe(strobe), .cand_count(dig_count), .cand_data(dig_data),
        .slot_count(slot_count), .slot_box(slot_box), .slot_digit(slot_digit)
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
        for (f = 0; f < FRAMES; f = f + 1) frame;
        vsync_n <= 0;                       // let the last read finish
        repeat (20000) @(posedge clk);
        $display("slots %0d", slot_count);
        for (k = 0; k < slot_count; k = k + 1)
            $display("slot %0d %0d %0d %0d %0d %0d", k, slot_box[k*38+28 +: 10],
                     slot_box[k*38+18 +: 10], slot_box[k*38+9 +: 9], slot_box[k*38 +: 9],
                     slot_digit[k*4 +: 4]);
        for (k = 0; k < obj_count; k = k + 1)
            $display("shape %0d", obj_data[k*41+38 +: 3]);
        $finish;
    end
endmodule

`timescale 1ns/1ps

// shape_detector + shape_overlay on a still image; the overlay output of the
// last frame is written to sim/out/overlay_frame.hex (RRGGBB per pixel) for
// tools/models/hex_to_png.py.
module tb_shape_overlay;
    localparam integer HA = 1280, VA = 720, HB = 220, VB = 12;
    reg clk = 0, rst_n = 0, vsync_n = 1, de = 0, hs = 0;
    reg [7:0] gray = 0;
    reg [7:0] img [0:HA*VA-1];
    wire [5:0] obj_count;
    wire [32*41-1:0] obj_data;
    wire [7:0] threshold;
    wire vs_o, hs_o, de_o;
    wire [23:0] rgb_o;
    shape_detector u_det (
        .clk(clk), .rst_n(rst_n), .vsync_n(vsync_n), .de(de), .gray(gray),
        .obj_count(obj_count), .obj_data(obj_data), .threshold(threshold)
    );
    shape_overlay u_ovl (
        .clk(clk), .rst_n(rst_n), .enable(1'b1),
        .vs_in(vsync_n), .hs_in(hs), .de_in(de), .rgb_in({gray, gray, gray}),
        .obj_count(obj_count), .obj_data(obj_data),
        .vs_out(vs_o), .hs_out(hs_o), .de_out(de_o), .rgb_out(rgb_o)
    );
    always #6.72 clk = ~clk;

    integer f, x, y, fd, dump;
    always @(posedge clk)
        if (dump && de_o) $fdisplay(fd, "%06x", rgb_o);

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
        dump = 0;
        $readmemh("sim/out/shape_img.hex", img);
        fd = $fopen("sim/out/overlay_frame.hex", "w");
        repeat (10) @(posedge clk);
        rst_n = 1;
        for (f = 0; f < 5; f = f + 1) frame;
        dump = 1;
        frame;
        repeat (10) @(posedge clk);
        dump = 0;
        $fclose(fd);
        $display("objects %0d", obj_count);
        $finish;
    end
endmodule

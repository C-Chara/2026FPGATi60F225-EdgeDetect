`timescale 1ns/1ps

// One Bayer frame through raw_demosaic; the RGB565 output of the first frame
// (gains still 1.0) goes to sim/out/raw_rtl.hex for raw_demosaic_model.py.
module tb_raw_demosaic;
    localparam integer HA = 1280, VA = 720, HB = 200;
    reg clk = 0, rst_n = 0, fv = 0, de = 0;
    reg [7:0] raw = 0;
    reg [7:0] img [0:HA*VA-1];
    reg [1:0] phase;
    wire de_out;
    wire [15:0] rgb;
    wire [9:0] gr, gb;
    raw_demosaic dut (
        .clk(clk), .rst_n(rst_n), .frame_valid(fv), .de(de), .raw(raw),
        .phase(phase), .gamma_on(1'b1), .de_out(de_out), .rgb565(rgb),
        .gain_r(gr), .gain_b(gb)
    );
    always #5.95 clk = ~clk;
    integer fd, x, y;
    always @(posedge clk) if (de_out) $fdisplay(fd, "%04x", rgb);
    initial begin
        if (!$value$plusargs("phase=%d", phase)) phase = 2'd3;
        $readmemh("sim/out/raw_img.hex", img);
        fd = $fopen("sim/out/raw_rtl.hex", "w");
        repeat (5) @(posedge clk);
        rst_n <= 1;
        repeat (5) @(posedge clk);
        fv <= 1;
        repeat (50) @(posedge clk);
        for (y = 0; y < VA; y = y + 1) begin
            for (x = 0; x < HA; x = x + 1) begin
                de <= 1; raw <= img[y*HA + x];
                @(posedge clk);
            end
            de <= 0; raw <= 0;
            repeat (HB) @(posedge clk);
        end
        repeat (20) @(posedge clk);
        fv <= 0;
        repeat (20) @(posedge clk);
        $fclose(fd);
        $display("gains after the frame: r %0d b %0d", gr, gb);
        $finish;
    end
endmodule

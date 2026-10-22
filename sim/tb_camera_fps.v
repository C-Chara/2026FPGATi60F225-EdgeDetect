`timescale 1ns/1ps
module tb_camera_fps;
    reg sys=0,pixel=0,rst=0,vs=0,ready=0;
    always #5 sys=~sys;
    always #7 pixel=~pixel;
    wire [7:0] bcd;
    wire valid;
    camera_fps #(.SYS_HZ(100)) dut (.clk_sys(sys),.rst_n(rst),.camera_vsync(vs),
        .camera_ready(ready),.clk_pixel(pixel),.fps_bcd(bcd),.fps_valid(valid));
    integer updates=0;
    reg [7:0] last_bcd=0;
    initial begin
        repeat(4) @(negedge sys);rst=1;
        repeat(130) @(negedge sys);
        if(valid) $fatal(1,"counted before initialization");
        ready=1;
        repeat(80) begin
            repeat(8) @(negedge sys);vs=1;
            repeat(2) @(negedge sys);vs=0;
        end
        repeat(4) @(negedge pixel);
        if(!valid || bcd!==8'h10) $fatal(1,"expected 10 fps, got %h",bcd);
        $display("PASS: initialization gating, VSYNC counting, BCD, asynchronous payload transfer");
        $finish;
    end
endmodule

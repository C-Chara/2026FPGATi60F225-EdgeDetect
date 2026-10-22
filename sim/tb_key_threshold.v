`timescale 1ns/1ps
module tb_key_threshold;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,vs=1;
    reg [1:0] keys=2'b11;
    wire [11:0] active,requested;
    wire [1:0] mode_active,mode_requested;
    key_threshold #(
        .DEBOUNCE_CYCLES(4), .LONG_PRESS_CYCLES(12),
        .MIN_THRESHOLD(86), .MAX_THRESHOLD(90)
    ) dut (
        .clk(clk),.rst_n(rst),.vsync_n(vs),.key_n(keys),
        .threshold_active(active),.threshold_requested(requested),
        .mode_active(mode_active),.mode_requested(mode_requested)
    );
    task ticks;
        input integer n;
        begin repeat(n) @(negedge clk);end
    endtask
    task tap;
        input [1:0] k;
        begin keys=k;ticks(9);keys=2'b11;ticks(9);end
    endtask
    task hold_k1;
        begin keys=2'b10;ticks(30);keys=2'b11;ticks(10);end
    endtask
    task commit_frame;
        begin vs=0;ticks(4);vs=1;ticks(2);end
    endtask
    integer i;
    initial begin
        ticks(3);rst=1;ticks(5);
        if(active!=88 || requested!=88 || mode_active!=2 || mode_requested!=2)
            $fatal(1,"initial settings");
        repeat(5) begin keys=2'b10;ticks(1);keys=2'b11;ticks(1);end
        ticks(10);
        if(requested!=88 || mode_requested!=2) $fatal(1,"bounce changed settings");

        keys=2'b10;ticks(9);
        if(requested!=88 || mode_requested!=2) $fatal(1,"K1 acted before release");
        keys=2'b11;ticks(9);
        if(requested!=89 || active!=88) $fatal(1,"K1 short press did not add one");
        commit_frame();
        if(active!=89) $fatal(1,"threshold was not committed at frame boundary");

        hold_k1();
        if(requested!=89 || mode_requested!=0 || mode_active!=2)
            $fatal(1,"K1 long hold changed threshold or failed mode switch");
        commit_frame();
        if(mode_active!=0) $fatal(1,"mode was not committed at frame boundary");

        tap(2'b01);
        if(requested!=88) $fatal(1,"K2 did not subtract one");
        tap(2'b00);
        if(requested!=88) $fatal(1,"simultaneous keys did not cancel");

        hold_k1();
        if(mode_requested!=1 || requested!=88) $fatal(1,"second long hold");
        hold_k1();
        if(mode_requested!=2 || requested!=88) $fatal(1,"third long hold");
        commit_frame();
        if(mode_active!=2) $fatal(1,"mode wrap commit");

        for(i=0;i<10;i=i+1) tap(2'b10);
        if(requested!=90) $fatal(1,"upper threshold clamp");
        for(i=0;i<10;i=i+1) tap(2'b01);
        if(requested!=86) $fatal(1,"lower threshold clamp");
        commit_frame();
        if(active!=86) $fatal(1,"final threshold commit");
        $display("PASS: K1 short +1, long mode cycle, K2 -1, debounce, clamps and frame commits");
        $finish;
    end
endmodule

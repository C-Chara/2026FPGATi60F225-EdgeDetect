`timescale 1ns/1ps
// key_threshold while frozen: K1/K2 short presses step the replay, K1+K2
// toggles playback, and none of them changes the threshold or median demo.
module tb_key_replay;
    reg clk=0;always #5 clk=~clk;
    reg rst=0,vs=1;
    reg [1:0] keys=2'b11;
    wire [11:0] active;
    wire [2:0] mode_active;
    wire freeze,median_on,noise_on,auto_on,newer,older,play;
    key_threshold #(.DEBOUNCE_CYCLES(4),.LONG_PRESS_CYCLES(12),.STEP(12'd8)) dut (
        .clk(clk),.rst_n(rst),.vsync_n(vs),.key_n(keys),
        .threshold_active(active),.threshold_requested(),
        .mode_active(mode_active),.mode_requested(),.freeze(freeze),
        .median_on(median_on),.noise_on(noise_on),.focus_mode(),.focus_code(),
        .tnr_mode(),.auto_value(12'd70),.auto_on(auto_on),
        .step_newer(newer),.step_older(older),.play_toggle(play));
    integer n_new=0,n_old=0,n_play=0;
    always @(posedge clk) if(rst) begin n_new<=n_new+newer;n_old<=n_old+older;n_play<=n_play+play;end
    task ticks;input integer n;begin repeat(n) @(negedge clk);end endtask
    task tap;input [1:0] k;begin keys=k;ticks(9);keys=2'b11;ticks(9);end endtask
    task hold;input [1:0] k;begin keys=k;ticks(30);keys=2'b11;ticks(10);end endtask
    task frame;begin vs=0;ticks(4);vs=1;ticks(2);end endtask
    initial begin
        ticks(3);rst=1;ticks(3);
        tap(2'b10);frame;                       // live: K1 -> manual 78
        $display("live K1: thr %0d auto %0d", active, auto_on);
        hold(2'b01);frame;                      // K2 long: freeze
        $display("freeze %0d", freeze);
        tap(2'b10);tap(2'b01);tap(2'b01);tap(2'b00);frame;
        $display("frozen: newer %0d older %0d play %0d thr %0d med %0d noise %0d",
                 n_new,n_old,n_play,active,median_on,noise_on);
        hold(2'b01);frame;
        tap(2'b01);frame;
        $display("unfrozen K2: freeze %0d thr %0d newer %0d older %0d", freeze, active, n_new, n_old);
        $finish;
    end
endmodule

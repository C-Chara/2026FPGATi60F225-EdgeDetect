`timescale 1ns/1ps

// K1 short release: threshold +1. K1 long hold: next display mode once.
// K2 short release: threshold -1. K2 long hold: toggle frame freeze once.
// K1+K2 held together for the long-press time: toggle focus mode. In focus
// mode K1/K2 short presses move the lens focus code instead of the threshold.
// With FOCUS_ENABLE=0 the same long combined hold steps tnr_mode instead:
//   1 <-> 2 (the top level decides what each value means).
// K1+K2 pressed and released together: next median demo state, cycling
//   median on -> median off (fine lines, e.g. line drawings, survive
//   without the median) -> median off + salt/pepper noise -> median on +
//   noise (the median removes it).
// A combined press never changes the threshold, mode or freeze.
// Automatic threshold (auto_on, set at power-up): the first K1/K2 short
// press switches to manual, starting from auto_value +/- 1. In manual mode
// K2 at MIN_THRESHOLD, or a K1+K2 short press, returns to automatic (that
// combined press then does not step the median demo).
// Both inputs debounce for 20 ms.
// Threshold and mode requests take effect at VSYNC low.
module key_threshold #(
    parameter integer DEBOUNCE_CYCLES=1488000,
    parameter integer LONG_PRESS_CYCLES=59520000,
    parameter [11:0] INITIAL_THRESHOLD=12'd88,
    parameter [11:0] STEP=12'd1,
    parameter [11:0] MIN_THRESHOLD=12'd16,
    parameter [11:0] MAX_THRESHOLD=12'd1024,
    parameter [2:0] INITIAL_MODE=3'd2,
    parameter [2:0] LAST_MODE=3'd2,
    parameter [9:0] INITIAL_FOCUS=10'd256,
    parameter [9:0] FOCUS_STEP=10'd32,
    // 0: K1+K2 long hold does nothing (fixed-focus lens).
    parameter FOCUS_ENABLE=1'b1
)(
    input wire clk,rst_n,vsync_n,
    input wire [1:0] key_n,
    output reg [11:0] threshold_active,
    output wire [11:0] threshold_requested,
    output reg [2:0] mode_active,
    output wire [2:0] mode_requested,
    output reg freeze,
    output reg median_on,
    output reg noise_on,
    output reg focus_mode,
    output reg [9:0] focus_code,
    output reg [1:0] tnr_mode,
    input  wire [11:0] auto_value,
    output reg auto_on
);
    (* async_reg="true" *) reg [1:0] key_meta,key_sync;
    reg [1:0] stable;
    reg [20:0] count_0,count_1;
    reg [25:0] hold_count,hold_count_1;
    reg long_fired,long_fired_1;
    reg [11:0] requested;
    reg [2:0] requested_mode;
    reg both_d;
    reg [25:0] combo_count;
    reg combo_long;
    reg [1:0] demo_state;
    wire both_pressed=!stable[0] && !stable[1];
    wire press_0=key_sync[0]!=stable[0] && count_0==DEBOUNCE_CYCLES-1 && !key_sync[0];
    wire release_0=key_sync[0]!=stable[0] && count_0==DEBOUNCE_CYCLES-1 && key_sync[0];
    wire press_1=key_sync[1]!=stable[1] && count_1==DEBOUNCE_CYCLES-1 && !key_sync[1];
    wire release_1=key_sync[1]!=stable[1] && count_1==DEBOUNCE_CYCLES-1 && key_sync[1];
    assign threshold_requested=requested;
    assign mode_requested=requested_mode;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) begin
            key_meta<=2'b11;key_sync<=2'b11;stable<=2'b11;
            count_0<=0;count_1<=0;requested<=INITIAL_THRESHOLD;
            threshold_active<=INITIAL_THRESHOLD;
            hold_count<=0;long_fired<=0;
            hold_count_1<=0;long_fired_1<=0;freeze<=0;
            both_d<=0;demo_state<=0;median_on<=1;noise_on<=0;
            combo_count<=0;combo_long<=0;focus_mode<=0;focus_code<=INITIAL_FOCUS;
            tnr_mode<=2'd1;
            auto_on<=1;
            requested_mode<=INITIAL_MODE;mode_active<=INITIAL_MODE;
        end else begin
            key_meta<=key_n;key_sync<=key_meta;
            if(key_sync[0]==stable[0]) count_0<=0;
            else if(count_0==DEBOUNCE_CYCLES-1) begin stable[0]<=key_sync[0];count_0<=0;end
            else count_0<=count_0+1'b1;
            if(key_sync[1]==stable[1]) count_1<=0;
            else if(count_1==DEBOUNCE_CYCLES-1) begin stable[1]<=key_sync[1];count_1<=0;end
            else count_1<=count_1+1'b1;
            // Defer K1's threshold step until release so a long hold changes
            // only the display mode, never the threshold as a side effect.
            if(both_pressed) begin
                long_fired<=1;
            end else if(press_0) begin
                hold_count<=0;
                long_fired<=0;
            end else if(release_0) begin
                hold_count<=0;
            end else if(!stable[0] && !key_sync[0] && !long_fired) begin
                if(hold_count==LONG_PRESS_CYCLES-1) begin
                    long_fired<=1;
                    requested_mode<=requested_mode==LAST_MODE ? 3'd0 : requested_mode+3'd1;
                end else hold_count<=hold_count+1'b1;
            end
            // K2 mirrors K1: a long hold toggles the freeze request only.
            if(both_pressed) begin
                long_fired_1<=1;
            end else if(press_1) begin
                hold_count_1<=0;
                long_fired_1<=0;
            end else if(release_1) begin
                hold_count_1<=0;
            end else if(!stable[1] && !key_sync[1] && !long_fired_1) begin
                if(hold_count_1==LONG_PRESS_CYCLES-1) begin
                    long_fired_1<=1;
                    freeze<=~freeze;
                end else hold_count_1<=hold_count_1+1'b1;
            end
            if(release_0 && !long_fired && stable[1] && !press_1) begin
                if(focus_mode)
                    focus_code<=focus_code>=10'd1023-FOCUS_STEP ? 10'd1023 : focus_code+FOCUS_STEP;
                else if(auto_on) begin
                    auto_on<=0;
                    requested<=auto_value>=MAX_THRESHOLD-STEP ? MAX_THRESHOLD : auto_value+STEP;
                end else
                    requested<=requested>=MAX_THRESHOLD-STEP ? MAX_THRESHOLD : requested+STEP;
            end else if(release_1 && !long_fired_1 && stable[0] && !press_0) begin
                if(focus_mode)
                    focus_code<=focus_code<=FOCUS_STEP ? 10'd0 : focus_code-FOCUS_STEP;
                else if(auto_on) begin
                    auto_on<=0;
                    requested<=auto_value<=MIN_THRESHOLD+STEP ? MIN_THRESHOLD : auto_value-STEP;
                end else if(requested==MIN_THRESHOLD)
                    auto_on<=1;
                else
                    requested<=requested<=MIN_THRESHOLD+STEP ? MIN_THRESHOLD : requested-STEP;
            end
            both_d<=both_pressed;
            if(both_pressed && !both_d) begin
                combo_count<=0;
                combo_long<=0;
            end else if(both_pressed && !combo_long) begin
                if(combo_count==LONG_PRESS_CYCLES-1) begin
                    combo_long<=1;
                    if(FOCUS_ENABLE) focus_mode<=~focus_mode;
                    else tnr_mode<=(tnr_mode==2'd1) ? 2'd2 : 2'd1;
                end else combo_count<=combo_count+1'b1;
            end
            // A short combined press steps the median demo when it ends.
            if(!both_pressed && both_d && !combo_long) begin
                if(!auto_on) auto_on<=1;          // manual: back to automatic
                else demo_state<=demo_state+2'd1;
            end
            if(!vsync_n) begin
                threshold_active<=requested;
                mode_active<=requested_mode;
                median_on<=!(demo_state[1]^demo_state[0]);
                noise_on<=demo_state[1];
            end
        end
    end
endmodule

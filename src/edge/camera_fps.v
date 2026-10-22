`timescale 1ns/1ps

// Count camera VSYNC rising edges over one second of the system clock.
// Payload is held for a full second and transferred using a toggle handshake.
// This measures camera frame sync, not HDMI refresh or valid image integrity.
module camera_fps #(
    parameter integer SYS_HZ = 96000000
)(
    input wire clk_sys, rst_n, camera_vsync, camera_ready,
    input wire clk_pixel,
    output reg [7:0] fps_bcd = 0,
    output reg fps_valid = 0
);
    (* async_reg = "true" *) reg [2:0] vs_sync = 0;
    (* async_reg = "true" *) reg [1:0] ready_sync = 0;
    reg [26:0] tick_count = 0;
    reg [6:0] frame_count = 0;
    reg [7:0] payload = 0;
    reg toggle = 0;
    wire rise = vs_sync[1] && !vs_sync[2];
    wire [6:0] measured = frame_count == 99 ? 7'd99 : frame_count + rise;
    wire [6:0] tens = measured / 7'd10;
    wire [6:0] ones = measured % 7'd10;
    always @(posedge clk_sys) begin
        if (!rst_n) begin
            vs_sync<=0; ready_sync<=0; tick_count<=0; frame_count<=0;
            payload<=0; toggle<=0;
        end else begin
            vs_sync <= {vs_sync[1:0],camera_vsync};
            ready_sync <= {ready_sync[0],camera_ready};
            if (!ready_sync[1]) begin
                tick_count<=0; frame_count<=0;
            end else if (tick_count == SYS_HZ-1) begin
                tick_count<=0; frame_count<=0;
                payload<={tens[3:0],ones[3:0]}; toggle<=!toggle;
            end else begin
                tick_count<=tick_count+1'b1; frame_count<=measured;
            end
        end
    end
    (* async_reg = "true" *) reg [1:0] toggle_sync = 0;
    reg toggle_seen = 0;
    always @(posedge clk_pixel) begin
        if (!rst_n) begin
            toggle_sync<=0; toggle_seen<=0; fps_bcd<=0; fps_valid<=0;
        end else begin
            toggle_sync<={toggle_sync[0],toggle};
            if (toggle_sync[1] != toggle_seen) begin
                toggle_seen<=toggle_sync[1]; fps_bcd<=payload; fps_valid<=1;
            end
        end
    end
endmodule

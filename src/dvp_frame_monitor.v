// Observe the registered DVP input without changing the captured stream.
// A falling VSYNC edge delimits one full frame period for either polarity.
module dvp_frame_monitor (
    input wire clk,
    input wire rst_n,
    input wire vsync,
    input wire href,
    output reg line_error = 0,
    output reg frame_error = 0,
    output reg checked_frame = 0
);
    reg vsync_d = 0;
    reg href_d = 0;
    reg [12:0] byte_count = 0;
    reg [10:0] line_count = 0;
    reg frame_started = 0;
    reg line_started = 0;
    always @(posedge clk) begin
        if (!rst_n) begin
            vsync_d <= 0;
            href_d <= 0;
            byte_count <= 0;
            line_count <= 0;
            frame_started <= 0;
            line_started <= 0;
            line_error <= 0;
            frame_error <= 0;
            checked_frame <= 0;
        end else begin
            vsync_d <= vsync;
            href_d <= href;
            if (href && !href_d) begin
                byte_count <= 1;
                line_started <= 1;
            end else if (href) begin
                if (byte_count != 13'h1fff) byte_count <= byte_count + 1'b1;
            end else begin
                byte_count <= 0;
            end
            if (href_d && !href) begin
                line_started <= 0;
                if (frame_started && line_started) begin
                    if (byte_count != 2560) line_error <= 1;
                    if (line_count != 11'h7ff) line_count <= line_count + 1'b1;
                end
            end
            if (vsync_d && !vsync) begin
                if (frame_started) begin
                    if (line_count != 720) frame_error <= 1;
                    checked_frame <= 1;
                end
                frame_started <= 1;
                line_count <= 0;
            end
        end
    end
endmodule

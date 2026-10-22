// Compare the known DDR diagnostic image with its pixel-clock reference.
// y=360..479: DDR ramp; y=480..599: identical directly generated ramp;
// y=600..719: green=exact RGB565 match, red=mismatch.
module ddr_video_compare (
    input wire clk,
    input wire rst_n,
    input wire vs,
    input wire request,
    input wire [15:0] actual,
    input wire [23:0] normal_rgb,
    output wire [23:0] rgb
);
    reg [10:0] x = 0;
    reg [9:0] y = 0;
    reg request_d = 0;
    reg [9:0] display_y = 0;
    reg [15:0] expected_d = 0;
    reg match_d = 0;
    wire [7:0] gray = x[7:0];
    wire [15:0] expected = {gray[7:3], gray[7:2], gray[7:3]};
    always @(posedge clk) begin
        if (!rst_n || !vs) begin
            x <= 0;
            y <= 0;
            request_d <= 0;
            display_y <= 0;
            expected_d <= 0;
            match_d <= 0;
        end else begin
            request_d <= request;
            if (request) x <= x + 1'b1;
            else x <= 0;
            if (request_d && !request) y <= y + 1'b1;
            display_y <= y;
            expected_d <= expected;
            match_d <= (actual == expected);
        end
    end
    wire [23:0] reference_rgb = {expected_d[15:11], 3'b0,
                                expected_d[10:5], 2'b0,
                                expected_d[4:0], 3'b0};
    assign rgb = display_y < 480 ? normal_rgb :
                 display_y < 600 ? reference_rgb :
                 match_d ? 24'h00ff00 : 24'hff0000;
endmodule

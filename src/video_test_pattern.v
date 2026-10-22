// Eight vertical colour bars for the 1280x720 HDMI timing in this project.
// de must be aligned with the RGB inputs of rgb2dvi.
module video_test_pattern (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        de,
    output reg  [23:0] rgb
);
    reg [10:0] active_x;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            active_x <= 11'd0;
        else if (!de)
            active_x <= 11'd0;
        else
            active_x <= active_x + 11'd1;
    end

    always @* begin
        if (!de)
            rgb = 24'h000000;
        else if (active_x < 11'd160)
            rgb = 24'hFFFFFF; // white
        else if (active_x < 11'd320)
            rgb = 24'hFFFF00; // yellow
        else if (active_x < 11'd480)
            rgb = 24'h00FFFF; // cyan
        else if (active_x < 11'd640)
            rgb = 24'h00FF00; // green
        else if (active_x < 11'd800)
            rgb = 24'hFF00FF; // magenta
        else if (active_x < 11'd960)
            rgb = 24'hFF0000; // red
        else if (active_x < 11'd1120)
            rgb = 24'h0000FF; // blue
        else
            rgb = 24'h000000; // black
    end
endmodule

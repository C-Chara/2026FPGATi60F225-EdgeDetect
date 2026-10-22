// Diagnostic bytes use the same frame/line timing as the captured camera stream.
// Upper half: white/red/green/blue horizontal bands (90 lines each).
// Lower half: five identical black-to-white ramps (256 pixels each).
// RGB565 bytes are emitted MSB first, matching OV5640 register 0x4300=0x61.
module ddr_video_diagnostic (
    input wire clk,
    input wire rst_n,
    input wire vsync,
    input wire de,
    output wire [7:0] data
);
    reg [11:0] byte_x = 0;
    reg [9:0] line_y = 0;
    reg de_d = 0;
    always @(posedge clk) begin
        if (!rst_n || !vsync) begin
            byte_x <= 0;
            line_y <= 0;
            de_d <= 0;
        end else begin
            de_d <= de;
            if (de) byte_x <= byte_x + 1'b1;
            else byte_x <= 0;
            if (de_d && !de) line_y <= line_y + 1'b1;
        end
    end
    wire [7:0] gray = byte_x[8:1];
    reg [15:0] pixel;
    always @* begin
        if (line_y < 90) pixel = 16'hffff;
        else if (line_y < 180) pixel = 16'hf800;
        else if (line_y < 270) pixel = 16'h07e0;
        else if (line_y < 360) pixel = 16'h001f;
        else pixel = {gray[7:3], gray[7:2], gray[7:3]};
    end
    assign data = byte_x[0] ? pixel[7:0] : pixel[15:8];
endmodule

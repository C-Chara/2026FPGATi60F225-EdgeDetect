`timescale 1ns/1ps
module tb_nms_bridge;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0, vsync_n = 0, pixel_valid = 0;
    reg [11:0] magnitude_in = 0, raw_magnitude_in = 0;
    wire [7:0] edge_out;
    wire pixel_valid_out;
    integer out_count = 0, i;

    hysteresis_stream #(.H_ACTIVE(12), .NMS_BRIDGE_ENABLE(1'b1)) dut (
        .clk(clk), .rst_n(rst_n), .vsync_n(vsync_n),
        .pixel_valid(pixel_valid), .magnitude_in(magnitude_in),
        .raw_magnitude_in(raw_magnitude_in), .gray_in(8'd0),
        .low_threshold_in(12'd60), .high_threshold_in(12'd120),
        .edge_out(edge_out), .gray_out(), .pixel_valid_out(pixel_valid_out)
    );

    task sample;
        input valid;
        input [11:0] nms, raw;
        reg expected;
        begin
            @(negedge clk);
            pixel_valid = valid;
            magnitude_in = nms;
            raw_magnitude_in = raw;
            @(posedge clk);
            #1;
            if (pixel_valid_out) begin
                expected = out_count <= 2;
                if (edge_out != (expected ? 8'hff : 8'h00))
                    $fatal(1, "pixel %0d: edge=%02x expected=%b", out_count, edge_out, expected);
                out_count = out_count + 1;
            end
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;
        repeat (2) sample(0, 0, 0);
        vsync_n = 1;
        for (i = 0; i < 12; i = i + 1) begin
            if (i == 0 || i == 2) sample(1, 120, 120);
            else if (i == 1 || i == 8) sample(1, 0, 80);
            else sample(1, 0, 0);
        end
        repeat (3) sample(0, 0, 0);
        if (out_count != 12) $fatal(1, "output count=%0d", out_count);
        $display("PASS: one-pixel NMS gap bridged; isolated suppressed response rejected");
        $finish;
    end
endmodule

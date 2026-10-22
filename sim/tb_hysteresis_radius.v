`timescale 1ns/1ps
module tb_hysteresis_radius;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg vsync_n = 0;
    reg pixel_valid = 0;
    reg [11:0] magnitude_in = 0;
    reg [7:0] gray_in = 0;
    wire [7:0] edge_out, gray_out;
    wire pixel_valid_out;
    integer out_count = 0;
    reg expected [0:35];
    integer i;

    hysteresis_stream #(.H_ACTIVE(12)) dut (
        .clk(clk), .rst_n(rst_n), .vsync_n(vsync_n),
        .pixel_valid(pixel_valid), .magnitude_in(magnitude_in),
        .gray_in(gray_in), .low_threshold_in(12'd60),
        .high_threshold_in(12'd120), .edge_out(edge_out),
        .gray_out(gray_out), .pixel_valid_out(pixel_valid_out)
    );

    task sample;
        input valid;
        input [11:0] magnitude;
        begin
            @(negedge clk);
            pixel_valid = valid;
            magnitude_in = magnitude;
            gray_in = 8'h55;
            @(posedge clk);
            #1;
            if (pixel_valid_out) begin
                if (out_count >= 36 || (edge_out != (expected[out_count] ? 8'hff : 8'h00))) begin
                    $display("FAIL: output %0d edge=%02x", out_count, edge_out);
                    $fatal(1);
                end
                out_count = out_count + 1;
            end
        end
    endtask

    initial begin
        for (i = 0; i < 36; i = i + 1) expected[i] = 0;
        expected[0] = 1;   // strong seed
        expected[4] = 1;   // strong seed two columns from next-row weak pixel
        expected[17] = 1;  // prior-row link, one column away
        expected[18] = 1;  // prior-row link, two columns away
        expected[24] = 1;  // strong seed
        expected[26] = 1;  // weak pixel across a one-pixel horizontal gap

        repeat (3) @(negedge clk);
        rst_n = 1;
        repeat (2) sample(0, 0);
        vsync_n = 1;
        for (i = 0; i < 12; i = i + 1)
            sample(1, (i == 0 || i == 4) ? 12'd120 : (i == 10 ? 12'd50 : 12'd0));
        repeat (4) sample(0, 0);
        for (i = 0; i < 12; i = i + 1)
            sample(1, (i == 5 || i == 6 || i == 9) ? 12'd80 : 12'd0);
        repeat (4) sample(0, 0);
        for (i = 0; i < 12; i = i + 1)
            sample(1, i == 0 ? 12'd120 : (i == 2 || i == 10 ? 12'd80 : 12'd0));
        repeat (4) sample(0, 0);
        if (out_count != 36) $fatal(1, "FAIL: output count %0d", out_count);
        $display("PASS: 36 pixels, two-column prior-row and one-gap horizontal links");
        $finish;
    end
endmodule

`timescale 1ns/1ps
module tb_nms_temporal_width;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0, vsync_n = 1, pixel_valid = 0;
    reg [7:0] edge_in = 0;
    reg [11:0] magnitude_in = 0;
    reg [11:0] neighbor_peak_in = 0;
    wire [7:0] edge_out;
    integer frame = 0;
    integer count [0:2];
    reg observed [0:2][0:3];
    integer i;

    edge_frame_hold #(.H_ACTIVE(4), .V_ACTIVE(1),
        .PEAK_GUARD_ENABLE(1'b1), .PEAK_TOLERANCE(13'd8)) dut (
        .clk(clk), .rst_n(rst_n), .vsync_n(vsync_n),
        .pixel_valid(pixel_valid), .edge_in(edge_in), .gray_in(8'd0),
        .magnitude_in(magnitude_in), .neighbor_peak_in(neighbor_peak_in),
        .release_threshold_in(12'd22),
        .edge_out(edge_out), .gray_out()
    );

    always @(posedge clk) begin
        if (rst_n && dut.valid_d) begin
            #1;
            observed[frame][count[frame]] = edge_out != 0;
            count[frame] = count[frame] + 1;
        end
    end

    task start_frame;
        input integer number;
        begin
            @(negedge clk);
            frame = number;
            pixel_valid = 0;
            vsync_n = 0;
            repeat (3) @(negedge clk);
            vsync_n = 1;
        end
    endtask

    task pixel;
        input bit edge_bit;
        input [11:0] mag, neighbor;
        begin
            @(negedge clk);
            pixel_valid = 1;
            edge_in = edge_bit ? 8'hff : 8'd0;
            magnitude_in = mag;
            neighbor_peak_in = neighbor;
        end
    endtask

    task end_frame;
        begin
            @(negedge clk);
            pixel_valid = 0;
            edge_in = 0;
            magnitude_in = 0;
            neighbor_peak_in = 0;
            repeat (3) @(negedge clk);
        end
    endtask

    initial begin
        for (i = 0; i < 3; i = i + 1) count[i] = 0;
        repeat (3) @(negedge clk);
        rst_n = 1;
        start_frame(0);
        pixel(1, 120, 80); pixel(0, 0, 0); pixel(0, 0, 0); pixel(0, 0, 0);
        end_frame();
        start_frame(1);
        pixel(0, 50, 120); pixel(1, 120, 80); pixel(0, 0, 0); pixel(0, 0, 0);
        end_frame();
        start_frame(2);
        pixel(0, 0, 0); pixel(0, 70, 75); pixel(0, 0, 0); pixel(0, 0, 0);
        end_frame();
        if (count[0] != 4 || count[1] != 4 || count[2] != 4)
            $fatal(1, "unexpected output counts: %0d %0d %0d", count[0], count[1], count[2]);
        if (!observed[0][0] || observed[1][0] || !observed[1][1] || !observed[2][1])
            $fatal(1, "old flank retained or stable near-threshold edge lost");
        $display("PASS: shifted edge does not widen; supported old edge survives one frame");
        $finish;
    end
endmodule

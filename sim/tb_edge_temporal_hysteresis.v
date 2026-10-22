`timescale 1ns/1ps
module tb_edge_temporal_hysteresis;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0;
    reg vsync_n = 0;
    reg pixel_valid = 0;
    reg [7:0] edge_in = 0;
    reg [7:0] gray_in = 8'h55;
    reg [11:0] magnitude_in = 0;
    wire [7:0] edge_out, gray_out;
    integer out_count = 0;
    integer frame, col;
    reg expected [0:27];
    reg check_valid;

    edge_frame_hold #(.H_ACTIVE(4), .V_ACTIVE(1)) dut (
        .clk(clk), .rst_n(rst_n), .vsync_n(vsync_n),
        .pixel_valid(pixel_valid), .edge_in(edge_in), .gray_in(gray_in),
        .magnitude_in(magnitude_in), .release_threshold_in(12'd30),
        .edge_out(edge_out), .gray_out(gray_out)
    );

    task sample;
        input valid;
        input [7:0] edge_value;
        input [11:0] magnitude;
        begin
            @(negedge clk);
            check_valid = dut.valid_d;
            pixel_valid = valid;
            edge_in = edge_value;
            magnitude_in = magnitude;
            @(posedge clk);
            #1;
            if (check_valid && out_count >= 28) $fatal(1, "Too many outputs");
            if (check_valid && edge_out !== (expected[out_count] ? 8'hff : 8'h00)) begin
                $display("FAIL: output %0d edge=%02x expected=%0d", out_count, edge_out, expected[out_count]);
                $fatal(1);
            end
            if (check_valid) begin
                if (gray_out !== 8'h55) $fatal(1, "Gray alignment at %0d", out_count);
                out_count = out_count + 1;
            end
        end
    endtask

    initial begin
        for (frame = 0; frame < 7; frame = frame + 1)
            for (col = 0; col < 4; col = col + 1)
                expected[frame*4+col] = (col == 1 && (frame == 0 || frame == 1 || frame == 2 || frame == 5)) ||
                                        (col == 2 && frame == 1);

        repeat (3) @(negedge clk);
        rst_n = 1;
        sample(0, 0, 0);
        vsync_n = 1;
        for (frame = 0; frame < 7; frame = frame + 1) begin
            for (col = 0; col < 4; col = col + 1) begin
                if (col == 1) begin
                    case (frame)
                        0,5: sample(1, 8'hff, 12'd120);
                        1: sample(1, 0, 12'd50);
                        2: sample(1, 0, 12'd40);
                        3: sample(1, 0, 12'd20);
                        4: sample(1, 0, 12'd50);
                        6: sample(1, 0, 12'd0);
                    endcase
                end else if (col == 2 && frame == 1)
                    sample(1, 8'hff, 12'd120);
                else
                    sample(1, 0, 0);
            end
            repeat (3) sample(0, 0, 0);
            vsync_n = 0;
            repeat (2) sample(0, 0, 0);
            vsync_n = 1;
        end
        if (out_count != 28) $fatal(1, "Output count %0d", out_count);
        $display("PASS: fast on, hold at 50/40, release at 20, no spontaneous reactivation");
        $finish;
    end
endmodule

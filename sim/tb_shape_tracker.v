`timescale 1ns/1ps

// Replays the detector result sequence of tools/models/shape_tracker_model.py
// (sim/out/tracker_in.txt) and prints the voted output after every update in
// the format of sim/out/tracker_expected.txt.
module tb_shape_tracker;
    reg clk = 0, rst_n = 0, strobe = 0;
    reg [5:0] in_count = 0;
    reg [32*41-1:0] in_data = 0;
    wire [5:0] obj_count;
    wire [32*41-1:0] obj_data;
    shape_tracker dut (
        .clk(clk), .rst_n(rst_n), .in_strobe(strobe), .in_count(in_count),
        .in_data(in_data), .obj_count(obj_count), .obj_data(obj_data)
    );
    always #6.72 clk = ~clk;

    integer f, n, i, u, c, x0, x1, y0, y1, r;
    initial begin
        f = $fopen("sim/out/tracker_in.txt", "r");
        repeat (4) @(posedge clk);
        rst_n <= 1;
        u = 0;
        while (!$feof(f)) begin
            r = $fscanf(f, "%d\n", n);
            if (r == 1) begin
                in_data = 0;
                for (i = 0; i < n; i = i + 1) begin
                    r = $fscanf(f, "%d %d %d %d %d\n", c, x0, x1, y0, y1);
                    in_data[i*41 +: 41] = {c[2:0], x0[9:0], x1[9:0], y0[8:0], y1[8:0]};
                end
                in_count = n;
                @(posedge clk) strobe <= 1;
                @(posedge clk) strobe <= 0;
                repeat (1300) @(posedge clk);
                $display("update %0d count %0d", u, obj_count);
                for (i = 0; i < obj_count; i = i + 1)
                    $display("obj %0d %0d %0d %0d %0d", obj_data[i*41+38 +: 3],
                             obj_data[i*41+28 +: 10], obj_data[i*41+18 +: 10],
                             obj_data[i*41+9 +: 9], obj_data[i*41 +: 9]);
                u = u + 1;
            end
        end
        $fclose(f);
        $finish;
    end
endmodule

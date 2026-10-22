`timescale 1ns/1ps

// One horizontal-gradient ridge on row 1 of a 6x4 stream.
//   frame 0: ridge at x=2, no stored state yet            -> x=2
//   frame 1: same picture shown again                     -> x=2
//   frame 2: NMS flips to x=3, both about equally strong  -> still x=2
//   frame 3: frame 2 shown again                          -> still x=2
//   frame 4: ridge really moves to x=3 (x=2 collapses)    -> x=3
module tb_edge_temporal_sticky;
    localparam integer W = 6;
    localparam integer H = 4;
    localparam integer FRAMES = 5;
    reg clk = 0;
    always #5 clk = ~clk;
    reg rst_n = 0, vsync_n = 1, pixel_valid = 0;
    reg [7:0] edge_in = 0, gray_in = 0;
    reg [11:0] magnitude_in = 0, neighbor_a_in = 0, neighbor_b_in = 0;
    wire [7:0] edge_out, gray_out;
    wire [1:0] direction_out;

    edge_temporal_sticky #(.H_ACTIVE(W), .V_ACTIVE(H)) dut (
        .clk(clk), .rst_n(rst_n), .vsync_n(vsync_n),
        .pixel_valid(pixel_valid), .edge_in(edge_in), .gray_in(gray_in),
        .magnitude_in(magnitude_in), .neighbor_a_in(neighbor_a_in),
        .neighbor_b_in(neighbor_b_in),
        .direction_in(2'd0), .release_threshold_in(12'd44),
        .onset_threshold_in(12'd110),
        .edge_out(edge_out), .gray_out(gray_out), .direction_out(direction_out)
    );

    // Outputs appear three clocks after the input pixel.
    reg [2:0] valid_pipe = 0;
    reg [7:0] gray_pipe [0:2];
    reg observed [0:FRAMES-1][0:W*H-1];
    integer frame = 0, taken = 0;
    always @(posedge clk) begin
        valid_pipe <= {valid_pipe[1:0], pixel_valid};
        gray_pipe[0] <= gray_in;
        gray_pipe[1] <= gray_pipe[0];
        gray_pipe[2] <= gray_pipe[1];
        if (valid_pipe[2]) begin
            if (gray_out !== gray_pipe[2])
                $fatal(1, "gray sideband is not three clocks late");
            observed[frame][taken] = edge_out != 0;
            taken = taken + 1;
        end else if (edge_out !== 8'd0)
            $fatal(1, "edge_out active outside the valid window");
    end

    // Columns 2 and 3 of row 1 carry the ridge and its flank; every other
    // pixel is flat. With direction 0, side a is the left neighbour.
    task send_frame;
        input integer number;
        input integer ridge_x;
        input [11:0] ridge_mag, flank_mag;
        integer x, y;
        begin
            @(negedge clk);
            vsync_n = 0;
            repeat (3) @(negedge clk);
            vsync_n = 1;
            frame = number;
            taken = 0;
            repeat (4) @(negedge clk);
            for (y = 0; y < H; y = y + 1) begin
                for (x = 0; x < W; x = x + 1) begin
                    pixel_valid = 1;
                    gray_in = y * W + x + 1;
                    edge_in = 8'd0;
                    magnitude_in = 12'd0;
                    neighbor_a_in = 12'd0;
                    neighbor_b_in = 12'd0;
                    if (y == 1 && (x == 2 || x == 3)) begin
                        edge_in = (x == ridge_x) ? 8'hff : 8'd0;
                        magnitude_in = (x == ridge_x) ? ridge_mag : flank_mag;
                        if (x == 2)
                            neighbor_b_in = (ridge_x == 3) ? ridge_mag : flank_mag;
                        else
                            neighbor_a_in = (ridge_x == 2) ? ridge_mag : flank_mag;
                    end
                    @(negedge clk);
                end
                pixel_valid = 0;
                edge_in = 8'd0;
                gray_in = 8'd0;
                magnitude_in = 12'd0;
                neighbor_a_in = 12'd0;
                neighbor_b_in = 12'd0;
                repeat (5) @(negedge clk);
            end
            if (taken != W * H)
                $fatal(1, "frame %0d produced %0d pixels", number, taken);
        end
    endtask

    task expect_ridge;
        input integer number;
        input integer x_on;
        integer i;
        begin
            for (i = 0; i < W * H; i = i + 1)
                if (observed[number][i] !== (i == W + x_on))
                    $fatal(1, "frame %0d pixel %0d = %b", number, i, observed[number][i]);
        end
    endtask

    initial begin
        repeat (3) @(negedge clk);
        rst_n = 1;
        send_frame(0, 2, 12'd120, 12'd100);
        send_frame(1, 2, 12'd120, 12'd100);
        send_frame(2, 3, 12'd118, 12'd116);
        send_frame(3, 3, 12'd118, 12'd116);
        send_frame(4, 3, 12'd150, 12'd60);
        expect_ridge(0, 2);
        expect_ridge(1, 2);
        expect_ridge(2, 2);
        expect_ridge(3, 2);
        expect_ridge(4, 3);
        $display("PASS: near-tie keeps the old winner, a clear move is followed");
        $finish;
    end
endmodule

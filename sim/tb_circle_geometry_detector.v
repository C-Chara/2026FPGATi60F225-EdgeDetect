`timescale 1ns/1ps
module tb_circle_geometry_detector;
    localparam W=256, H=256;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0, vs=1, de=0, edge_in=0;
    reg [1:0] edge_dir=0;
    wire found;
    wire [10:0] cx;
    wire [9:0] cy, radius;
    integer frame, yy, xx, gap, dx, dy, dist2, ax, ay;
    circle_geometry_detector #(
        .H_ACTIVE(W), .V_ACTIVE(H), .R_MIN(8), .R_MAX(16),
        .CENTER_MARGIN(8), .MIN_SCORE(11)
    ) dut (
        .clk(clk), .rst_n(rst_n), .vsync_n(vs), .de(de),
        .edge_pixel(edge_in), .edge_direction(edge_dir),
        .found(found), .center_x(cx), .center_y(cy), .radius_px(radius)
    );

    task video_frame;
        input integer shape; // 0 circle, 1 square, 2 empty, 3 shifted circle, 4 stripes, 5 grid, 6 thick annulus
        begin
            de=0; edge_in=0; vs=0;
            repeat (5) @(negedge clk);
            vs=1;
            for (yy=0; yy<H; yy=yy+1) begin
                for (xx=0; xx<W; xx=xx+1) begin
                    dx=xx-128; dy=yy-128; dist2=dx*dx+dy*dy;
                    de=1;
                    case(shape)
                        0: edge_in=(dist2>=46*46 && dist2<=50*50);
                        1: edge_in=((xx>=79 && xx<=81 || xx>=175 && xx<=177) &&
                                 yy>=79 && yy<=177) ||
                                ((yy>=79 && yy<=81 || yy>=175 && yy<=177) &&
                                 xx>=79 && xx<=177);
                        3: edge_in=((xx-116)*(xx-116)+(yy-140)*(yy-140)>=54*54 &&
                                    (xx-116)*(xx-116)+(yy-140)*(yy-140)<=58*58);
                        4: edge_in=(xx>=80 && xx<=176 && yy>=80 && yy<=176 &&
                                    ((xx-80)%16 <= 2));
                        5: edge_in=((xx%8)<=1 || (yy%8)<=1);
                        6: edge_in=(dist2>=38*38 && dist2<=58*58);
                        default: edge_in=0;
                    endcase
                    if (shape==3) begin dx=xx-116; dy=yy-140; end
                    ax=dx<0 ? -dx : dx;
                    ay=dy<0 ? -dy : dy;
                    if (shape==0 || shape==3 || shape==6) begin
                        if (2*ay<=ax) edge_dir=0;
                        else if (2*ax<=ay) edge_dir=1;
                        else edge_dir=(dx<0)==(dy<0) ? 2 : 3;
                    end else if (shape==1) begin
                        edge_dir=(xx>=79 && xx<=81 || xx>=175 && xx<=177) ? 0 : 1;
                    end else if (shape==5)
                        edge_dir=((xx%8)<=1) ? 0 : 1;
                    else edge_dir=0;
                    @(negedge clk);
                end
                de=0; edge_in=0;
                for (gap=0; gap<4; gap=gap+1) @(negedge clk);
            end
        end
    endtask

    initial begin
        repeat (6) @(negedge clk);
        rst_n=1;
        // The two occupancy banks are explicitly cleared before capture.
        repeat (8300) @(negedge clk);
        for (frame=0; frame<5; frame=frame+1) video_frame(0);
        $display("circle: found=%0d center=(%0d,%0d) radius=%0d score=%0d mask=%h side=%0d",found,cx,cy,radius,dut.best_score,dut.best_mask,dut.side_hits);
        if (!found || cx<100 || cx>156 || cy<100 || cy>156 || radius<32 || radius>64)
            $fatal(1,"circle not recognized near its true location");
        for (frame=0; frame<6; frame=frame+1) video_frame(1);
        $display("square: found=%0d",found);
        if (found) $fatal(1,"square falsely recognized as circle");
        for (frame=0; frame<6; frame=frame+1) video_frame(4);
        $display("stripes: found=%0d",found);
        if (found) $fatal(1,"parallel stripes falsely recognized as circle");
        for (frame=0; frame<6; frame=frame+1) video_frame(5);
        $display("dense grid: found=%0d score=%0d side=%0d",
                 found,dut.best_score,dut.side_hits);
        if (found) $fatal(1,"dense grid falsely recognized as circle");
        for (frame=0; frame<6; frame=frame+1) video_frame(6);
        $display("thick annulus: found=%0d score=%0d side=%0d",
                 found,dut.best_score,dut.side_hits);
        if (found) $fatal(1,"thick clutter annulus falsely recognized as crisp circle");
        for (frame=0; frame<5; frame=frame+1) video_frame(3);
        $display("shifted circle: found=%0d center=(%0d,%0d) radius=%0d score=%0d mask=%h side=%0d",found,cx,cy,radius,dut.best_score,dut.best_mask,dut.side_hits);
        if (!found || cx<96 || cx>136 || cy<120 || cy>160 || radius<40 || radius>72)
            $fatal(1,"shifted intermediate-radius circle not recognized");
        $display("PASS: two circles confirmed, square, stripes and dense grid rejected");
        $finish;
    end
endmodule








`timescale 1ns/1ps
module tb_circle_label_osd;
    reg clk=0;
    always #5 clk=~clk;
    reg rst_n=0, vs=1, de=0, found=0;
    wire [23:0] rgb_out;
    integer x,y,ink,border;
    circle_label_osd #(.H_ACTIVE(256), .V_ACTIVE(180)) dut (
        .clk(clk), .rst_n(rst_n), .vsync_n(vs), .de(de),
        .rgb_in(24'h123456), .found(found),
        .center_x(11'd128), .center_y(10'd120), .radius_px(10'd48),
        .rgb_out(rgb_out)
    );
    initial begin
        repeat(5) @(negedge clk);
        rst_n=1; vs=0;
        repeat(5) @(negedge clk);
        vs=1; found=1;
        ink=0; border=0;
        for(y=0;y<180;y=y+1) begin
            for(x=0;x<256;x=x+1) begin
                de=1;
                #1;
                if(rgb_out==24'hffff00) ink=ink+1;
                if(rgb_out==24'h00ffff) border=border+1;
                @(negedge clk);
            end
            de=0;
            repeat(4) @(negedge clk);
        end
        if(ink<100 || border<100)
            $fatal(1,"Chinese label missing: ink=%0d border=%0d",ink,border);
        found=0;
        de=1;
        #1;
        if(rgb_out!==24'h123456)
            $fatal(1,"annotation not transparent when detection is absent");
        $display("PASS: circle label has %0d glyph pixels and %0d border pixels",ink,border);
        $finish;
    end
endmodule

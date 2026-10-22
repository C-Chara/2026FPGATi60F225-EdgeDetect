`timescale 1ns/1ps
module tb_median5;
 localparam W=16; localparam H=10; reg clk=0; always #5 clk=~clk; reg rst_n=0,hs=1,vs=1,de=0; reg [7:0] gray=0; wire vo,do_; wire [7:0] go,co; integer x,y,b,count=0,bad=0;
 median5x5_video #(.H_ACTIVE(W)) dut(.clk(clk),.rst_n(rst_n),.hs_in(hs),.vs_in(vs),.de_in(de),.gray_in(gray),.hs_out(),.vs_out(vo),.de_out(do_),.gray_out(go),.gray_center_out(co));
 always @(posedge clk) begin #1; if(do_) begin count=count+1; if(go!==8'd100) begin bad=bad+1; $display("bad %0d: go=%0d co=%0d",count,go,co); end end end
 initial begin repeat(4) @(negedge clk); rst_n=1; vs=0; repeat(8) @(negedge clk); vs=1; for(y=0;y<H;y=y+1) begin for(x=0;x<W;x=x+1) begin de=1; gray=(x==8 && y==5)?8'd255:8'd100; @(negedge clk); end de=0;gray=0; for(b=0;b<12;b=b+1) @(negedge clk); end repeat(50) @(negedge clk); $display("RESULT count=%0d bad=%0d",count,bad); if(count<1 || bad!=0) $fatal(1,"median5 failed"); $finish; end
endmodule


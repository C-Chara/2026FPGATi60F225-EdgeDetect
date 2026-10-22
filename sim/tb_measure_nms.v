`timescale 1ns/1ps
module tb_measure_nms;
localparam integer W=32,H=12,B=80; reg clk=0; always #5 clk=~clk; reg rst_n=0,vs=1,de=0; reg [7:0] gray=0;
wire mv; wire [7:0] mg,mc; median3x3_video #(.H_ACTIVE(W)) m(.clk(clk),.rst_n(rst_n),.hs_in(1'b1),.vs_in(vs),.de_in(de),.gray_in(gray),.hs_out(),.vs_out(),.de_out(mv),.gray_out(mg),.gray_center_out(mc));
wire [7:0] se,sg; wire [11:0] sm; wire [1:0] sd; wire sv; sobel_stream #(.H_ACTIVE(W)) s(.clk(clk),.rst_n(rst_n),.vsync_n(vs),.pixel_valid(mv),.gray_in(mg),.gray_center_in(mc),.edge_out(se),.magnitude_out(sm),.direction_out(sd),.window_valid_out(sv),.gray_center_out(sg));
wire [11:0] nm; wire [7:0] ng; wire nv; nms_stream #(.H_ACTIVE(W-2)) n(.clk(clk),.rst_n(rst_n),.vsync_n(vs),.pixel_valid(sv),.magnitude_in(sm),.direction_in(sd),.gray_in(sg),.magnitude_out(nm),.pixel_valid_out(nv),.gray_out(ng));
wire [7:0] he,hg; wire hv; hysteresis_stream #(.H_ACTIVE(W-4)) h(.clk(clk),.rst_n(rst_n),.vsync_n(vs),.pixel_valid(nv),.magnitude_in(nm),.gray_in(ng),.low_threshold_in(12'd60),.high_threshold_in(12'd120),.edge_out(he),.gray_out(hg),.pixel_valid_out(hv));
reg [11:0] md1,md2; wire [7:0] ee,eg; edge_frame_hold #(.H_ACTIVE(W-4),.V_ACTIVE(H)) e(.clk(clk),.rst_n(rst_n),.vsync_n(vs),.pixel_valid(hv),.edge_in(he),.gray_in(hg),.magnitude_in(md2),.release_threshold_in(12'd30),.edge_out(ee),.gray_out(eg));
integer it[0:255],ix[0:255],iy[0:255],id,cyc=0,x,y,b,seen=0,dly; always @(posedge clk) begin cyc=cyc+1; if(de)begin it[gray]=cyc;ix[gray]=x;iy[gray]=y;end; md1<=nm;md2<=md1; #1; if(eg!=0 && seen<40) begin seen=seen+1; if(it[eg]>=0) begin dly=cyc-it[eg]; $display("out cyc=%0d val=%0d incyc=%0d xy=(%0d,%0d) delay=%0d de=%b",cyc,eg,it[eg],ix[eg],iy[eg],dly,de);end end end
initial begin for(id=0;id<256;id=id+1)begin it[id]=-1;ix[id]=-1;iy[id]=-1;end repeat(5)@(negedge clk);rst_n=1;vs=0;repeat(30)@(negedge clk);vs=1;for(y=0;y<H;y=y+1)begin for(x=0;x<W;x=x+1)begin de=1;gray=(y*32+x)*73;@(negedge clk);end de=0;gray=0;for(b=0;b<B;b=b+1)@(negedge clk);end repeat(100)@(negedge clk);$finish;end
endmodule

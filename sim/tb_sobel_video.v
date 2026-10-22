`timescale 1ns/1ps
module tb_sobel_video;
    parameter TEST_MEDIAN=0;
    localparam W=12,H=8,LATENCY=TEST_MEDIAN ? 20:8;
    reg clk=0; always #5 clk=~clk;
    reg rst_n=0, hs=1, vs=1, de=0;
    reg [15:0] rgb=0;
    wire ho,vo,dout;
    wire [23:0] rout;
    wire [7:0] gray,edge_pixel;
    reg [11:0] threshold=120;
    sobel_video #(.H_ACTIVE(W),.MEDIAN_ENABLE(TEST_MEDIAN),.RUNTIME_THRESHOLD(1)) dut (
        .clk(clk),.rst_n(rst_n),.hs_in(hs),.vs_in(vs),.de_in(de),
        .rgb565_in(rgb),.hs_out(ho),.vs_out(vo),.de_out(dout),
        .rgb_out(rout),.gray_out(gray),.edge_out(edge_pixel),.threshold_in(threshold)
    );
    integer sx,sy,frame,expected_gray,expected_edge,checked=0;
    integer qp,j,vx,vy,gradient_x,gradient_y,mag;
    integer qgray[0:LATENCY-1],qedge[0:LATENCY-1];
    reg [LATENCY-1:0] qhs={LATENCY{1'b1}},qvs={LATENCY{1'b1}},qde=0;
    function [15:0] pixel;
        input integer f,x,y;
        integer value;
        begin
            case(f)
                0:value=255;
                1:value=x>=4 ? 255:0;
                2:value=y>=3 ? 255:0;
                3:value=(x==4 && y==3) ? 255:0;
                4:value=((x+y)%2) ? 255:0;
                default:value=x*17+y*13;
            endcase
            pixel={value[7:3],value[7:2],value[7:3]};
        end
    endfunction
    // Independent software sort of the causal 3x3 neighborhood.
    function integer filtered;
        input integer f,x,y;
        integer samples[0:8];
        integer a,b,temp;
        begin
            if(!TEST_MEDIAN) filtered=luma(f,x,y);
            else if(x<2 || y<2) filtered=0;
            else begin
                for(a=0;a<9;a=a+1) samples[a]=luma(f,x-2+a%3,y-2+a/3);
                for(a=0;a<8;a=a+1)
                    for(b=a+1;b<9;b=b+1)
                        if(samples[a]>samples[b]) begin temp=samples[a];samples[a]=samples[b];samples[b]=temp;end
                filtered=samples[4];
            end
        end
    endfunction
    function integer luma;
        input integer f,x,y;
        reg [15:0] p;
        integer r,g,b;
        begin
            p=pixel(f,x,y);
            r={p[15:11],p[15:13]};g={p[10:5],p[10:9]};b={p[4:0],p[4:2]};
            luma=(77*r+150*g+29*b+128)/256;
        end
    endfunction
    always @(posedge clk) begin
        if (!rst_n) begin
            qhs={LATENCY{1'b1}};qvs={LATENCY{1'b1}};qde=0;
            for(j=0;j<LATENCY;j=j+1) begin qgray[j]=0;qedge[j]=0;end
        end else begin
            for(j=LATENCY-1;j>0;j=j-1) begin qgray[j]=qgray[j-1];qedge[j]=qedge[j-1];end
            qgray[0]=expected_gray;qedge[0]=expected_edge;
            qhs={qhs[LATENCY-2:0],hs};qvs={qvs[LATENCY-2:0],vs};qde={qde[LATENCY-2:0],de};
            #1;
            if ({ho,vo,dout} !== {qhs[LATENCY-1],qvs[LATENCY-1],qde[LATENCY-1]}) $fatal(1,"control latency");
            if (qde[LATENCY-1]) begin
                if (gray !== qgray[LATENCY-1] || edge_pixel !== qedge[LATENCY-1])
                    $fatal(1,"pixel mismatch frame=%0d gray=%0d/%0d edge=%0d/%0d",frame,gray,qgray[LATENCY-1],edge_pixel,qedge[LATENCY-1]);
                qp=qedge[LATENCY-1] ? 255 : qgray[LATENCY-1]/2;
                if (rout !== {qp[7:0],qp[7:0],qp[7:0]}) $fatal(1,"overlay mismatch");
                checked=checked+1;
            end else if(rout !== 0) $fatal(1,"blanking RGB");
        end
    end
    task blank;
        input integer n;
        begin
            repeat(n) begin @(negedge clk);de=0;rgb=0;expected_gray=0;expected_edge=0;end
        end
    endtask
    initial begin
        expected_gray=0;expected_edge=0;
        repeat(3) @(negedge clk);
        rst_n=1;
        for(frame=0;frame<6;frame=frame+1) begin
            threshold=frame==1 ? 1024:120;
            vs=0;blank(4);vs=1;blank(4);
            for(sy=0;sy<H;sy=sy+1) begin
                for(sx=0;sx<W;sx=sx+1) begin
                    @(negedge clk);de=1;hs=1;rgb=pixel(frame,sx,sy);
                    expected_gray=0;expected_edge=0;
                    if(sx>=(TEST_MEDIAN ? 4:2) && sy>=(TEST_MEDIAN ? 4:2)) begin
                        expected_gray=filtered(frame,sx-1,sy-1);
                        gradient_x=0;gradient_y=0;
                        for(vy=0;vy<3;vy=vy+1) begin
                            gradient_x=gradient_x+(vy==1 ? 2:1)*(filtered(frame,sx,sy-2+vy)-filtered(frame,sx-2,sy-2+vy));
                        end
                        for(vx=0;vx<3;vx=vx+1) begin
                            gradient_y=gradient_y+(vx==1 ? 2:1)*(filtered(frame,sx-2+vx,sy)-filtered(frame,sx-2+vx,sy-2));
                        end
                        mag=(gradient_x<0 ? -gradient_x:gradient_x)+(gradient_y<0 ? -gradient_y:gradient_y);
                        expected_edge=mag>=threshold ? 255:0;
                    end
                end
                hs=0;blank(5);hs=1;
            end
            blank(LATENCY+4);
        end
        blank(LATENCY+4);
        if(checked!=6*W*H) $fatal(1,"pixel count %0d",checked);
        $display("PASS: %0d pixels, six frames; median=%0d, exact filter/Sobel/overlay/borders, runtime threshold and %0d-clock controls",checked,TEST_MEDIAN,LATENCY);
        $finish;
    end
endmodule

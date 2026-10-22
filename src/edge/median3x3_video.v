`timescale 1ns/1ps

// Two synchronous line RAMs form a causal 3x3 window. Nine pipelined
// odd/even compare-exchange passes sort all nine samples, selecting rank 4.
// One pixel per clock; data/HS/VS/DE latency = 3 + 9 = 12 clocks.
module median3x3_video #(
    parameter integer H_ACTIVE = 1280
)(
    input wire clk, rst_n, hs_in, vs_in, de_in,
    input wire [7:0] gray_in,
    output wire hs_out, vs_out, de_out,
    output wire [7:0] gray_out,
    output wire [7:0] gray_center_out
);
    reg [7:0] line_1 [0:H_ACTIVE-1];
    reg [7:0] line_2 [0:H_ACTIVE-1];
    reg [7:0] line_1_q, line_2_q;
    reg [10:0] column, column_q;
    reg [1:0] completed_rows;
    reg valid_q, valid_qq, candidate_q, candidate_qq, window_valid;
    reg [7:0] gray_q, middle_q, bottom_q;
    reg [7:0] p00,p01,p02,p10,p11,p12,p20,p21,p22;
    reg [11:0] hs_pipe, vs_pipe, de_pipe;
    always @(posedge clk) begin
        if (de_in) begin
            line_1_q <= line_1[column];
            line_1[column] <= gray_in;
        end
        if (valid_q) begin
            line_2_q <= line_2[column_q];
            line_2[column_q] <= line_1_q;
        end
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            column<=0; column_q<=0; completed_rows<=0;
            valid_q<=0; valid_qq<=0; candidate_q<=0; candidate_qq<=0; window_valid<=0;
            gray_q<=0; middle_q<=0; bottom_q<=0;
            p00<=0;p01<=0;p02<=0;p10<=0;p11<=0;p12<=0;p20<=0;p21<=0;p22<=0;
            hs_pipe<=12'hfff;vs_pipe<=12'hfff;de_pipe<=0;
        end else begin
            hs_pipe<={hs_pipe[10:0],hs_in};
            vs_pipe<={vs_pipe[10:0],vs_in};
            de_pipe<={de_pipe[10:0],de_in};
            valid_q<=de_in;valid_qq<=valid_q;
            column_q<=column;gray_q<=gray_in;
            middle_q<=line_1_q;bottom_q<=gray_q;
            candidate_q<=de_in && completed_rows>=2 && column>=2;
            candidate_qq<=candidate_q;
            if (!vs_in) begin column<=0;completed_rows<=0;end
            else if (de_in) begin
                if (column==H_ACTIVE-1) begin
                    column<=0;
                    if(completed_rows!=3) completed_rows<=completed_rows+1'b1;
                end else column<=column+1'b1;
            end else column<=0;
            if (valid_qq) begin
                p00<=p01;p01<=p02;p02<=line_2_q;
                p10<=p11;p11<=p12;p12<=middle_q;
                p20<=p21;p21<=p22;p22<=bottom_q;
                window_valid<=candidate_qq;
            end else begin
                p00<=0;p01<=0;p02<=0;p10<=0;p11<=0;p12<=0;p20<=0;p21<=0;p22<=0;
                window_valid<=0;
            end
        end
    end
    wire [7:0] window_samples [0:8];
    assign window_samples[0]=p00;assign window_samples[1]=p01;assign window_samples[2]=p02;
    assign window_samples[3]=p10;assign window_samples[4]=p11;assign window_samples[5]=p12;
    assign window_samples[6]=p20;assign window_samples[7]=p21;assign window_samples[8]=p22;
    wire [7:0] sorted [0:8][0:8];
    reg [8:0] candidate_pipe;
    reg [7:0] center_pipe [0:8];
    integer center_stage;
    always @(posedge clk or negedge rst_n) begin
        if(!rst_n) candidate_pipe<=0;
        else candidate_pipe<={candidate_pipe[7:0],window_valid};
    end
    // Carry the original center pixel through the same nine sorting stages.
    always @(posedge clk) begin
        center_pipe[0] <= p11;
        for (center_stage=1; center_stage<9; center_stage=center_stage+1)
            center_pipe[center_stage] <= center_pipe[center_stage-1];
    end
    genvar stage,item;
    generate for(stage=0;stage<9;stage=stage+1) begin: sorting_pass
        for(item=0;item<9;item=item+1) begin: sorting_item
            wire [7:0] a,b;
            if(stage==0) begin: first_input
                assign a=window_samples[item];
            end else begin: prior_input
                assign a=sorted[stage-1][item];
            end
            if((item%2)==(stage%2) && item<8) begin: lower_half
                if(stage==0) assign b=window_samples[item+1];
                else assign b=sorted[stage-1][item+1];
                reg [7:0] q;
                always @(posedge clk) q<=a<b ? a:b;
                assign sorted[stage][item]=q;
            end else if((item%2)!=(stage%2) && item>0) begin: upper_half
                if(stage==0) assign b=window_samples[item-1];
                else assign b=sorted[stage-1][item-1];
                reg [7:0] q;
                always @(posedge clk) q<=a>b ? a:b;
                assign sorted[stage][item]=q;
            end else begin: unpaired
                reg [7:0] q;
                always @(posedge clk) q<=a;
                assign sorted[stage][item]=q;
            end
        end
    end endgenerate
    assign hs_out=hs_pipe[11];assign vs_out=vs_pipe[11];assign de_out=de_pipe[11];
    assign gray_out=candidate_pipe[8] ? sorted[8][4] : 8'd0;
    assign gray_center_out=candidate_pipe[8] ? center_pipe[8] : 8'd0;
endmodule

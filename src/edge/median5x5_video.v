`timescale 1ns/1ps

// Streaming exact 5x5 median filter. Four synchronous line memories build
// the vertical window; 25 odd/even compare-exchange passes select rank 12.
// The original centre pixel is carried through the same timing so the Sobel
// stage can keep its colour overlay aligned.
module median5x5_video #(
    parameter integer H_ACTIVE = 1280
)(
    input  wire clk, rst_n, hs_in, vs_in, de_in,
    input  wire [7:0] gray_in,
    output wire hs_out, vs_out, de_out,
    output wire [7:0] gray_out,
    output wire [7:0] gray_center_out
);
    reg [7:0] line_1 [0:H_ACTIVE-1];
    reg [7:0] line_2 [0:H_ACTIVE-1];
    reg [7:0] line_3 [0:H_ACTIVE-1];
    reg [7:0] line_4 [0:H_ACTIVE-1];
    reg [7:0] line_1_q, line_2_q, line_3_q, line_4_q;
    reg [10:0] column, column_q, column_qq, column_qqq;
    reg valid_q, valid_qq, valid_qqq, valid_qqqq;
    reg candidate_q, candidate_qq, candidate_qqq, candidate_qqqq;
    reg [2:0] completed_rows;
    reg [7:0] gray_q, gray_1_q, gray_2_q, gray_3_q;
    reg [7:0] p00,p01,p02,p03,p04;
    reg [7:0] p10,p11,p12,p13,p14;
    reg [7:0] p20,p21,p22,p23,p24;
    reg [7:0] p30,p31,p32,p33,p34;
    reg [7:0] p40,p41,p42,p43,p44;
    reg window_valid;
    reg [28:0] hs_pipe, vs_pipe;
    reg [24:0] candidate_pipe;
    reg [7:0] center_pipe [0:24];
    integer center_stage;

    // Four cascaded synchronous line memories.
    always @(posedge clk) begin
        if (de_in) begin
            line_1_q <= line_1[column];
            line_1[column] <= gray_in;
        end
        if (valid_q) begin
            line_2_q <= line_2[column_q];
            line_2[column_q] <= line_1_q;
        end
        if (valid_qq) begin
            line_3_q <= line_3[column_qq];
            line_3[column_qq] <= line_2_q;
        end
        if (valid_qqq) begin
            line_4_q <= line_4[column_qqq];
            line_4[column_qqq] <= line_3_q;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            column<=0; column_q<=0; column_qq<=0; column_qqq<=0;
            completed_rows<=0;
            valid_q<=0; valid_qq<=0; valid_qqq<=0; valid_qqqq<=0;
            candidate_q<=0; candidate_qq<=0; candidate_qqq<=0; candidate_qqqq<=0;
            gray_q<=0; gray_1_q<=0; gray_2_q<=0; gray_3_q<=0;
            p00<=0;p01<=0;p02<=0;p03<=0;p04<=0;
            p10<=0;p11<=0;p12<=0;p13<=0;p14<=0;
            p20<=0;p21<=0;p22<=0;p23<=0;p24<=0;
            p30<=0;p31<=0;p32<=0;p33<=0;p34<=0;
            p40<=0;p41<=0;p42<=0;p43<=0;p44<=0;
            window_valid<=0;
            hs_pipe<=29'h1fffffff; vs_pipe<=29'h1fffffff;
            candidate_pipe<=0;
        end else begin
            hs_pipe <= {hs_pipe[27:0],hs_in};
            vs_pipe <= {vs_pipe[27:0],vs_in};
            valid_q<=de_in; valid_qq<=valid_q;
            valid_qqq<=valid_qq; valid_qqqq<=valid_qqq;
            candidate_q <= de_in && (completed_rows>=4) && (column>=4);
            candidate_qq <= candidate_q;
            candidate_qqq <= candidate_qq;
            candidate_qqqq <= candidate_qqq;
            column_q<=column; column_qq<=column_q; column_qqq<=column_qq;
            gray_q<=gray_in; gray_1_q<=gray_q;
            gray_2_q<=gray_1_q; gray_3_q<=gray_2_q;
            candidate_pipe <= {candidate_pipe[23:0],window_valid};

            if (!vs_in) begin
                column<=0; completed_rows<=0;
            end else if (de_in) begin
                if (column==H_ACTIVE-1) begin
                    column<=0;
                    if (completed_rows!=5) completed_rows<=completed_rows+1'b1;
                end else column<=column+1'b1;
            end else column<=0;

            if (valid_qqqq) begin
                p00<=p01;p01<=p02;p02<=p03;p03<=p04;p04<=line_4_q;
                p10<=p11;p11<=p12;p12<=p13;p13<=p14;p14<=line_3_q;
                p20<=p21;p21<=p22;p22<=p23;p23<=p24;p24<=line_2_q;
                p30<=p31;p31<=p32;p32<=p33;p33<=p34;p34<=line_1_q;
                p40<=p41;p41<=p42;p42<=p43;p43<=p44;p44<=gray_3_q;
                window_valid <= candidate_qqqq;
            end else begin
                window_valid<=0;
                p00<=0;p01<=0;p02<=0;p03<=0;p04<=0;
                p10<=0;p11<=0;p12<=0;p13<=0;p14<=0;
                p20<=0;p21<=0;p22<=0;p23<=0;p24<=0;
                p30<=0;p31<=0;p32<=0;p33<=0;p34<=0;
                p40<=0;p41<=0;p42<=0;p43<=0;p44<=0;
            end
        end
    end

    wire [7:0] window_samples [0:24];
    assign window_samples[0]=p00; assign window_samples[1]=p01; assign window_samples[2]=p02; assign window_samples[3]=p03; assign window_samples[4]=p04;
    assign window_samples[5]=p10; assign window_samples[6]=p11; assign window_samples[7]=p12; assign window_samples[8]=p13; assign window_samples[9]=p14;
    assign window_samples[10]=p20; assign window_samples[11]=p21; assign window_samples[12]=p22; assign window_samples[13]=p23; assign window_samples[14]=p24;
    assign window_samples[15]=p30; assign window_samples[16]=p31; assign window_samples[17]=p32; assign window_samples[18]=p33; assign window_samples[19]=p34;
    assign window_samples[20]=p40; assign window_samples[21]=p41; assign window_samples[22]=p42; assign window_samples[23]=p43; assign window_samples[24]=p44;

    wire [7:0] sorted [0:25][0:24];
    genvar stage,item;
    generate for(stage=0;stage<25;stage=stage+1) begin: sorting_pass
        for(item=0;item<25;item=item+1) begin: sorting_item
            wire [7:0] a,b;
            if(stage==0) assign a=window_samples[item];
            else assign a=sorted[stage-1][item];
            if((item%2)==(stage%2) && item<24) begin: lower_half
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

    always @(posedge clk) begin
        center_pipe[0] <= p22;
        for (center_stage=1;center_stage<25;center_stage=center_stage+1)
            center_pipe[center_stage] <= center_pipe[center_stage-1];
    end

    assign hs_out=hs_pipe[28];
    assign vs_out=vs_pipe[28];
    assign de_out=candidate_pipe[24];
    assign gray_out=candidate_pipe[24] ? sorted[24][12] : 8'd0;
    assign gray_center_out=candidate_pipe[24] ? center_pipe[24] : 8'd0;
endmodule

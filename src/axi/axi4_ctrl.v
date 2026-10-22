//  by CrazyBird
module axi4_ctrl #(
	parameter 	C_ID_LEN      = 8, 
			C_DATA_LEN    = 128, 
			C_DATA_SIZE   = 4, 	//	C_DATA_LEN=8:0, 16:1, 32:2, 64:3, 128:4, 256:5, 512:6, 1024:7
			
			C_BURST_LEN   = 128,
			
			C_STRB_LEN    = C_DATA_LEN / 8, 
			C_ADDR_INC    = C_BURST_LEN * C_STRB_LEN,
			
			C_BASE_ADDR   = 32'h00000000, 	//	Start at 0x00000000 by default
			C_BUF_SIZE    = 22, 			//	Allocate 2^22 bytes (4MB) by default. The module takes 4*4MB by default. 
			C_RD_END_ADDR = 1280 * 720,
			
			C_W_WIDTH     = 64, 
			C_R_WIDTH     = 8, 
			C_AXI_HZ      = 96000000, 
			
			//	Temporal noise reduction on the stored RGB565 frame. Before each
			//	write burst the same 2 KB of the previous stored frame is read
			//	back, and every colour channel is filtered against it:
			//	  |cur - prev| <= DEAD        keep prev (sensor noise)
			//	  DEAD < |cur - prev| <= TH   prev steps 1 LSB toward cur
			//	  |cur - prev| > TH           take cur (motion)
			//	The stored frame is the filter state, so both the displayed
			//	image and the edge chain see the filtered pixels.
			C_TNR         = 0, 
			C_TNR_DEAD5   = 1, 	//	R and B (5 bits)
			C_TNR_TH5     = 3, 
			C_TNR_DEAD6   = 2, 	//	G (6 bits)
			C_TNR_TH6     = 6
)(
    input  wire                 axi_clk         ,
    input  wire                 axi_reset       ,
    
    output       [C_ID_LEN-1:0]      axi_awid        ,
    output       [31:0]      axi_awaddr      ,
    output       [ 7:0]      axi_awlen       ,
    output       [ 2:0]      axi_awsize      ,
    output       [ 1:0]      axi_awburst     ,
    output                   axi_awlock      ,
    output       [ 3:0]      axi_awcache     ,
    output       [ 2:0]      axi_awprot      ,
    output       [ 3:0]      axi_awqos       ,
    output reg                  axi_awvalid     ,
    input  wire                 axi_awready     ,
    
    output       [C_DATA_LEN-1:0]      axi_wdata       ,
    output       [C_STRB_LEN-1:0]      axi_wstrb       ,
    output                   axi_wlast       ,
    output reg                  axi_wvalid      ,
    input  wire                 axi_wready      ,
    
    input  wire     [C_ID_LEN-1:0]      axi_bid         ,
    input  wire     [ 1:0]      axi_bresp       ,
    input  wire                 axi_bvalid      ,
    output                   axi_bready      ,
    
    output       [C_ID_LEN-1:0]      axi_arid        ,
    output       [31:0]      axi_araddr      ,
    output       [ 7:0]      axi_arlen       ,
    output       [ 2:0]      axi_arsize      ,
    output       [ 1:0]      axi_arburst     ,
    output                   axi_arlock      ,
    output       [ 3:0]      axi_arcache     ,
    output       [ 2:0]      axi_arprot      ,
    output       [ 3:0]      axi_arqos       ,
    output wire                 axi_arvalid     ,
    input  wire                 axi_arready     ,
    
    input  wire     [C_ID_LEN-1:0]      axi_rid         ,
    input  wire     [C_DATA_LEN-1:0]      axi_rdata       ,
    input  wire     [ 1:0]      axi_rresp       ,
    input  wire                 axi_rlast       ,
    input  wire                 axi_rvalid      ,
    output                   axi_rready      ,
    
    input  wire                 wframe_pclk     ,
    input  wire                 wframe_vsync    ,		//	Writter VSync. Flush on falling edge. Connect to EOF. 
    input  wire                 wframe_data_en  ,
    input  wire     [C_W_WIDTH-1:0]      wframe_data     ,
    
    input  wire                 rframe_pclk     ,
    input  wire                 rframe_vsync    ,		//	Reader VSync. Flush on falling edge. Connect to ~EOF. 
    input  wire                 rframe_data_en  ,
    output wire     [C_R_WIDTH-1:0]      rframe_data     ,
    
    output 		[31:0] 	tp_o, 

    // Time from a written frame's EOF until the reader starts that frame.
    output reg 	[7:0] 	frame_latency_ms = 0, 
    output reg 		frame_latency_valid = 0, 

    //	Temporal filter on/off at run time (any clock, resynchronized).
    input  wire 		tnr_on
);
	
	//	The display reader and the previous-frame reader share AR/R. Only
	//	one read burst is in flight at a time; r_prev_busy marks the
	//	previous-frame burst from its AR until its RLAST.
	reg 			r_disp_arvalid = 0, r_prev_arvalid = 0, r_prev_busy = 0; 
	assign axi_arvalid = r_disp_arvalid | r_prev_arvalid; 
	//	A display burst accepted by the controller and not yet finished.
	//	Unlike the display FSM this is not cleared by the per-frame FIFO
	//	reset, so its beats can never be taken for previous-frame data.
	reg 			r_disp_inflight = 0; 
	always @(posedge axi_clk) begin
		if(axi_reset) r_disp_inflight <= 0; 
		else if(axi_arready && ~r_prev_busy) r_disp_inflight <= 1; 
		else if(axi_rvalid && axi_rlast && ~r_prev_busy) r_disp_inflight <= 0; 
	end
	reg 	[C_DATA_LEN-1:0] 	r_tnr_q = 0; 	//	filtered word for the current write beat
	
	initial begin
		axi_awvalid <= 0; 
		axi_wvalid <= 0; 
		r_disp_arvalid <= 0; 
	end

	assign axi_awid    = {C_ID_LEN{1'b0}};
	assign axi_awlen   = C_BURST_LEN - 1'b1;
	assign axi_awsize  = C_DATA_SIZE;
	assign axi_awburst = 2'b01;	//	INCR
	assign axi_awlock  = 1'b0;
	assign axi_awcache = 0;
	assign axi_awprot  = 3'b0;
	assign axi_awqos   = 4'b0;
	assign axi_wstrb   = 32'hFFFFFFFF;
	assign axi_bready  = 1; 
	    
	assign axi_arid    = {C_ID_LEN{1'b0}};
	assign axi_arlen   = C_BURST_LEN - 1'b1;
	assign axi_arsize  = C_DATA_SIZE;
	assign axi_arburst = 2'b01;	//	INCR
	assign axi_arlock  = 1'b0;
	assign axi_arcache = 0;
	assign axi_arprot  = 3'b0;
	assign axi_arqos   = 4'b0;
	assign axi_rready  = 1; 
	
	
	
	
	////////////////////////////////////////////////////////////////
	//	R/W Schedule
	reg	[1:0] 	rc_wframe_index;
	reg	[1:0] 	rc_rframe_index;

	//	Use 4 data buffers to simplify control. 
	wire 	[1:0] 	w_wframe_index_p1 = rc_wframe_index + 1; 
	wire 	[1:0] 	w_wframe_index_next = (w_wframe_index_p1 == rc_rframe_index) ? rc_wframe_index + 2 : rc_wframe_index + 1; 

	reg 	[1:0] 	r_wframe_index_last = 0; 
	
	reg 			r_wframe_inc = 0, r_rframe_inc = 0; 

	always @(posedge axi_clk) begin
		if(axi_reset) begin
			rc_wframe_index <= 2'b0;
			rc_rframe_index <= 2'd2;
			r_wframe_index_last <= 0; 
			
		end else begin
			rc_wframe_index <= rc_wframe_index; 
			rc_rframe_index <= rc_rframe_index; 
			
			//	When wfifo_rd_rst_busy_neg, write pointer increments. When rfifo_wr_rst_busy_neg, read pointer increments. 
			case ({r_rframe_inc, r_wframe_inc})
				2'b01: begin
						//	Write increment only. 
						rc_wframe_index <= w_wframe_index_next; 	//	Use 4 buffers. 
						r_wframe_index_last <= rc_wframe_index; 
					end
				2'b10: begin
						//	Use r_wframe_index_last. 
						rc_rframe_index <= r_wframe_index_last; 
					end
				2'b11: begin
						//	Update write & read pointer simutaneously. 
						rc_wframe_index <= w_wframe_index_next; 	//	Use 4 buffers. 
						rc_rframe_index <= rc_wframe_index; 		
					end
			endcase
			
		end
	end
	
	
	
	//	The frame finished last (r_wframe_index_last is not updated when
	//	the reader switches at the same clock).
	reg 	[1:0] 	r_tnr_prev_index = 0; 
	reg 			r_tnr_prev_valid = 0; 
	always @(posedge axi_clk) begin
		if(axi_reset) begin
			r_tnr_prev_index <= 0; r_tnr_prev_valid <= 0; 
		end else if(r_wframe_inc) begin
			r_tnr_prev_index <= rc_wframe_index; r_tnr_prev_valid <= 1; 
		end
	end
	
	////////////////////////////////////////////////////////////////
	//	Frame latency monitor (diagnostic only, does not affect scheduling).
	reg 	[16:0] 	rc_ms_tick = 0; 
	reg 	[7:0] 	rc_latency_ms = 0; 
	reg 			r_latency_armed = 0; 
	reg 	[1:0] 	r_latency_index = 0; 
	always @(posedge axi_clk) begin
		if(axi_reset) begin
			rc_ms_tick <= 0; rc_latency_ms <= 0; r_latency_armed <= 0; r_latency_index <= 0; 
			frame_latency_ms <= 0; frame_latency_valid <= 0; 
		end else begin
			if(rc_ms_tick == C_AXI_HZ / 1000 - 1) begin
				rc_ms_tick <= 0; 
				if(rc_latency_ms != 8'hFF) rc_latency_ms <= rc_latency_ms + 1; 
			end else rc_ms_tick <= rc_ms_tick + 1; 
			//	The reader picked up the frame being timed. 
			if(r_rframe_inc && r_latency_armed && !r_wframe_inc && (r_wframe_index_last == r_latency_index)) begin
				frame_latency_ms <= rc_latency_ms; 
				frame_latency_valid <= 1; 
				r_latency_armed <= 0; 
			end
			//	A frame just finished: start timing it. If the reader starts at
			//	the same clock it takes this frame at once (latency 0). 
			if(r_wframe_inc) begin
				rc_ms_tick <= 0; rc_latency_ms <= 0; 
				r_latency_armed <= ~r_rframe_inc; 
				r_latency_index <= rc_wframe_index; 
				if(r_rframe_inc) begin frame_latency_ms <= 0; frame_latency_valid <= 1; end
			end
		end
	end


	////////////////////////////////////////////////////////////////
	//	AXI Writter

	wire 				w_wfifo_pempty, w_wfifo_empty; 
	wire 				w_wfifo_ren; 
	wire 	[C_DATA_LEN-1:0] 	w_wfifo_rdata; 

	//	On EOF when ~empty, flush the last data then reset FIFO. 
	reg 	[3:0] 	rs_w = 0; 
	wire 	[3:0] 	ws_w_idle = 0; 
	wire 	[3:0] 	ws_w_wdata = 1; 
	wire 	[3:0] 	ws_w_winc = 2; 
	wire 	[3:0] 	ws_w_eof = 3; 
	wire 	[3:0] 	ws_w_prd = 4; 		//	TNR: wait for the read port
	wire 	[3:0] 	ws_w_prdata = 5; 	//	TNR: previous frame in, filtered words to buffer
	wire 	[3:0] 	ws_w_pdrain = 6; 	//	TNR: let the buffer pipeline finish
	
	//	Display reader wants the port (same condition as its IDLE state).
	wire 			w_disp_want; 
	wire 			w_disp_idle; 
	reg 	[7:0] 	rc_pbeat = 0; 
	reg 	[1:0] 	rc_pdrain = 0; 

	//	Write Pointer. Burst bytes is always C_ADDR_INC. 
	reg 	[C_BUF_SIZE-1:0] 	rc_w_ptr = 0; 
	reg 	[0:0] 		rc_w_eof = 0; 
	reg 				r_w_rst = 1; 
	
	//	Burst Control
	reg 	[7:0] 	rc_burst = 0; 	//	Compare to C_BURST_LEN - 1. 
	
	//	EOF Monitor. 
	reg 	[1:0] 	r_wframe_sync = 0; 	
	reg 			r_weof_pending = 0; 

	always @(posedge axi_clk or posedge axi_reset) begin
		if(axi_reset) begin
			rs_w <= 0; 
			rc_w_ptr <= 0; 
			rc_w_eof <= 0; 
			r_w_rst <= 1; 
			axi_awvalid <= 0; 
			axi_wvalid <= 0; 
			r_wframe_sync <= 0; 
			r_weof_pending <= 0; 
			r_wframe_inc <= 0; 
			r_prev_arvalid <= 0; 
			r_prev_busy <= 0; 
			rc_pbeat <= 0; 
			rc_pdrain <= 0; 
			
		end else begin
			if(axi_arready && r_prev_arvalid) begin
				r_prev_arvalid <= 0; 
			end
			rc_w_eof <= 0; 
			r_wframe_inc <= 0; 
			
			//	Raise EOF on falling edge of VSYNC. 
			r_wframe_sync <= {r_wframe_sync, wframe_vsync}; 
			if(r_wframe_sync == 2'b10) begin
				r_weof_pending <= 1; 
			end else begin
			end
			
			if(axi_awready) begin
				axi_awvalid <= 0; 
			end else begin
			end
			
			case (rs_w)
				ws_w_idle: begin
						rc_burst <= 0; 
						r_w_rst <= 0; 
						
						if(~w_wfifo_pempty || (r_weof_pending && (~w_wfifo_empty))) begin
							//	A full burst, or the last data at EOF. With TNR,
							//	read the previous frame first.
							if(C_TNR) begin
								rs_w <= ws_w_prd; 
							end else begin
								axi_awvalid <= 1; 
								axi_wvalid <= 1; 
								rs_w <= ws_w_wdata; 
							end
							
						end else if(r_weof_pending) begin
							//	EOF. Reset FIFO. Increment write pointer. 
							r_w_rst <= 1; 
							r_wframe_inc <= 1; 
							rs_w <= ws_w_eof; 
							
						end else begin
						end
					end
					
				ws_w_eof: begin
						//	Wait for some cycles to release reset. 
						r_weof_pending <= 0; 
						rc_w_ptr <= 0; 
						
						rc_w_eof <= rc_w_eof + 1; 
						if(&rc_w_eof)
							rs_w <= ws_w_idle; 
						else begin
						end
					end
					
				ws_w_wdata: begin
						rc_burst <= rc_burst + axi_wready; 
						
						//	On last transaction terminate write. 
						if(axi_wlast && axi_wready) begin
							axi_wvalid <= 0; 
							rs_w <= ws_w_winc; 
						end else begin
						end
					end
					
				ws_w_winc: begin
						rc_w_ptr <= rc_w_ptr + C_ADDR_INC; 
						rs_w <= ws_w_idle; 
					end
				
				ws_w_prd: begin
						//	Take the read port only while the display reader is
						//	idle and does not want it (the display has priority).
						rc_pbeat <= 0; 
						if(w_disp_idle && ~w_disp_want && ~r_prev_busy && ~r_disp_inflight) begin
							r_prev_arvalid <= 1; 
							r_prev_busy <= 1; 
							rs_w <= ws_w_prdata; 
						end
					end
				
				ws_w_prdata: begin
						if(axi_rvalid) rc_pbeat <= rc_pbeat + 1; 
						if(axi_rvalid && axi_rlast) begin
							r_prev_busy <= 0; 
							rc_pdrain <= 0; 
							rs_w <= ws_w_pdrain; 
						end
					end
				
				ws_w_pdrain: begin
						rc_pdrain <= rc_pdrain + 1; 
						if(&rc_pdrain) begin
							axi_awvalid <= 1; 
							axi_wvalid <= 1; 
							rs_w <= ws_w_wdata; 
						end
					end
			endcase
		end
	end
	assign axi_awaddr = C_BASE_ADDR + {rc_wframe_index, rc_w_ptr}; 
	assign axi_wdata = C_TNR ? r_tnr_q : w_wfifo_rdata; 
	assign axi_wlast = (rc_burst >= C_BURST_LEN - 1); 
	
	//	With TNR the camera words are taken while the previous frame arrives.
	assign w_wfifo_ren = C_TNR ? ((rs_w == ws_w_prdata) && axi_rvalid) : (axi_wvalid && axi_wready); 
	
	////////////////////////////////////////////////////////////////
	//	Temporal filter
	(* async_reg = "true" *) reg 	[1:0] 	r_tnr_on_sync = 0; 
	always @(posedge axi_clk) r_tnr_on_sync <= {r_tnr_on_sync[0], tnr_on}; 
	wire 			w_tnr_active = r_tnr_on_sync[1] && r_tnr_prev_valid; 
	
	function [5:0] tnr_ch; 
		input [5:0] cur, prev; 
		input [5:0] dead, th; 
		reg [5:0] diff; 
		reg up; 
		begin
			up = cur > prev; 
			diff = up ? cur - prev : prev - cur; 
			if(diff <= dead) tnr_ch = prev; 
			else if(diff <= th) tnr_ch = up ? prev + 1'b1 : prev - 1'b1; 
			else tnr_ch = cur; 
		end
	endfunction
	
	//	Each 16-bit lane is one RGB565 pixel {R[4:0], G[5:0], B[4:0]} (the
	//	same lanes the 16-bit display FIFO reads), so every lane is filtered
	//	the same way.
	function [C_DATA_LEN-1:0] tnr_word; 
		input [C_DATA_LEN-1:0] cur, prev; 
		integer k; 
		reg [5:0] r, g, b; 
		begin
			for(k = 0; k < C_DATA_LEN / 16; k = k + 1) begin
				r = tnr_ch({1'b0, cur[16*k+11 +: 5]}, {1'b0, prev[16*k+11 +: 5]}, C_TNR_DEAD5, C_TNR_TH5); 
				g = tnr_ch(cur[16*k+5 +: 6], prev[16*k+5 +: 6], C_TNR_DEAD6, C_TNR_TH6); 
				b = tnr_ch({1'b0, cur[16*k +: 5]}, {1'b0, prev[16*k +: 5]}, C_TNR_DEAD5, C_TNR_TH5); 
				tnr_word[16*k +: 16] = {r[4:0], g, b[4:0]}; 
			end
		end
	endfunction
	
	//	Stage 1 registers the camera word and the previous-frame word; stage 2
	//	writes the filtered word into the burst buffer. The write burst then
	//	reads the buffer one word ahead (r_tnr_q holds the current beat).
	reg 	[C_DATA_LEN-1:0] 	r_tnr_buf [0:C_BURST_LEN-1]; 
	reg 	[C_DATA_LEN-1:0] 	r_tnr_cur = 0, r_tnr_prev = 0; 
	reg 	[6:0] 	r_tnr_idx = 0; 
	reg 			r_tnr_v = 0, r_tnr_en = 0; 
	wire 	[6:0] 	w_tnr_raddr = (rs_w == ws_w_wdata) ? rc_burst[6:0] + (axi_wvalid && axi_wready) : 7'd0; 
	always @(posedge axi_clk) begin
		r_tnr_v <= C_TNR && (rs_w == ws_w_prdata) && axi_rvalid; 
		r_tnr_cur <= w_wfifo_rdata; 
		r_tnr_prev <= axi_rdata; 
		r_tnr_idx <= rc_pbeat[6:0]; 
		r_tnr_en <= w_tnr_active; 
		if(r_tnr_v) r_tnr_buf[r_tnr_idx] <= r_tnr_en ? tnr_word(r_tnr_cur, r_tnr_prev) : r_tnr_cur; 
		r_tnr_q <= r_tnr_buf[w_tnr_raddr]; 
	end
	
	
	assign tp_o[1:0] = {rs_w[1:0]}; 
	assign tp_o[2] = axi_wvalid; 
	assign tp_o[3] = wframe_data_en; 
	
	
	generate
		if(C_W_WIDTH == 64) begin: Gen_FIFO_W64
			W0_FIFO_64 u_W0_FIFO_64 
			(
			    .wr_clk_i       (wframe_pclk    ),
			    .wr_en_i        (wframe_data_en),
			    .wdata          (wframe_data    ),
			    
			    .a_rst_i 	(r_w_rst), 

			    .rd_clk_i       (axi_clk        ),
			    .rd_en_i        (w_wfifo_ren     ),
			    .rdata          (w_wfifo_rdata    ),
			    .prog_empty_o	(w_wfifo_pempty),
			    .empty_o 		(w_wfifo_empty)
			);
		end else if(C_W_WIDTH == 32) begin: Gen_FIFO_W32
			W0_FIFO_32 u_W0_FIFO_32
			(
			    .wr_clk_i       (wframe_pclk    ),
			    .wr_en_i        (wframe_data_en),
			    .wdata          (wframe_data    ),
			    
			    .a_rst_i 	(r_w_rst), 

			    .rd_clk_i       (axi_clk        ),
			    .rd_en_i        (w_wfifo_ren     ),
			    .rdata          (w_wfifo_rdata    ),
			    .prog_empty_o	(w_wfifo_pempty),
			    .empty_o 		(w_wfifo_empty)
			);
		end else if(C_W_WIDTH == 16) begin: Gen_FIFO_W32
			W0_FIFO_16 u_W0_FIFO_16
			(
			    .wr_clk_i       (wframe_pclk    ),
			    .wr_en_i        (wframe_data_en),
			    .wdata          (wframe_data    ),
			    
			    .a_rst_i 	(r_w_rst), 

			    .rd_clk_i       (axi_clk        ),
			    .rd_en_i        (w_wfifo_ren     ),
			    .rdata          (w_wfifo_rdata    ),
			    .prog_empty_o	(w_wfifo_pempty),
			    .empty_o 		(w_wfifo_empty)
			);
		end else if(C_W_WIDTH == 8) begin: Gen_FIFO_W8
			W0_FIFO_8 u_W0_FIFO_8 
			(
			    .wr_clk_i       (wframe_pclk    ),
			    .wr_en_i        (wframe_data_en),
			    .wdata          (wframe_data    ),
			    
			    .a_rst_i 	(r_w_rst), 

			    .rd_clk_i       (axi_clk        ),
			    .rd_en_i        (w_wfifo_ren     ),
			    .rdata          (w_wfifo_rdata    ),
			    .prog_empty_o	(w_wfifo_pempty),
			    .empty_o 		(w_wfifo_empty)
			);
		end
	endgenerate




















reg                             rframe_vsync_dly;

always @(posedge rframe_pclk)
begin
    if(axi_reset == 1'b1)
        rframe_vsync_dly <= 1'b0;
    else
        rframe_vsync_dly <= rframe_vsync;
end

wire                            rframe_vsync_neg;
assign rframe_vsync_neg =  rframe_vsync_dly & ~rframe_vsync;

reg             [4:0]           rfifo_cnt;

always @(posedge rframe_pclk)
begin
    if(axi_reset == 1'b1)
        rfifo_cnt <= 5'h1f;
    else
    begin
        if(rframe_vsync_neg == 1'b1)
            rfifo_cnt <= 5'h1f;
        else if(rfifo_cnt > 5'd0)
            rfifo_cnt <= rfifo_cnt - 1'b1;
        else
            rfifo_cnt <= 5'b0;
    end
end

reg                             rfifo_rst;

always @(posedge rframe_pclk)
begin
    if(axi_reset == 1'b1)
        rfifo_rst <= 1'b1;
    else
    begin
        if(rfifo_cnt == 5'b0)
            rfifo_rst <= 1'b0;
        else
            rfifo_rst <= 1'b1;
    end
end


wire 			w_rfifo_rst = axi_reset || rfifo_rst; 

reg                             rfifo_wenb;
reg             [C_DATA_LEN-1:0]          rfifo_wdata;
wire            [ 9:0]          rfifo_wcnt;
wire 					  rfifo_wfull; 
wire                            rfifo_wr_rst_busy;
wire 					w_rfifo_aempty; 
wire 					w_rfifo_empty; 


generate
	if(C_R_WIDTH == 8) begin: Gen_RFIFO_8
		R0_FIFO_8 u_R0_FIFO_8
		(
			.wr_clk_i		(axi_clk),
			.wr_en_i		(rfifo_wenb),
			.wdata			(rfifo_wdata),
			.a_rst_i		(w_rfifo_rst), 
			.prog_full_o		(rfifo_wfull),
			
			.rd_clk_i		(rframe_pclk),
			.rd_en_i		(rframe_data_en),
			.rdata			(rframe_data),
			.empty_o		(w_rfifo_empty),
			.almost_empty_o	(w_rfifo_aempty)
		);
	end else if(C_R_WIDTH == 16) begin: Gen_RFIFO_16	
		R0_FIFO_16 u_R0_FIFO_16
		(
			.wr_clk_i		(axi_clk),
			.wr_en_i		(rfifo_wenb),
			.wdata			(rfifo_wdata),
			.a_rst_i		(w_rfifo_rst), 
			.prog_full_o		(rfifo_wfull),
			
			.rd_clk_i		(rframe_pclk),
			.rd_en_i		(rframe_data_en),
			.rdata			(rframe_data),
			.empty_o		(w_rfifo_empty),
			.almost_empty_o	(w_rfifo_aempty)
		);
	end
endgenerate
		
reg r_rfifo_rst = 0; 
always @(posedge axi_clk)
begin
	r_rfifo_rst <= w_rfifo_rst; 
end

//assign tp_o[7:0] = {w_rfifo_empty, rfifo_wfull, rframe_data_en, rfifo_wenb, rfifo_rst, axi_reset, rframe_pclk, axi_clk}; 

reg             [15:0]               rfifo_wr_rst_busy_dly = 2'b0;

always @(posedge axi_clk or posedge r_rfifo_rst)
begin
    if(r_rfifo_rst == 1'b1)
        rfifo_wr_rst_busy_dly <= 0;
    else
        rfifo_wr_rst_busy_dly <= {rfifo_wr_rst_busy_dly,1'b1};
end

wire                                rfifo_wr_rst_busy_neg;
assign rfifo_wr_rst_busy_neg = (rfifo_wr_rst_busy_dly[1:0] == 2'b01) ? 1'b1 : 1'b0;

reg             [4:0]               read_ddr_delay_cnt;

always @(posedge axi_clk or posedge r_rfifo_rst)
begin
    if(r_rfifo_rst == 1'b1)
        read_ddr_delay_cnt <= 5'b0;
    else
    begin
        if(rfifo_wr_rst_busy_neg == 1'b1)
            read_ddr_delay_cnt <= 5'd31;
        else if(read_ddr_delay_cnt > 5'b0)
            read_ddr_delay_cnt <= read_ddr_delay_cnt - 1'b1;
        else
            read_ddr_delay_cnt <= 5'b0;
    end
end

always @(posedge axi_clk or posedge axi_reset) begin
	if(axi_reset)
		r_rframe_inc <= 0; 
	else
		r_rframe_inc <= rfifo_wr_rst_busy_neg; 
end


wire                                read_ddr_init_flag;
assign read_ddr_init_flag = (read_ddr_delay_cnt == 5'd1) ? 1'b1 : 1'b0;

//----------------------------------------------------------------------




//----------------------------------------------------------------------
localparam S_READ_IDLE = 2'd0;
localparam S_READ_ADDR = 2'd1;
localparam S_READ_DATA = 2'd2;

reg             [ 1:0]          rd_state;
reg             [ 8:0]          rdata_cnt;
reg             [C_BUF_SIZE-1:0]          araddr;
reg 					r_rd_pend = 0; 


always @(posedge axi_clk or posedge r_rfifo_rst)
begin
    if(r_rfifo_rst) begin
        rd_state <= S_READ_IDLE;
	  r_disp_arvalid <= 0; 
	  r_rd_pend <= 0; 
    end else
    begin
	
	
	
	if(axi_arready) begin
		r_disp_arvalid <= 0; 
	end else begin
	end
	if(axi_rvalid && axi_rlast && ~r_prev_busy) begin
		 r_rd_pend <= 0; 
	end else begin
	end
	
        case(rd_state)
            S_READ_IDLE : 
            begin
			//	Continue if RFIFO ~Full. 
                if(w_disp_want && ~r_prev_busy) begin	//	rfifo_wcnt < 10'd256))
                    rd_state <= S_READ_ADDR;
                end else
                    rd_state <= S_READ_IDLE;
            end
		
            S_READ_ADDR : 
            begin
				r_disp_arvalid <= 1; 
				r_rd_pend <= 1; 
                rd_state <= S_READ_DATA;
            end
            S_READ_DATA : 
            begin
			//	Return when ~arvalid && ~rd_pend. 
			if((~r_disp_arvalid) && (~r_rd_pend))
                //if((axi_rvalid == 1'b1)&&(axi_rready == 1'b1)&&(rdata_cnt == C_BURST_LEN))
                    rd_state <= S_READ_IDLE;
                else
                    rd_state <= S_READ_DATA;
            end
            default : 
            begin
                rd_state <= S_READ_IDLE;
            end
        endcase
    end
end

always @(posedge axi_clk or posedge r_rfifo_rst)
begin
    if(r_rfifo_rst == 1'b1)
        araddr <= 0;
    else
    begin
        if((r_disp_arvalid == 1'b1)&&(axi_arready == 1'b1))
            araddr <= araddr + C_ADDR_INC;
        else
            araddr <= araddr;
    end
end

assign axi_araddr = r_prev_busy ? (C_BASE_ADDR + {r_tnr_prev_index, rc_w_ptr}) : (C_BASE_ADDR + {rc_rframe_index, araddr});
assign w_disp_want = rfifo_wr_rst_busy_dly[15] && (araddr < C_RD_END_ADDR) && (~rfifo_wfull);
assign w_disp_idle = (rd_state == S_READ_IDLE);


reg             [8:0]           rdata_cnt_dly;

always @(posedge axi_clk)
begin
    rdata_cnt_dly <= rdata_cnt;
end

always @(*)
begin
    if(rd_state == S_READ_DATA)
        begin
        if((axi_rvalid == 1'b1)&&(axi_rready == 1'b1))
            rdata_cnt = rdata_cnt_dly + 1'b1;
        else
            rdata_cnt = rdata_cnt_dly;
        end
    else
        rdata_cnt = 9'b0;
end

assign axi_rready = 1; 

always @(posedge axi_clk)
begin
    if(axi_reset == 1'b1)
        rfifo_wenb <= 1'b0;
    else
    begin
        if((axi_rvalid == 1'b1)&&(axi_rready == 1'b1)&&(~r_prev_busy))
            rfifo_wenb <= 1'b1;
        else
            rfifo_wenb <= 1'b0;
    end
end

always @(posedge axi_clk)
begin
    rfifo_wdata <= axi_rdata;
end

endmodule

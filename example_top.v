`timescale 1ns/1ps

//`include "ddr3_controller.vh"


module example_top 
(
	////////////////////////////////////////////////////////////////
	//	External Clock & Reset
	//input 			nrst, 			//	Button K2
	input 			clk_24m,			//	24MHz Crystal
	input 			clk_25m,			//	25MHz Crystal 
	
	
	////////////////////////////////////////////////////////////////
	//	System Clock
	output 			sys_pll_rstn_o, 		
	
	input 			clk_sys,			//	Sys PLL 96MHz 
	input 			clk_pixel,			//	Sys PLL 74.25MHz
	input 			clk_pixel_2x,		//	Sys PLL 148.5MHz
	input 			clk_pixel_10x,		//	Sys PLL 742.5MHz
	
	input 			sys_pll_lock,		//	Sys PLL Lock
	
	////////////////////////////////////////////////////////////////
	//	MIPI-DSI Clock & Reset
	output 			dsi_pll_rstn_o,
	
	input 			dsi_refclk_i,		//	48MHz Reference Clock (for DSI PLL)
	input 			dsi_byteclk_i,		//	DSI Byte Clock (1X)
	input 			dsi_serclk_i,		//	DSI Serial Clock (4X 45)
	input 			dsi_txcclk_i,		//	DSI Serial Clock (4X 135)
	
	input 			dsi_pll_lock,
	
	////////////////////////////////////////////////////////////////
	//	DDR Clock
	output 			ddr_pll_rstn_o, 
	
	input 			tdqss_clk,			
	input 			core_clk,			//	DDR PLL 200MHz
	input 			tac_clk,			
	input 			twd_clk,			
	
	input 			ddr_pll_lock,		//	DDR PLL Lock
	
	////////////////////////////////////////////////////////////////
	//	DDR PLL Phase Shift Interface
	output 	[2:0] 	shift,
	output 	[4:0] 	shift_sel,
	output 			shift_ena,
	
	
	
	////////////////////////////////////////////////////////////////
	//	LVDS Clock
	output 			lvds_pll_rstn_o, 
	
	input 			clk_lvds_1x, 
	input 			clk_lvds_7x, 
	input 			clk_27m, 			//	RGB 1X Clock (16MHz)
	input 			clk_54m, 			//	RGB 2X Clock (32MHz, for export control)
	
	input 			lvds_pll_lock, 
	
	
	
	////////////////////////////////////////////////////////////////
	//	DDR Interface Ports
	output 	[15:0] 	addr,
	output 	[2:0] 	ba,
	output 			we,
	output 			reset,
	output 			ras,
	output 			cas,
	output 			odt,
	output 			cke,
	output 			cs,
	
	//	DQ I/O
	input 	[15:0] 	i_dq_hi,
	input 	[15:0] 	i_dq_lo,
	
	output 	[15:0] 	o_dq_hi,
	output 	[15:0] 	o_dq_lo,
	output 	[15:0] 	o_dq_oe,
	
	//	DM O
	output 	[1:0] 	o_dm_hi,
	output 	[1:0] 	o_dm_lo,
	
	//	DQS I/O
	input 	[1:0] 	i_dqs_hi,
	input 	[1:0] 	i_dqs_lo,
	
	input 	[1:0] 	i_dqs_n_hi,
	input 	[1:0] 	i_dqs_n_lo,
	
	output 	[1:0] 	o_dqs_hi,
	output 	[1:0] 	o_dqs_lo,
	
	output 	[1:0] 	o_dqs_n_hi,
	output 	[1:0] 	o_dqs_n_lo,
	
	output 	[1:0] 	o_dqs_oe,
	output 	[1:0] 	o_dqs_n_oe,
	
	//	CK
	output 			clk_p_hi, 
	output 			clk_p_lo, 
	output 			clk_n_hi, 
	output 			clk_n_lo, 
	
	
	
	////////////////////////////////////////////////////////////////
	//	MIPI-CSI Ctl / I2C
	output 			csi_ctl0_o,
	output 			csi_ctl0_oe,
	input 			csi_ctl0_i,
	
	output 			csi_ctl1_o,
	output 			csi_ctl1_oe,
	input 			csi_ctl1_i,
	
	output 			csi_scl_o,
	output 			csi_scl_oe,
	input 			csi_scl_i,
	
	output 			csi_sda_o,
	output 			csi_sda_oe,
	input 			csi_sda_i,
	
	//	MIPI-CSI RXC 
	input 			csi_rxc_lp_p_i,
	input 			csi_rxc_lp_n_i,
	output 			csi_rxc_hs_en_o,
	output 			csi_rxc_hs_term_en_o,
	input 			csi_rxc_i,
	
	//	MIPI-CSI RXD0
	output 			csi_rxd0_rst_o,
	output 			csi_rxd0_hs_en_o,
	output 			csi_rxd0_hs_term_en_o,
	
	input 			csi_rxd0_lp_p_i,
	input 			csi_rxd0_lp_n_i,
	input 	[7:0] 	csi_rxd0_hs_i,
	
	//	MIPI-CSI RXD1
	output 			csi_rxd1_rst_o,
	output 			csi_rxd1_hs_en_o,
	output 			csi_rxd1_hs_term_en_o,
	
	input 			csi_rxd1_lp_n_i,
	input 			csi_rxd1_lp_p_i,
	input 	[7:0] 	csi_rxd1_hs_i,
	
	//	MIPI-CSI RXD2
	output 			csi_rxd2_rst_o,
	output 			csi_rxd2_hs_en_o,
	output 			csi_rxd2_hs_term_en_o,
	
	input 			csi_rxd2_lp_p_i,
	input 			csi_rxd2_lp_n_i,
	input 	[7:0] 	csi_rxd2_hs_i,
	
	//	MIPI-CSI RXD3
	output 			csi_rxd3_rst_o,
	output 			csi_rxd3_hs_en_o,
	output 			csi_rxd3_hs_term_en_o,
	
	input 			csi_rxd3_lp_p_i,
	input 			csi_rxd3_lp_n_i,
	input 	[7:0] 	csi_rxd3_hs_i,
	
	//output 			csi_rxd0_fifo_rd_o, 
	//input 			csi_rxd0_fifo_empty_i, 
	//output 			csi_rxd1_fifo_rd_o, 
	//input 			csi_rxd1_fifo_empty_i, 
	//output 			csi_rxd2_fifo_rd_o, 
	//input 			csi_rxd2_fifo_empty_i, 
	//output 			csi_rxd3_fifo_rd_o, 
	//input 			csi_rxd3_fifo_empty_i, 
	
	
	
	////////////////////////////////////////////////////////////////
	//	DSI PWM & Reset Control 
	output 			dsi_pwm_o,			//	MIPI-DSI LCD PWM
	output 			dsi_resetn_o,		//	MIPI-DSI LCD Reset
	
	//	MIPI-DSI TXC / TXD
	output 			dsi_txc_rst_o,
	output 			dsi_txc_lp_p_oe,
	output 			dsi_txc_lp_p_o,
	output 			dsi_txc_lp_n_oe,
	output 			dsi_txc_lp_n_o,
	output 			dsi_txc_hs_oe,
	output 	[7:0] 	dsi_txc_hs_o,
	
	output 			dsi_txd0_rst_o,
	output 			dsi_txd0_hs_oe,
	output 	[7:0] 	dsi_txd0_hs_o,
	output 			dsi_txd0_lp_p_oe,
	output 			dsi_txd0_lp_p_o,
	output 			dsi_txd0_lp_n_oe,
	output 			dsi_txd0_lp_n_o,
	
	output 			dsi_txd1_rst_o,
	output 			dsi_txd1_lp_p_oe,
	output 			dsi_txd1_lp_p_o,
	output 			dsi_txd1_lp_n_oe,
	output 			dsi_txd1_lp_n_o,
	output 			dsi_txd1_hs_oe,
	output 	[7:0] 	dsi_txd1_hs_o,
	
	output 			dsi_txd2_rst_o,
	output 			dsi_txd2_lp_p_oe,
	output 			dsi_txd2_lp_p_o,
	output 			dsi_txd2_lp_n_oe,
	output 			dsi_txd2_lp_n_o,
	output 			dsi_txd2_hs_oe,
	output 	[7:0] 	dsi_txd2_hs_o,
	
	output 			dsi_txd3_rst_o,
	output 			dsi_txd3_lp_p_oe,
	output 			dsi_txd3_lp_p_o,
	output 			dsi_txd3_lp_n_oe,
	output 			dsi_txd3_lp_n_o,
	output 			dsi_txd3_hs_oe,
	output 	[7:0] 	dsi_txd3_hs_o,
	
	input 			dsi_txd0_lp_p_i,
	input 			dsi_txd0_lp_n_i,
	input 			dsi_txd1_lp_p_i,
	input 			dsi_txd1_lp_n_i,
	input 			dsi_txd2_lp_p_i,
	input 			dsi_txd2_lp_n_i,
	input 			dsi_txd3_lp_p_i,
	input 			dsi_txd3_lp_n_i,
	
	
	////////////////////////////////////////////////////////////////
	//	UART Interface
	input 		 	uart_rx_i,			//	Support 460800-8-N-1. 
	output 		 	uart_tx_o, 
	
	
	output 	[5:0] 	led_o,			//	
	input [1:0] key_n, // K1/K2 active low; K3 is dedicated CRESET_N.
	
	
	////////////////////////////////////////////////////////////////
	//	CMOS Sensor
	output 			cmos_sclk,
	input 			cmos_sdat_IN,
	output 			cmos_sdat_OUT,
	output 			cmos_sdat_OE,
	
	//	CMOS Interface
	input 			cmos_pclk,
	input 			cmos_vsync,
	input 			cmos_href,
	input 	[7:0] 	cmos_data,
	
	output 			cmos_ctl1_o, 
	output 			cmos_ctl1_oe, 
	input 			cmos_ctl1_i,
	output 			cmos_ctl2_o,
	output 			cmos_ctl2_oe, 
	input 			cmos_ctl2_i, 
	output 			cmos_ctl3_o,
	output 			cmos_ctl3_oe, 
	input 			cmos_ctl3_i, 
	
	
	////////////////////////////////////////////////////////////////
	//	HDMI Interface
	output 			hdmi_txc_oe,
	output 			hdmi_txd0_oe,
	output 			hdmi_txd1_oe,
	output 			hdmi_txd2_oe,
	
	output 			hdmi_txc_rst_o,
	output 			hdmi_txd0_rst_o,
	output 			hdmi_txd1_rst_o,
	output 			hdmi_txd2_rst_o,
	
	output 	[9:0] 	hdmi_txc_o,
	output 	[9:0] 	hdmi_txd0_o,
	output 	[9:0] 	hdmi_txd1_o,
	output 	[9:0] 	hdmi_txd2_o,
	
	
	////////////////////////////////////////////////////////////////
	//	LVDS Interface
	output 			lvds_txc_oe,
	output 	[6:0] 	lvds_txc_o,
	output 			lvds_txc_rst_o,
	
	output 			lvds_txd0_oe,
	output 	[6:0] 	lvds_txd0_o,
	output 			lvds_txd0_rst_o,
	
	output 			lvds_txd1_oe,
	output 	[6:0] 	lvds_txd1_o,
	output 			lvds_txd1_rst_o,
	
	output 			lvds_txd2_oe,
	output 	[6:0] 	lvds_txd2_o,
	output 			lvds_txd2_rst_o,
	
	output 			lvds_txd3_oe,
	output 	[6:0] 	lvds_txd3_o,
	output 			lvds_txd3_rst_o,
	
	
	////////////////////////////////////////////////////////////////
	//	RGB LCD 5Inch 800x480
	output 			lcd_tp_sda_o,		//	TP SDA
	output 			lcd_tp_sda_oe,
	input 			lcd_tp_sda_i,
	
	output 			lcd_tp_scl_o,		//	TP SCL
	output 			lcd_tp_scl_oe,
	input 			lcd_tp_scl_i,
	
	output 			lcd_tp_int_o,		//	TP INT
	output 			lcd_tp_int_oe,
	input 			lcd_tp_int_i,
	
	output 			lcd_tp_rst_o,		//	TP RST
	
	output 			lcd_pwm_o,			//	Backlight
	output 			lcd_blen_o,
	
	//output 			lcd_pclk_o,			//	PCLK & SCK Mux
	output 			lcd_vs_o,			//	VS & SSN Mux. Fixed to 1. Use DE-Only mode. 
	output 			lcd_hs_o,			//	HS. Fixed to 1. Use DE-Only mode. 

	output 	[7:0] 	lcd_b7_0_o,			//	B7:B0. 
	output 	[7:0] 	lcd_g7_0_o,			//	G7:G0. Must output 8'hFF when access SPI. 
	output 	[7:0] 	lcd_r7_0_o,			//	R7:R0. 
	
	output 	[7:0] 	lcd_b7_0_oe,		//	B7:B0. 
	output 	[7:0] 	lcd_g7_0_oe,		//	G7:G0. Must output 8'hFF when access SPI. 
	output 	[7:0] 	lcd_r7_0_oe,		//	R7:R0. 

	input 	[7:0] 	lcd_b7_0_i,			//	B7:B0. 
	input 	[7:0] 	lcd_g7_0_i,			//	G7:G0. Must output 8'hFF when access SPI. 
	input 	[7:0] 	lcd_r7_0_i,			//	R7:R0. 
	
	//	SPI Pins
	output 			spi_sck_o, 
	output 			spi_ssn_o 			
);
	
	wire 			csi_rxd0_fifo_rd_o; 
	wire 			csi_rxd0_fifo_empty_i = 0;  
	wire 			csi_rxd1_fifo_rd_o;  
	wire 			csi_rxd1_fifo_empty_i = 0;  
	wire 			csi_rxd2_fifo_rd_o;  
	wire 			csi_rxd2_fifo_empty_i = 0;  
	wire 			csi_rxd3_fifo_rd_o;  
	wire 			csi_rxd3_fifo_empty_i = 0;  
	
	
	parameter 	SIM_DATA 	= 0; 
	
	//	Hardware Configuration
	assign clk_p_hi = 1'b0;	//	DDR3 Clock requires 180 degree shifted. 
	assign clk_p_lo = 1'b1;
	assign clk_n_hi = 1'b1;
	assign clk_n_lo = 1'b0; 
	
	assign cmos_ctl1_o = 0; 
	assign cmos_ctl1_oe = 1; 
	assign cmos_ctl2_o = 0; 
	assign cmos_ctl2_oe = 1; 
	assign cmos_ctl3_o = 0; 
	assign cmos_ctl3_oe = 1; 
	
	//	System Clock Tree Control
	assign sys_pll_rstn_o = 1'b1; 	//	nrst; 	//	Reset whole system when nrst (K2) is pressed. 
	
	assign dsi_pll_rstn_o = sys_pll_lock; 
	assign ddr_pll_rstn_o = sys_pll_lock; 
	assign lvds_pll_rstn_o = sys_pll_lock; 
	
	wire 			w_pll_lock = sys_pll_lock && dsi_pll_lock && ddr_pll_lock && lvds_pll_lock; 
	
	//	Synchronize System Resets. 
	reg 			rstn_sys = 0, rstn_pixel = 0; 
	wire 			rst_sys = ~rstn_sys, rst_pixel = ~rstn_pixel; 
	
	reg 			rstn_dsi_refclk = 0, rstn_dsi_byteclk = 0; 
	wire 			rst_dsi_refclk = ~rstn_dsi_refclk, rst_dsi_byteclk = ~rstn_dsi_byteclk; 
	
	reg 			rstn_lvds_1x = 0; 
	wire 			rst_lvds_1x = ~rstn_lvds_1x; 
	
	reg 			rstn_27m = 0, rstn_54m = 0; 
	wire 			rst_27m = ~rstn_27m, rst_54m = ~rstn_54m; 
	
	//	Clock Gen
	always @(posedge clk_27m or negedge w_pll_lock) begin if(~w_pll_lock) rstn_27m <= 0; else rstn_27m <= 1; end
	always @(posedge clk_54m or negedge w_pll_lock) begin if(~w_pll_lock) rstn_54m <= 0; else rstn_54m <= 1; end
	always @(posedge clk_sys or negedge w_pll_lock) begin if(~w_pll_lock) rstn_sys <= 0; else rstn_sys <= 1; end
	always @(posedge clk_pixel or negedge w_pll_lock) begin if(~w_pll_lock) rstn_pixel <= 0; else rstn_pixel <= 1; end
	always @(posedge dsi_refclk_i or negedge w_pll_lock) begin if(~w_pll_lock) rstn_dsi_refclk <= 0; else rstn_dsi_refclk <= 1; end
	always @(posedge dsi_byteclk_i or negedge w_pll_lock) begin if(~w_pll_lock) rstn_dsi_byteclk <= 0; else rstn_dsi_byteclk <= 1; end
	always @(posedge clk_lvds_1x or negedge w_pll_lock) begin if(~w_pll_lock) rstn_lvds_1x <= 0; else rstn_lvds_1x <= 1; end
	
	
	localparam 	CLOCK_MAIN 	= 96000000; 	//	System clock using 96MHz. 
	
	
	
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	//	Flash Burner Control
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	wire 			w_ustick, w_mstick; 
	
	wire  [7:0] 	w_dev_index_o;  
	wire  [7:0] 	w_dev_cmd_o;  
	wire  [31:0] 	w_dev_wdata_o;  
	wire  		w_dev_wvalid_o;  
	wire  		w_dev_rvalid_o;  
	wire 	[31:0] 	w_dev_rdata_i;  
	
	wire 			w_spi_ssn_o, w_spi_sck_o; 
	wire 	[3:0] 	w_spi_data_o, w_spi_data_oe; 
	wire 	[3:0] 	w_spi_data_i; 
	
	//	Flash Control
	reg 			r_flash_en = 0; 		//	0x00:0x00 Enable Flash
	
	always @(posedge clk_sys) begin
		r_flash_en <= (w_dev_wvalid_o && (w_dev_index_o == 8'h00) && (w_dev_cmd_o == 8'h00)) ? w_dev_wdata_o : r_flash_en; 
	end
	
	
	
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	//	LCD Data Mux
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	
	wire 	[7:0] 	w_lcd_b_o, w_lcd_g_o, w_lcd_r_o; 
	
	assign lcd_b7_0_o = r_flash_en ? {4'b0, w_spi_data_o[3:2], 2'b0} : w_lcd_b_o; 
	assign lcd_g7_0_o = r_flash_en ? {6'h0, w_spi_data_o[1:0]} : w_lcd_g_o; 
	assign lcd_r7_0_o = r_flash_en ? {8'h00} : w_lcd_r_o; 
	
	assign lcd_b7_0_oe = r_flash_en ? {4'b0, w_spi_data_oe[3:2], 2'b0} : 8'hFF; 
	assign lcd_g7_0_oe = r_flash_en ? {6'h0, w_spi_data_oe[1:0]} : 8'hFF; 
	assign lcd_r7_0_oe = r_flash_en ? {8'h00} : 8'hFF; 
	
	assign spi_sck_o = w_spi_sck_o; 
	assign spi_ssn_o = w_spi_ssn_o; 
	assign w_spi_data_i = {lcd_b7_0_i[3:2], lcd_g7_0_i[1:0]}; 
	
	
	
	
	
	
	
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	//	DDR3 Controller
	////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////////
	wire			w_ddr3_ui_clk = clk_sys;
	wire			w_ddr3_ui_rst = rst_sys;
	wire			w_ddr3_ui_areset = rst_sys;
	wire			w_ddr3_ui_aresetn = rstn_sys;
	

	//	General AXI Interface 
	wire	[3:0] 	w_ddr3_awid;
	wire	[31:0]	w_ddr3_awaddr;
	wire	[7:0]		w_ddr3_awlen;
	wire			w_ddr3_awvalid;
	wire			w_ddr3_awready;
	
	wire 	[3:0]  	w_ddr3_wid;
	wire 	[127:0] 	w_ddr3_wdata;
	wire 	[15:0]	w_ddr3_wstrb;
	wire			w_ddr3_wlast;
	wire			w_ddr3_wvalid;
	wire			w_ddr3_wready;
	
	wire 	[3:0] 	w_ddr3_bid;
	wire 	[1:0] 	w_ddr3_bresp;
	wire			w_ddr3_bvalid;
	wire			w_ddr3_bready;
	
	wire	[3:0] 	w_ddr3_arid;
	wire	[31:0]	w_ddr3_araddr;
	wire	[7:0]		w_ddr3_arlen;
	wire			w_ddr3_arvalid;
	wire			w_ddr3_arready;
	
	wire 	[3:0] 	w_ddr3_rid;
	wire 	[127:0] 	w_ddr3_rdata;
	wire			w_ddr3_rlast;
	wire			w_ddr3_rvalid;
	wire			w_ddr3_rready;
	wire 	[1:0] 	w_ddr3_rresp;
	
	
	//	AXI Interface Request
	wire 	[3:0] 	w_ddr3_aid;
	wire 	[31:0] 	w_ddr3_aaddr;
	wire 	[7:0]  	w_ddr3_alen;
	wire 	[2:0]  	w_ddr3_asize;
	wire 	[1:0]  	w_ddr3_aburst;
	wire 	[1:0]  	w_ddr3_alock;
	wire			w_ddr3_avalid;
	wire			w_ddr3_aready;
	wire			w_ddr3_atype;
	
	wire 			w_ddr3_cal_done, w_ddr3_cal_pass; 
	
	//	Do not issue DDR read / write when ~cal_done. 
	reg 			r_ddr_unlock = 0; 
	always @(posedge w_ddr3_ui_clk or negedge w_ddr3_ui_aresetn) begin
		if(~w_ddr3_ui_aresetn)
			r_ddr_unlock <= 0; 
		else
			r_ddr_unlock <= w_ddr3_cal_done; 
	end
	
	DdrCtrl ddr3_ctl_axi (	
		.core_clk		(core_clk),
		.tac_clk		(tac_clk),
		.twd_clk		(twd_clk),	
		.tdqss_clk		(tdqss_clk),
		
		.reset		(reset),
		.cs			(cs),
		.ras			(ras),
		.cas			(cas),
		.we			(we),
		.cke			(cke),    
		.addr			(addr),
		.ba			(ba),
		.odt			(odt),
		
		.o_dm_hi		(o_dm_hi),
		.o_dm_lo		(o_dm_lo),
		
		.i_dq_hi		(i_dq_hi),
		.i_dq_lo		(i_dq_lo),
		.o_dq_hi		(o_dq_hi),
		.o_dq_lo		(o_dq_lo),
		.o_dq_oe		(o_dq_oe),
		
		.i_dqs_hi		(i_dqs_hi),
		.i_dqs_lo		(i_dqs_lo),
		.i_dqs_n_hi		(i_dqs_n_hi),
		.i_dqs_n_lo		(i_dqs_n_lo),
		.o_dqs_hi		(o_dqs_hi),
		.o_dqs_lo		(o_dqs_lo),
		.o_dqs_n_hi		(o_dqs_n_hi),
		.o_dqs_n_lo		(o_dqs_n_lo),
		.o_dqs_oe		(o_dqs_oe),
		.o_dqs_n_oe		(o_dqs_n_oe),
		
		.clk			(w_ddr3_ui_clk),
		.reset_n		(w_ddr3_ui_aresetn),
		
		.axi_avalid		(w_ddr3_avalid),	//	Enable command only when unlocked. 
		.axi_aready		(w_ddr3_aready),
		.axi_aaddr		(w_ddr3_aaddr),
		.axi_aid		(w_ddr3_aid),
		.axi_alen		(w_ddr3_alen),
		.axi_asize		(w_ddr3_asize),
		.axi_aburst		(w_ddr3_aburst),
		.axi_alock		(w_ddr3_alock),
		.axi_atype		(w_ddr3_atype),
		
		.axi_wid		(w_ddr3_wid),
		.axi_wvalid		(w_ddr3_wvalid),
		.axi_wready		(w_ddr3_wready),
		.axi_wdata		(w_ddr3_wdata),
		.axi_wstrb		(w_ddr3_wstrb),
		.axi_wlast		(w_ddr3_wlast),
		
		.axi_bvalid		(w_ddr3_bvalid),
		.axi_bready		(w_ddr3_bready),
		.axi_bid		(w_ddr3_bid),
		.axi_bresp		(w_ddr3_bresp),
		
		.axi_rvalid		(w_ddr3_rvalid),
		.axi_rready		(w_ddr3_rready),
		.axi_rdata		(w_ddr3_rdata),
		.axi_rid		(w_ddr3_rid),
		.axi_rresp		(w_ddr3_rresp),
		.axi_rlast		(w_ddr3_rlast),
		
		.shift		(shift),
		.shift_sel		(),
		.shift_ena		(shift_ena),
		
		.cal_ena		(1'b1),
		.cal_done		(w_ddr3_cal_done),
		.cal_pass		(w_ddr3_cal_pass)
	);
	
	assign w_ddr3_bready = 1'b1; 
	assign shift_sel = 5'b00100; 		//	ddr_tac_clk always use PLLOUT[2]. 
	
	
	AXI4_AWARMux #(.AID_LEN(4), .AADDR_LEN(32)) axi4_awar_mux (
		.aclk_i			(w_ddr3_ui_clk), 
		.arst_i			(w_ddr3_ui_rst), 
		
		.awid_i			(w_ddr3_awid),
		.awaddr_i			(w_ddr3_awaddr),
		.awlen_i			(w_ddr3_awlen),
		.awvalid_i			(w_ddr3_awvalid && r_ddr_unlock),
		.awready_o			(w_ddr3_awready),
		
		.arid_i			(w_ddr3_arid),
		.araddr_i			(w_ddr3_araddr),
		.arlen_i			(w_ddr3_arlen),
		.arvalid_i			(w_ddr3_arvalid && r_ddr_unlock),
		.arready_o			(w_ddr3_arready),
		
		.aid_o			(w_ddr3_aid),
		.aaddr_o			(w_ddr3_aaddr),
		.alen_o			(w_ddr3_alen),
		.atype_o			(w_ddr3_atype),
		.avalid_o			(w_ddr3_avalid),
		.aready_i			(w_ddr3_aready)
	);
	
	assign w_ddr3_asize = 4; 		//	Fixed 128 bits (16 bytes, size = 4)
	assign w_ddr3_aburst = 1; 
	assign w_ddr3_alock = 0; 
	
	//assign led_o[1:0] = {w_ddr3_cal_pass, w_ddr3_cal_done}; 
	
	
	
	
	
	
	
	////////////////////////////////////////////////////////////////
	//	I2C Config (OV5640)
	
	//  i2c timing controller module of 16Bit
	wire            [ 7:0]          ov5640_i2c_config_index;
	wire            [23:0]          ov5640_i2c_config_data;
	wire            [ 7:0]          ov5640_i2c_config_size;
	wire                            ov5640_i2c_config_done;
	// Lens focus from the keys (pixel clock): resynchronize, then rewrite
	// the two VCM registers at the end of the OV5640 table.
	wire [9:0] focus_code_pixel;
	(* async_reg = "true" *) reg [9:0] focus_meta = 0, focus_sync = 0;
	reg [9:0] focus_applied = 10'd256;
	reg focus_rewrite_pending = 0, focus_config_done_d = 0;
	// Stays high after the first full configuration, so focus rewrites do
	// not look like a camera restart to the frame monitor and FPS counter.
	reg ov5640_config_ready = 0;
	always @(posedge clk_sys) begin
		focus_meta <= focus_code_pixel;
		focus_sync <= focus_meta;
		focus_config_done_d <= ov5640_i2c_config_done;
		if (!rstn_sys) begin
			focus_applied <= 10'd256;
			focus_rewrite_pending <= 1'b0;
			ov5640_config_ready <= 1'b0;
		end else begin
			if (ov5640_i2c_config_done) ov5640_config_ready <= 1'b1;
			if (focus_sync == focus_meta && focus_sync != focus_applied) begin
				focus_applied <= focus_sync;
				focus_rewrite_pending <= 1'b1;
			end else if (focus_rewrite_pending && focus_config_done_d && !ov5640_i2c_config_done)
				focus_rewrite_pending <= 1'b0;
		end
	end
	wire            [15:0]          ov5640_i2c_rdata;                              //  i2c register data

	i2c_timing_ctrl_16bit
	#(
	    .CLK_FREQ           (CLOCK_MAIN),                              //  100 MHz
	    .I2C_FREQ           (50_000    )                               //  10 KHz(<= 400KHz)
	) 
	u_i2c_timing_ctrl_16bit 
	(
	    //global clock
	    .clk                (clk_sys                 ),                          //  96MHz
	    .rst_n              (rstn_sys                ),                          //  system reset

	    //i2c interface
	    .i2c_sclk           (cmos_sclk                  ),                  //  i2c clock
		.i2c_sdat_OUT 	(cmos_sdat_OUT), 
		.i2c_sdat_OE	(cmos_sdat_OE), 
		.i2c_sdat_IN 	(cmos_sdat_IN), 
		
	    //i2c config data
	    .i2c_config_index   (ov5640_i2c_config_index           ),                  //  i2c config reg index, read 2 reg and write xx reg
	    .i2c_config_data    ({8'h78, ov5640_i2c_config_data}   ),                  //  i2c config data
	    .i2c_config_size    (ov5640_i2c_config_size            ),                  //  i2c config data counte
	    .i2c_config_done    (ov5640_i2c_config_done            ),
	    .i2c_rewrite_req    (focus_rewrite_pending             ),
	    .i2c_rewrite_index  (8'd253                            ),                  //  i2c config timing complete
	    .i2c_rdata          (ov5640_i2c_rdata                  )                   //  i2c register data while read i2c slave
	);
	
	//----------------------------------------------------------------------
	//  I2C Configure Data of OV5640
	// Sensor bars traverse the DVP capture, FIFO, DDR and HDMI path.
	localparam SENSOR_TEST_PATTERN = 1'b0;
	// The sensor reference clock is 16 MHz, so the reference PLL settings
	// give 20 fps (SCLK 28 MHz, PCLK 56 MHz). CAMERA_30FPS raises the PLL
	// multiplier for 30 fps (PCLK 84 MHz). The display path remains 720p60.
	localparam [7:0] CAMERA_SYS_DIV = 8'h21;
	localparam CAMERA_30FPS = 1'b1;
	// With CAMERA_30FPS, 1 shortens the sensor line (HTS 1892 -> 1600 SCLK)
	// for about 35.5 fps at the same 84 MHz PCLK. Experimental.
	localparam CAMERA_SHORT_LINE = 1'b0;
	localparam [15:0] CAMERA_HTS = (CAMERA_30FPS && CAMERA_SHORT_LINE) ? 16'd1600 : 16'd1892;
	// 1 sets the exposure band step to 10 ms for 50 Hz lighting; 0 keeps
	// the original register table.
	localparam CAMERA_BAND_50HZ_FIX = 1'b1;
	// 1: sensor sharpening off, stronger sensor denoise.
	localparam CAMERA_ISP_LOW_NOISE = 1'b0;
	I2C_OV5640_1280720_Config #(.SENSOR_TEST_PATTERN(SENSOR_TEST_PATTERN), .CAMERA_SYS_DIV(CAMERA_SYS_DIV), .BAND_50HZ_FIX(CAMERA_BAND_50HZ_FIX),
		.PLL_MULT(CAMERA_30FPS ? 8'h9e : 8'h69),
		// Rows in 10 ms and whole 10 ms bands within one frame (740 rows).
		.B50_STEP(!CAMERA_30FPS ? 10'd148 : CAMERA_SHORT_LINE ? 10'd263 : 10'd222),
		.B50_MAX_BANDS(!CAMERA_30FPS ? 8'd4 : CAMERA_SHORT_LINE ? 8'd2 : 8'd3),
		.HTS(CAMERA_HTS), .ISP_LOW_NOISE(CAMERA_ISP_LOW_NOISE)) u_I2C_OV5640_1280720_Config
	(
	    .LUT_INDEX  (ov5640_i2c_config_index   ),
	    .FOCUS_CODE (focus_applied             ),
	    .LUT_DATA   (ov5640_i2c_config_data    ),
	    .LUT_SIZE   (ov5640_i2c_config_size    )
	); 
	
	
	//	CMOS Interface
	//input 			cmos_pclk,
	//input 			cmos_vsync,
	//input 			cmos_href,
	//input 	[7:0] 	cmos_data,
	
	wire 			w_cmos_pclk = cmos_pclk;
	// Ignore sensor reset and interim formats during the I2C configuration.
	(* async_reg = "true" *) reg [1:0] camera_config_sync = 0;
	always @(posedge w_cmos_pclk) begin
		if (!rstn_sys) camera_config_sync <= 0;
		else camera_config_sync <= {camera_config_sync[0], ov5640_config_ready};
	end
	wire dvp_line_error, dvp_frame_error, dvp_checked_frame;
	dvp_frame_monitor u_dvp_frame_monitor (
		.clk(w_cmos_pclk), .rst_n(rstn_sys && camera_config_sync[1]), .vsync(cmos_vsync), .href(cmos_href),
		.line_error(dvp_line_error), .frame_error(dvp_frame_error), .checked_frame(dvp_checked_frame)
	);
	(* async_reg = "true" *) reg [2:0] dvp_status_meta = 0, dvp_status_pixel = 0;
	always @(posedge clk_pixel) begin
		dvp_status_meta <= {dvp_checked_frame, dvp_frame_error, dvp_line_error};
		dvp_status_pixel <= dvp_status_meta;
	end
	
	
	
	//	Output LED
	reg 	[3:0]		r_cmos_fv_o = 0; 
	reg 	[1:0] 	r_cmos_rx_vsync0_in = 0; 
	always @(posedge w_cmos_pclk) begin
		r_cmos_rx_vsync0_in <= {r_cmos_rx_vsync0_in, cmos_vsync}; 
		r_cmos_fv_o <= r_cmos_fv_o + ((r_cmos_rx_vsync0_in == 2'b01) ? 1 : 0); 
	end
	assign led_o[5] = r_cmos_fv_o[3]; 
	
	
	
	
	
	
	
	
	////////////////////////////////////////////////////////////////
	//	System Control. Can be removed for public. 
	
	localparam 	CLK_FREQ 	= 96_000_000; 	//	clk_sys is 96MHz. 
	localparam 	BAUD_RATE 	= 460_800; 		//	Use 460800-8-N-1. 
	
	
	//	SFR I/O Interface
	wire 	[7:0] 	w_sfr_addr_o; 	//	SFR Address (0xFF00 ~ 0xFFFF). 00:Power; 40~5F:Stream0; 60~7F:Stream1. 
	wire 	[7:0] 	w_sfr_wdata_o; 	//	SFR Write Data. 
	wire 			w_sfr_we_o; 		//	SFR WE. 
	reg 	[7:0] 	w_sfr_rdata_i; 	//	Must be valid after sfr_rd_o. 
	wire 			w_sfr_rd_o; 		//	SFR RD. 
	
	
	//	System Control Registers
	reg 			r_dsi_tx_rstn = 0; 	//	DSI TX Reset
	reg 	[7:0] 	r_dsi_pwm = 64; 		//	[6:0]PWM, [7]Pol
	reg 			r_dsi_resetn_o = 0; 	//	DSI Panel Reset
	reg 			r_dsi_data_rstn = 0; 	//	DSI TX Reset
	
	reg 	[3:0] 	r_dsi_lp_p_ovr = 0; 	
	reg 	[3:0] 	r_dsi_lp_n_ovr = 0; 	
	
	
	
	//	AXI-Lite Interface Bridge
	localparam 	CSI_AXILITE_ID 	= 0; 				//	Select DSI_TX when r_axi_sel = DSI_AXILITE_ID. 
	localparam 	DSI_AXILITE_ID 	= 1; 				//	Select DSI_TX when r_axi_sel = DSI_AXILITE_ID. 
	
	reg 	[7:0] 	r_axi_addr = 8'h18; 		//	0xE0 (RW)
	reg 	[31:0] 	r_axi_wdata = 32'h0000000A; 	//	0xE1~0xE4 (RW)
	wire 	[31:0] 	w_axi_rdata; 			//	0xE5~0xE8 (RO)
	reg 	[0:0] 	r_axi_sel = 1; 			//	0xE9[7:2] (RW)
	reg 			r_axi_r1w0 = 0; 			//	0xE9[1] (RW)
	reg 			r_axi_req = 0; 			//	0xE9[0] (WO, Single Cycle)
	reg 			r_axi_req_o = 0; 			//	Delayed of r_axi_req. 
	
	
	//	Buffered AXI Read Data
	reg 	[31:0] 	r_axi_rdata = 0; 		//	Use state machine
	reg 			r_axi_idle = 0; 		//	AXI Idle 
	
	reg 	[3:0] 	rs_axilite = 0; 		//	AXI Access
	wire 	[3:0] 	ws_axilite_idle = 0; 		
	wire 	[3:0] 	ws_axilite_write = 1; 
	wire 	[3:0] 	ws_axilite_read = 2; 
	wire 	[3:0] 	ws_axilite_endread = 3; 
	
	reg 			r_axi_awvalid = 0, r_axi_wvalid = 0, r_axi_arvalid = 0; 
	wire 			w_axi_awready, w_axi_wready, w_axi_arready, w_axi_rvalid; 
	
	
	reg 	[3:0] 	rc_axi_init = 0; 

	always @(posedge clk_sys or posedge rst_sys) begin
		if(rst_sys) begin
			r_dsi_tx_rstn <= 0; 
			r_dsi_pwm <= 64; 
			r_axi_req <= 0; 
			r_dsi_resetn_o <= 0; 
			r_dsi_data_rstn <= 0; 
			
			rs_axilite <= 0; 
			r_axi_awvalid <= 0; 
			r_axi_wvalid <= 0;
			r_axi_arvalid <= 0; 
			
			r_dsi_lp_p_ovr <= 0; 
			r_dsi_lp_n_ovr <= 0; 
			
			rc_axi_init <= 0; 
			r_axi_idle <= 0; 
			
		end else begin
			r_dsi_tx_rstn <= 1; 
			r_dsi_resetn_o <= 1; 
			r_dsi_data_rstn <= 1; 
			
		end
	end
	
	assign dsi_resetn_o = r_dsi_resetn_o; 
	
	assign csi_ctl0_oe = 0; 
	assign csi_ctl1_oe = 0; 
	
	
	PWMLite dsi_pwm (		//	#(.ENABLE_TICK(0), .PWM_BITS(7)) 
		.clk_i			(clk_sys),
		.rst_i			(rst_sys),
		.pwm_i			(r_dsi_pwm[6:0]),
		.pol_i			(r_dsi_pwm[7]), 
		.pwm_o			(dsi_pwm_o)
	);






	////////////////////////////////////////////////////////////////
	//	MIPI CSI RX
	
	//	The CSI RXC shall not be inverted. Data can be inverted with swapped LP data and flipped HS data. 
	localparam 	CSI_RXD_INV 	= 4'b1111; 
	localparam 	CSI_DATA_WIDTH 	= 8; 			
	localparam 	CSI_STRB_WIDTH 	= CSI_DATA_WIDTH / 8; 

	
	////////////////////////////////////////////////////////////////
	//	MIPI-CSI Crop
	
	wire			XYCrop_frame_vsync; 
	wire			XYCrop_frame_href;
	wire			XYCrop_frame_de;
	wire	[63:0]	XYCrop_frame_Gray;

	Sensor_Image_XYCrop
	#(
		//	RGB width doubled. 
		.IMAGE_HSIZE_SOURCE (1280 * 2 / CSI_STRB_WIDTH),
		.IMAGE_VSIZE_SOURCE (720	 ),
		.IMAGE_HSIZE_TARGET (1280 * 2 / CSI_STRB_WIDTH),
		.IMAGE_YSIZE_TARGET (720 	 ),
		.PIXEL_DATA_WIDTH	(CSI_DATA_WIDTH) 		//	32		 )
	)
	u_Sensor_Image_XYCrop
	(
		//	globel clock
		.clk			(w_cmos_pclk),			//	image pixel clock
		.rst_n		(rstn_sys),			//	system reset
		
		//CMOS Sensor interface
		.image_in_vsync (cmos_vsync		),			//H : Data Valid; L : Frame Sync(Set it by register)
		.image_in_href	(cmos_href		),			//H : Data vaild, L : Line Sync
		.image_in_de	(cmos_href		), 			//H : Data Enable, L : Line Sync
		.image_in_data	(cmos_data),			//8 bits cmos data input
		
		.image_out_vsync(XYCrop_frame_vsync ),			//H : Data Valid; L : Frame Sync(Set it by register)
		.image_out_href (XYCrop_frame_href	),			//H : Data vaild, L : Line Sync
		.image_out_de	(XYCrop_frame_de	), 			//H : Data Enable, L : Line Sync
		.image_out_data (XYCrop_frame_Gray	)			//8 bits cmos data input	
	);

	reg			r_XYCrop_frame_vsync = 0; 
	reg			r_XYCrop_frame_href = 0;
	reg			r_XYCrop_frame_de = 0;
	reg	[63:0]	r_XYCrop_frame_Gray = 0;
	
	always @(posedge w_cmos_pclk) begin
		r_XYCrop_frame_vsync <= XYCrop_frame_vsync; 
		r_XYCrop_frame_href <= XYCrop_frame_href;
		r_XYCrop_frame_de <= XYCrop_frame_de;
		r_XYCrop_frame_Gray <= XYCrop_frame_Gray;
	end
	
	//	Data Write Assignment
	wire			cmos_frame_vsync = r_XYCrop_frame_vsync;                     //  cmos frame data vsync valid signal
	// Frame freeze (K2 long hold): stop writing new camera frames into DDR.
	// The switch happens on the VSYNC falling edge that axi4_ctrl treats as
	// end of frame, so the reader keeps showing the last complete frame.
	wire frame_freeze;
	(* async_reg = "true" *) reg [1:0] freeze_sync = 0;
	reg freeze_vsync_d = 0, freeze_active = 0;
	always @(posedge w_cmos_pclk) begin
		freeze_sync <= {freeze_sync[0], frame_freeze};
		freeze_vsync_d <= cmos_frame_vsync;
		if (freeze_vsync_d && !cmos_frame_vsync)
			freeze_active <= freeze_sync[1];
	end
	wire write_frame_vsync = cmos_frame_vsync && !freeze_active;
	wire			cmos_frame_href = r_XYCrop_frame_href && r_XYCrop_frame_de;	 //  cmos frame data href vaild  signal
	// Set to 1 to test byte packing and DDR with known pixels; 0 for camera.
	localparam DDR_VIDEO_DIAGNOSTIC = 1'b0;
	wire [7:0] diagnostic_byte;
	ddr_video_diagnostic u_ddr_video_diagnostic (
		.clk(w_cmos_pclk), .rst_n(rstn_sys),
		.vsync(cmos_frame_vsync), .de(cmos_frame_href), .data(diagnostic_byte)
	);
	wire	[63:0]	cmos_frame_Gray = DDR_VIDEO_DIAGNOSTIC ? {56'b0, diagnostic_byte} : r_XYCrop_frame_Gray;
	wire 			cmos_vsync_end;

	












	////////////////////////////////////////////////////////////////
	//	DDR R/W Control
	

	wire                            lcd_de;
	wire                            lcd_hs;      
	wire                            lcd_vs;
	wire 					  lcd_request; 
	wire            [7:0]           lcd_red, lcd_red2;
	wire            [7:0]           lcd_green, lcd_green2;
	wire            [7:0]           lcd_blue, lcd_blue2;
	wire            [15:0]          lcd_data;
	wire [11:0] diagnostic_lcd_x, diagnostic_lcd_y;


	assign w_ddr3_awid = 0; 
	assign w_ddr3_wid = 0; 
	
	wire 			w_wframe_vsync; 
	wire 	[7:0] 	w_axi_tp; 
	wire 	[7:0] 	w_frame_latency_ms; 
	wire 			w_frame_latency_valid; 
	wire 	[6:0] 	w_tnr_change_pct; 
	wire 			w_tnr_change_valid; 
	
	// 1: temporal noise reduction on the stored camera frame (see
	// axi4_ctrl C_TNR). K1+K2 long hold steps normal -> strong -> off.
	localparam TNR_ENABLE = 1'b1;
	wire [1:0] tnr_key_mode;
	wire [1:0] tnr_mode = TNR_ENABLE ? tnr_key_mode : 2'd0;
	//	Write in 8 bits. Read in 16 bits. 
	axi4_ctrl #(.C_RD_END_ADDR(1280 * 2 * 720), .C_W_WIDTH(CSI_DATA_WIDTH), .C_R_WIDTH(16), .C_ID_LEN(4),
		.C_TNR(TNR_ENABLE)) u_axi4_ctrl (

		.axi_clk        (w_ddr3_ui_clk            ),
		.axi_reset      (w_ddr3_ui_rst            ),

		.axi_awaddr     (w_ddr3_awaddr       ),
		.axi_awlen      (w_ddr3_awlen        ),
		.axi_awvalid    (w_ddr3_awvalid      ),
		.axi_awready    (w_ddr3_awready      ),

		.axi_wdata      (w_ddr3_wdata        ),
		.axi_wstrb      (w_ddr3_wstrb        ),
		.axi_wlast      (w_ddr3_wlast        ),
		.axi_wvalid     (w_ddr3_wvalid       ),
		.axi_wready     (w_ddr3_wready       ),

		.axi_bid        (0          ),
		.axi_bresp      (0        ),
		.axi_bvalid     (1       ),

		.axi_arid       (w_ddr3_arid         ),
		.axi_araddr     (w_ddr3_araddr       ),
		.axi_arlen      (w_ddr3_arlen        ),
		.axi_arvalid    (w_ddr3_arvalid      ),
		.axi_arready    (w_ddr3_arready      ),

		.axi_rid        (w_ddr3_rid          ),
		.axi_rdata      (w_ddr3_rdata        ),
		.axi_rresp      (0        ),
		.axi_rlast      (w_ddr3_rlast        ),
		.axi_rvalid     (w_ddr3_rvalid       ),
		.axi_rready     (w_ddr3_rready       ),

		.wframe_pclk    (w_cmos_pclk          ),
		.wframe_vsync   (write_frame_vsync), //w_wframe_vsync   ),		//	Writter VSync. Flush on rising edge. Connect to EOF. 
		.wframe_data_en (cmos_frame_href && !freeze_active),
		.wframe_data    (cmos_frame_Gray),
		
		.rframe_pclk    (clk_pixel            ),
		.rframe_vsync   (~lcd_vs             ),		//	Reader VSync. Flush on rising edge. Connect to ~EOF. 
		.rframe_data_en (lcd_request             ),
		.rframe_data    (lcd_data           ),
		
		.tp_o 		(w_axi_tp),
		.frame_latency_ms (w_frame_latency_ms),
		.frame_latency_valid (w_frame_latency_valid),
		.tnr_mode (tnr_mode),
		.tnr_change_pct (w_tnr_change_pct),
		.tnr_change_valid (w_tnr_change_valid)
	);
	assign led_o[3:0] = w_axi_tp; 
	assign led_o[4] = frame_freeze;
	
	
	
	
	////////////////////////////////////////////////////////////////
	//  LCD Timing Driver
	wire 	[15:0] 	w_lcd_data_swap = {lcd_data[7:0], lcd_data[15:8]}; 
	wire 	[7:0] 	lcd_data_r = {lcd_data[15:11], 3'b0}; 
	wire 	[7:0] 	lcd_data_g = {lcd_data[10:5], 2'b0}; 
	wire 	[7:0] 	lcd_data_b = {lcd_data[4:0], 3'b0}; 
	
	lcd_driver u_lcd_driver
	(
	    //  global clock
	    .clk        (clk_pixel   ),
	    .rst_n      (rstn_pixel), 
	    
	    //  lcd interface
	    .lcd_dclk   (               ),
	    .lcd_blank  (               ),
	    .lcd_sync   (               ),
	    .lcd_request(lcd_request    ), 	//	Request data 1 cycle ahead. 
	    .lcd_hs     (lcd_hs         ),
	    .lcd_vs     (lcd_vs         ),
	    .lcd_en     (lcd_de         ),
	    .lcd_xpos   (diagnostic_lcd_x),
	    .lcd_ypos   (diagnostic_lcd_y),
	    .lcd_rgb    ({lcd_red2,lcd_green2,lcd_blue2, lcd_red,lcd_green,lcd_blue}),
	    
	    //  user interface
	    .lcd_data   ({lcd_data_r, lcd_data_g, lcd_data_b}  )
	);
	
	
	
	////////////////////////////////////////////////////////////////
	//	HDMI Interface. 
	
	//	HDMI requires specific timing, thus is not compatible with LCD & LVDS & DSI. Must implement standalone. 
	// Set to 1 for an HDMI-only colour-bar check, then return to 0 for OV5640 live video.
	localparam VIDEO_TEST_PATTERN = 1'b0;
	wire [23:0] test_pattern_rgb;
	wire [23:0] diagnostic_display_rgb;
	ddr_video_compare u_ddr_video_compare (
		.clk(clk_pixel), .rst_n(rstn_pixel), .vs(lcd_vs),
		.request(lcd_request), .actual(lcd_data),
		.normal_rgb({lcd_red, lcd_green, lcd_blue}), .rgb(diagnostic_display_rgb)
	);
	localparam DVP_MONITOR_OVERLAY = 1'b0;
	localparam EDGE_ENABLE = 1'b1;
	localparam FPS_OSD_ENABLE = 1'b1;
	localparam GRADIENT_DIAGNOSTIC = 1'b0;
	localparam [11:0] EDGE_THRESHOLD = 12'd88;
	wire edge_hs, edge_vs, edge_de;
	wire [23:0] edge_rgb, edge_fps_rgb;
	wire [7:0] camera_fps_bcd;
	wire camera_fps_valid;
	wire [11:0] edge_threshold_active;
	wire [2:0] edge_mode_active;
	wire median_on, noise_on, focus_mode;
	wire [11:0] edge_low_threshold = (edge_threshold_active >> 1);
	// The OV5640 module has a manually screwed lens: its VCM sink is not
	// connected to a focus motor, so the run-time focus control is off.
	localparam FOCUS_CONTROL_ENABLE = 1'b0;
	key_threshold #(.INITIAL_THRESHOLD(EDGE_THRESHOLD), .LAST_MODE(3'd4),
		.FOCUS_ENABLE(FOCUS_CONTROL_ENABLE)) u_key_threshold (
		.clk(clk_pixel), .rst_n(rstn_pixel), .vsync_n(lcd_vs),
		.key_n(key_n), .threshold_active(edge_threshold_active), .threshold_requested(),
		.mode_active(edge_mode_active), .mode_requested(),
		.freeze(frame_freeze),
		.median_on(median_on), .noise_on(noise_on),
		.focus_mode(focus_mode), .focus_code(focus_code_pixel),
		.tnr_mode(tnr_key_mode)
	);
	// Smooth grayscale with a 3x3 median (and optionally a 3x3 Gaussian),
	// then use Sobel + NMS before hysteresis linking. NMS keeps only the
	// local maximum along the gradient direction, removing the broad
	// double response.
	// Median demo (K1+K2): optional salt-and-pepper noise on the camera
	// pixels (about 0.8% white, 0.8% black, new pattern every frame), applied
	// before both the edge chain and the colour/gray background.
	wire [15:0] camera_rgb565 = {lcd_red[7:3], lcd_green[7:2], lcd_blue[7:3]};
	reg [15:0] noise_lfsr = 16'hace1;
	always @(posedge clk_pixel)
		if (lcd_request)
			noise_lfsr <= {noise_lfsr[14:0], noise_lfsr[15] ^ noise_lfsr[13] ^ noise_lfsr[12] ^ noise_lfsr[10]};
	wire [15:0] source_rgb565 = !noise_on ? camera_rgb565 :
		(noise_lfsr[7:1] == 7'd0) ? 16'hffff :
		(noise_lfsr[7:1] == 7'd1) ? 16'h0000 : camera_rgb565;
	wire [7:0] gray_pixel;
	rgb565_gray u_rgb565_gray (.rgb565(source_rgb565), .gray(gray_pixel));
	wire [7:0] filtered_pixel, filtered_center;
	wire filtered_valid, filtered_vs;
	wire [7:0] median_pixel;
	// 1: three-level selection network (row sort, column selection,
	// diagonal median), 6-clock latency. 0: the earlier nine-stage full
	// sort, 12-clock latency. Both output the exact 3x3 median.
	localparam MEDIAN_FAST = 1'b1;
	generate if (MEDIAN_FAST) begin: median_fast
		median3x3_fast #(.H_ACTIVE(1280)) u_median3x3_fast (
			.clk(clk_pixel), .rst_n(rstn_pixel), .hs_in(lcd_hs), .vs_in(lcd_vs),
			.de_in(lcd_request), .gray_in(gray_pixel),
			.hs_out(), .vs_out(filtered_vs), .de_out(filtered_valid),
			.gray_out(median_pixel), .gray_center_out(filtered_center)
		);
	end else begin: median_full_sort
		median3x3_video #(.H_ACTIVE(1280)) u_median3x3_video (
			.clk(clk_pixel), .rst_n(rstn_pixel), .hs_in(lcd_hs), .vs_in(lcd_vs),
			.de_in(lcd_request), .gray_in(gray_pixel),
			.hs_out(), .vs_out(filtered_vs), .de_out(filtered_valid),
			.gray_out(median_pixel), .gray_center_out(filtered_center)
		);
	end endgenerate
	// MED OFF passes the unfiltered center pixel with the same latency.
	assign filtered_pixel = median_on ? median_pixel : filtered_center;
	// Set to 1 for the Canny front end: median -> 3x3 Gaussian -> Sobel.
	// It costs one more image row and four pixel clocks of latency. 0 feeds
	// the median output straight into Sobel, as in the 2026-10-11 build.
	localparam GAUSSIAN_ENABLE = 1'b1;
	// Set to 1 to make the previous frame's NMS winner sticky (one extra
	// clock). 0 restores the 2026-10-11 same-pixel two-frame confirmation.
	localparam TEMPORAL_STICKY_ENABLE = 1'b1;
	wire [7:0] smooth_pixel, smooth_center;
	wire smooth_valid;
	generate if (GAUSSIAN_ENABLE) begin: gaussian_enabled
		gaussian_stream #(.H_ACTIVE(1280)) u_gaussian_stream (
			.clk(clk_pixel), .rst_n(rstn_pixel), .vsync_n(filtered_vs),
			.pixel_valid(filtered_valid), .gray_in(filtered_pixel),
			.gray_out(smooth_pixel), .gray_center_out(smooth_center),
			.pixel_valid_out(smooth_valid)
		);
	end else begin: gaussian_bypassed
		assign smooth_pixel = filtered_pixel;
		assign smooth_center = filtered_center;
		assign smooth_valid = filtered_valid;
	end endgenerate
	wire [7:0] sobel_edge_unused;
	wire [11:0] sobel_magnitude;
	wire [1:0] sobel_direction;
	wire sobel_valid;
	wire [7:0] sobel_gray;
	sobel_stream #(.H_ACTIVE(1280)) u_sobel_stream (
		.clk(clk_pixel), .rst_n(rstn_pixel), .vsync_n(filtered_vs),
		.pixel_valid(smooth_valid), .gray_in(smooth_pixel),
		.gray_center_in(smooth_center), .edge_out(sobel_edge_unused),
		.magnitude_out(sobel_magnitude), .direction_out(sobel_direction),
		.window_valid_out(sobel_valid), .gray_center_out(sobel_gray)
	);
	wire [11:0] nms_magnitude;
	wire [11:0] nms_raw_magnitude;
	wire [11:0] nms_neighbor_peak;
	wire [11:0] nms_neighbor_a, nms_neighbor_b;
	wire [7:0] nms_gray;
	wire [1:0] nms_direction;
	wire nms_valid;
	nms_stream #(.H_ACTIVE(1278)) u_nms_stream (
		.clk(clk_pixel), .rst_n(rstn_pixel), .vsync_n(filtered_vs),
		.pixel_valid(sobel_valid), .magnitude_in(sobel_magnitude),
		.direction_in(sobel_direction), .gray_in(sobel_gray),
		.magnitude_out(nms_magnitude), .raw_magnitude_out(nms_raw_magnitude),
		.neighbor_peak_out(nms_neighbor_peak),
		.neighbor_a_out(nms_neighbor_a), .neighbor_b_out(nms_neighbor_b),
		.pixel_valid_out(nms_valid),
		.gray_out(nms_gray), .direction_out(nms_direction)
	);
    wire [7:0] hysteresis_edge, hysteresis_gray;
    wire hysteresis_valid;
	hysteresis_stream #(.H_ACTIVE(1276), .NMS_BRIDGE_ENABLE(1'b1)) u_hysteresis_stream (
		.clk(clk_pixel), .rst_n(rstn_pixel), .vsync_n(lcd_vs),
		.pixel_valid(nms_valid), .magnitude_in(nms_magnitude),
		.raw_magnitude_in(nms_raw_magnitude),
		.gray_in(nms_gray), .low_threshold_in(edge_low_threshold),
        .high_threshold_in(edge_threshold_active), .edge_out(hysteresis_edge),
        .gray_out(hysteresis_gray), .pixel_valid_out(hysteresis_valid)
    );
    // Align the unsuppressed Sobel magnitude to the hysteresis output. The
    // temporal hold must not see the zeros inserted by NMS. The two-cycle
    // delay also feeds the optional diagnostic display below.
    reg [11:0] magnitude_d1, magnitude_d2;
    reg [11:0] neighbor_peak_d1, neighbor_peak_d2;
    reg [11:0] neighbor_a_d1, neighbor_a_d2;
    reg [11:0] neighbor_b_d1, neighbor_b_d2;
    always @(posedge clk_pixel or negedge rstn_pixel) begin
        if (!rstn_pixel) begin
            magnitude_d1 <= 12'd0;
            magnitude_d2 <= 12'd0;
            neighbor_peak_d1 <= 12'd0;
            neighbor_peak_d2 <= 12'd0;
            neighbor_a_d1 <= 12'd0;
            neighbor_a_d2 <= 12'd0;
            neighbor_b_d1 <= 12'd0;
            neighbor_b_d2 <= 12'd0;
        end else begin
            magnitude_d1 <= nms_raw_magnitude;
            magnitude_d2 <= magnitude_d1;
            neighbor_peak_d1 <= nms_neighbor_peak;
            neighbor_peak_d2 <= neighbor_peak_d1;
            neighbor_a_d1 <= nms_neighbor_a;
            neighbor_a_d2 <= neighbor_a_d1;
            neighbor_b_d1 <= nms_neighbor_b;
            neighbor_b_d2 <= neighbor_b_d1;
        end
    end
    // Release threshold of the edge_frame_hold fallback: one eighth of the
    // adjustable threshold.
    wire [11:0] edge_release_threshold = edge_threshold_active >> 3;
    wire [7:0] stable_edge, stable_gray;
    // NMS carries the center pixel's Sobel direction. Delay that direction
    // through hysteresis and the temporal stage to match the final edge pixel.
    wire [1:0] stable_direction;
    wire edge_toggle;
    reg [1:0] circle_dir_d1, circle_dir_d2, circle_dir_d3, circle_dir_d4;
    always @(posedge clk_pixel or negedge rstn_pixel) begin
        if (!rstn_pixel) begin
            circle_dir_d1<=0; circle_dir_d2<=0;
            circle_dir_d3<=0; circle_dir_d4<=0;
        end else begin
            circle_dir_d1<=nms_direction;
            circle_dir_d2<=circle_dir_d1;
            circle_dir_d3<=circle_dir_d2;
            circle_dir_d4<=circle_dir_d3;
        end
    end
    generate if (TEMPORAL_STICKY_ENABLE) begin: temporal_sticky
        // The old NMS winner stays while its raw gradient is above the low
        // threshold and near the gradient-direction peak; a new neighbour
        // of comparable strength is suppressed instead of replacing it.
        // It also replaces the same-pixel confirmation, which let every
        // second 60 Hz frame through unfiltered with the 30 fps camera.
        // A line is released below a quarter of the threshold and must stay
        // within 1/4 of its gradient-direction peak; an isolated new pixel
        // needs the full threshold.
        edge_temporal_sticky #(.H_ACTIVE(1276), .V_ACTIVE(720),
            .TOLERANCE_SHIFT(2)) u_edge_temporal_sticky (
            .clk(clk_pixel), .rst_n(rstn_pixel), .vsync_n(lcd_vs),
            .pixel_valid(hysteresis_valid), .edge_in(hysteresis_edge),
            .gray_in(hysteresis_gray), .magnitude_in(magnitude_d2),
            .neighbor_a_in(neighbor_a_d2), .neighbor_b_in(neighbor_b_d2),
            .direction_in(circle_dir_d2),
            .release_threshold_in(edge_low_threshold >> 1),
            .onset_threshold_in(edge_threshold_active),
            .edge_out(stable_edge), .gray_out(stable_gray),
            .direction_out(stable_direction), .toggle_out(edge_toggle)
        );
    end else begin: temporal_confirm
        assign edge_toggle = 1'b0;
        edge_frame_hold #(.H_ACTIVE(1276), .V_ACTIVE(720),
            .PEAK_GUARD_ENABLE(1'b1), .PEAK_TOLERANCE(13'd8),
            .TEMPORAL_CONFIRM_ENABLE(1'b1)) u_edge_frame_hold (
            .clk(clk_pixel), .rst_n(rstn_pixel), .vsync_n(lcd_vs),
            .pixel_valid(hysteresis_valid), .edge_in(hysteresis_edge),
            .gray_in(hysteresis_gray), .magnitude_in(magnitude_d2),
            .neighbor_peak_in(neighbor_peak_d2),
            .release_threshold_in(edge_release_threshold),
            .edge_out(stable_edge), .gray_out(stable_gray)
        );
        assign stable_direction = circle_dir_d4;
    end endgenerate
	// Match the original RGB565 pixel to its edge result. The median + NMS
	// chain measured three image rows and 24 pixel clocks; the Gaussian
	// stage adds one row and four clocks, the sticky temporal stage one clock.
	localparam integer ALIGN_ROW_DELAY = GAUSSIAN_ENABLE ? 4 : 3;
	// The fast median network is six clocks shorter than the full sort.
	localparam integer ALIGN_PIXEL_DELAY = 24 + (GAUSSIAN_ENABLE ? 4 : 0) +
		(TEMPORAL_STICKY_ENABLE ? 1 : 0) - (MEDIAN_FAST ? 6 : 0);
	wire [15:0] aligned_rgb565;
	wire aligned_rgb_valid;
	rgb565_frame_align #(.H_ACTIVE(1280), .ROW_DELAY(ALIGN_ROW_DELAY),
		.PIXEL_DELAY(ALIGN_PIXEL_DELAY)) u_rgb565_frame_align (
		.clk(clk_pixel), .rst_n(rstn_pixel), .vsync_n(lcd_vs),
		.pixel_valid(lcd_request),
		.rgb565_in(source_rgb565),
		.rgb565_out(aligned_rgb565), .pixel_valid_out(aligned_rgb_valid)
	);
	wire [23:0] aligned_rgb = {
		aligned_rgb565[15:11], 3'b000,
		aligned_rgb565[10:5], 2'b00,
		aligned_rgb565[4:0], 3'b000
	};
	// Display-only choices: the edge detector and its threshold are shared.
	// Mode 0: the previous half-brightness grayscale background + white edges.
	// Mode 1: black background + white edges.
	// Mode 2: original colour background + red edges.
	// Mode 3: split screen, original grayscale left, binary edges right.
	// Mode 4: Sobel gradient magnitude |Gx|+|Gy| as grayscale with a soft
	//         threshold (black below THR/2), no binary decision: the
	//         plain-Sobel display for comparison.
	// With the Gaussian stage the gray sideband is the median output, so
	// take the unfiltered background from the aligned colour pixel instead.
	wire [7:0] aligned_gray;
	rgb565_gray u_aligned_gray (.rgb565(aligned_rgb565), .gray(aligned_gray));
	wire [7:0] background_gray = GAUSSIAN_ENABLE ? aligned_gray : stable_gray;
	wire [7:0] gray_overlay_pixel = (stable_edge != 8'd0) ?
		8'hff : {1'b0, background_gray[7:1]};
	wire [23:0] gray_overlay_rgb = {
		gray_overlay_pixel, gray_overlay_pixel, gray_overlay_pixel
	};
	wire [23:0] black_overlay_rgb = (stable_edge != 8'd0) ?
		24'hffffff : 24'h000000;
	wire [23:0] color_overlay_rgb = (stable_edge != 8'd0) ?
		24'hff0000 : aligned_rgb;
	wire [23:0] split_rgb = (diagnostic_lcd_x == 12'd640) ? 24'h00ff00 :
		(diagnostic_lcd_x < 12'd640) ? {aligned_gray, aligned_gray, aligned_gray} :
		black_overlay_rgb;
	// Soft threshold: below THR/2 is black, above it twice the excess.
	wire [11:0] magnitude_floor = edge_threshold_active >> 1;
	wire [12:0] magnitude_excess = (magnitude_d2 > magnitude_floor) ?
		{1'b0, magnitude_d2 - magnitude_floor} << 1 : 13'd0;
	wire [7:0] magnitude_gray = (magnitude_excess > 13'd255) ? 8'hff : magnitude_excess[7:0];
	wire [23:0] magnitude_rgb = !hysteresis_valid ? 24'h000000 :
		{magnitude_gray, magnitude_gray, magnitude_gray};
	wire [23:0] selected_overlay_rgb =
		(edge_mode_active == 3'd4) ? magnitude_rgb :
		!aligned_rgb_valid ? 24'h000000 :
		(edge_mode_active == 3'd0) ? gray_overlay_rgb :
		(edge_mode_active == 3'd1) ? black_overlay_rgb :
		(edge_mode_active == 3'd2) ? color_overlay_rgb : split_rgb;
	// Optional colour diagnostic is disabled in the normal white-edge display.
	wire [11:0] diagnostic_floor = edge_low_threshold >> 1;
	wire [7:0] diagnostic_gray = {2'b00, hysteresis_gray[7:2]};
	wire [23:0] gradient_diagnostic_rgb = !hysteresis_valid ? 24'h000000 :
		(hysteresis_edge != 8'd0) ? 24'hffffff :
		(magnitude_d2 >= edge_low_threshold) ? 24'hffff00 :
		(magnitude_d2 >= diagnostic_floor) ? 24'hff0000 :
		{diagnostic_gray, diagnostic_gray, diagnostic_gray};
	assign edge_hs = lcd_hs;
	assign edge_vs = lcd_vs;
	assign edge_de = lcd_de;
	assign edge_rgb = GRADIENT_DIAGNOSTIC ? gradient_diagnostic_rgb :
		selected_overlay_rgb;
	camera_fps u_camera_fps (
		.clk_sys(clk_sys), .rst_n(rstn_sys), .camera_vsync(cmos_vsync),
		.camera_ready(ov5640_config_ready), .clk_pixel(clk_pixel),
		.fps_bcd(camera_fps_bcd), .fps_valid(camera_fps_valid)
	);
	// The latency value changes at most once per camera frame; take it only
	// when two successive synchronized samples agree.
	(* async_reg = "true" *) reg [8:0] latency_meta = 0, latency_sync = 0;
	reg [7:0] frame_latency_pixel = 0;
	reg frame_latency_pixel_valid = 0;
	always @(posedge clk_pixel) begin
		latency_meta <= {w_frame_latency_valid, w_frame_latency_ms};
		latency_sync <= latency_meta;
		if (latency_sync == latency_meta) begin
			frame_latency_pixel <= latency_sync[7:0];
			frame_latency_pixel_valid <= latency_sync[8];
		end
	end
	// TNR change share (DDR clock): same two-sample agreement as above.
	(* async_reg = "true" *) reg [7:0] change_meta = 0, change_sync = 0;
	reg [6:0] change_pct_pixel = 0;
	reg change_valid_pixel = 0;
	always @(posedge clk_pixel) begin
		change_meta <= {w_tnr_change_valid, w_tnr_change_pct};
		change_sync <= change_meta;
		if (change_sync == change_meta) begin
			change_pct_pixel <= change_sync[6:0];
			change_valid_pixel <= change_sync[7];
		end
	end
	// Edge flicker: toggled edge pixels summed over 60 display frames
	// (about one second, 30 camera frames), shown per camera frame (/32).
	reg [19:0] flk_frame = 0;
	reg [25:0] flk_sum = 0;
	reg [5:0] flk_frames = 0;
	reg [11:0] flk_value = 0;
	reg flk_vs_d = 1;
	wire [25:0] flk_total = flk_sum + flk_frame;
	always @(posedge clk_pixel) begin
		flk_vs_d <= lcd_vs;
		if (flk_vs_d && !lcd_vs) begin
			flk_frame <= 20'd0;
			if (flk_frames == 6'd59) begin
				flk_frames <= 6'd0;
				flk_sum <= 26'd0;
				flk_value <= (flk_total[25:5] > 21'd4095) ? 12'd4095 : flk_total[16:5];
			end else begin
				flk_frames <= flk_frames + 6'd1;
				flk_sum <= flk_total;
			end
		end else if (edge_toggle && flk_frame != 20'hfffff) begin
			flk_frame <= flk_frame + 20'd1;
		end
	end
	fps_osd #(.SHOW_FOCUS(FOCUS_CONTROL_ENABLE)) u_fps_osd (
		.clk(clk_pixel), .rst_n(rstn_pixel), .vs(edge_vs), .de(edge_de),
		.rgb_in(edge_rgb), .fps_bcd(camera_fps_bcd), .fps_valid(camera_fps_valid),
		.threshold_in(edge_threshold_active),
		.latency_ms(frame_latency_pixel), .latency_valid(frame_latency_pixel_valid),
		.median_on(median_on), .noise_on(noise_on), .tnr_mode(tnr_mode),
		.change_pct(change_pct_pixel), .change_valid(change_valid_pixel),
		.flicker(flk_value),
		.focus_code(focus_code_pixel), .focus_mode(focus_mode),
		.rgb_out(edge_fps_rgb)
	);
	// Recognize one near-frontal circular outline from the stable edge map.
	// Search and annotation use separate frame banks and do not stall video.
	wire circle_found;
	wire [10:0] circle_x;
	wire [9:0] circle_y, circle_radius;
	wire [23:0] circle_annotated_rgb;
	circle_geometry_detector u_circle_geometry_detector (
		.clk(clk_pixel), .rst_n(rstn_pixel), .vsync_n(lcd_vs), .de(lcd_de),
		.edge_pixel(stable_edge != 8'd0), .edge_direction(stable_direction),
		.found(circle_found), .center_x(circle_x), .center_y(circle_y),
		.radius_px(circle_radius)
	);
	circle_label_osd u_circle_label_osd (
		.clk(clk_pixel), .rst_n(rstn_pixel), .vsync_n(lcd_vs), .de(lcd_de),
		.rgb_in(FPS_OSD_ENABLE ? edge_fps_rgb : edge_rgb),
		.found(circle_found), .center_x(circle_x), .center_y(circle_y),
		.radius_px(circle_radius), .rgb_out(circle_annotated_rgb)
	);
	wire use_edge_timing = 1'b0;
	wire hdmi_vs = lcd_vs;
	wire hdmi_hs = lcd_hs;
	wire hdmi_de = lcd_de;
	wire [23:0] dvp_status_rgb = dvp_status_pixel[0] ? 24'hff0000 :
		dvp_status_pixel[1] ? 24'h0000ff : dvp_status_pixel[2] ? 24'h00ff00 : 24'hffff00;
	wire [23:0] hdmi_rgb = VIDEO_TEST_PATTERN ? test_pattern_rgb :
		DDR_VIDEO_DIAGNOSTIC ? diagnostic_display_rgb :
		(DVP_MONITOR_OVERLAY && diagnostic_lcd_x < 64 && diagnostic_lcd_y < 12) ? dvp_status_rgb :
		EDGE_ENABLE ? circle_annotated_rgb : {lcd_red, lcd_green, lcd_blue};
	video_test_pattern u_video_test_pattern (
		.clk   (clk_pixel),
		.rst_n (rstn_pixel),
		.de    (lcd_de),
		.rgb   (test_pattern_rgb)
	);
	
	assign hdmi_txd0_rst_o = rst_pixel; 
	assign hdmi_txd1_rst_o = rst_pixel; 
	assign hdmi_txd2_rst_o = rst_pixel; 
	assign hdmi_txc_rst_o = rst_pixel; 
	
	assign hdmi_txd0_oe = 1'b1; 
	assign hdmi_txd1_oe = 1'b1; 
	assign hdmi_txd2_oe = 1'b1; 
	assign hdmi_txc_oe = 1'b1; 
	
	//-------------------------------------
	//Digilent HDMI-TX IP Modified by CB elec.
	rgb2dvi #(.ENABLE_OSERDES(0)) u_rgb2dvi 
	(
		//.TMDS_Clk_p		(hdmio_txc_p_o), 	//	w_hdmio_txc), 
		//.TMDS_Clk_n		(hdmio_txc_n_o), 
		//.TMDS_Data_p	(hdmio_txd_p_o), 	//	w_hdmio_txd), 
		//.TMDS_Data_n 	(hdmio_txd_n_o), 
		
		.oe_i 		(1), 			//	Always enable output
		.bitflip_i 		(4'b0000), 		//	Reverse clock & data lanes. 
		
		.aRst			(1'b0), 
		.aRst_n		(1'b1), 
		
		.PixelClk		(clk_pixel        ),//pixel clk = 74.25M
		.SerialClk		(     ),//pixel clk *5 = 371.25M
		
		.vid_pVSync		(hdmi_vs),
		.vid_pHSync		(hdmi_hs),
		.vid_pVDE		(hdmi_de),
		.vid_pData		(hdmi_rgb), 
		
		.txc_o			(hdmi_txc_o), 
		.txd0_o			(hdmi_txd0_o), 
		.txd1_o			(hdmi_txd1_o), 
		.txd2_o			(hdmi_txd2_o)
	); 
		
	






	
	
endmodule

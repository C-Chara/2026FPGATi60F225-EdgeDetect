`timescale 1ns/1ps

// Delay the original RGB565 image to the center pixel of the live edge chain.
// Its measured phase is ROW_DELAY active video rows plus PIXEL_DELAY clocks.
// The row ring buffer reads the old pixel before overwriting it.
// ROW_DELAY may be 1 to 6.
module rgb565_frame_align #(
    parameter integer H_ACTIVE = 1280,
    parameter integer ROW_DELAY = 3,
    parameter integer PIXEL_DELAY = 24
)(
    input wire clk,
    input wire rst_n,
    input wire vsync_n,
    input wire pixel_valid,
    input wire [15:0] rgb565_in,
    output wire [15:0] rgb565_out,
    output wire pixel_valid_out
);
    localparam integer BUFFER_PIXELS = ROW_DELAY * H_ACTIVE;
    reg [15:0] line_ring [0:BUFFER_PIXELS-1];
    reg [15:0] line_read_q;
    reg [10:0] column;
    reg [2:0] row_bank;
    reg [2:0] rows_seen;
    reg read_valid_q;
    reg [12:0] bank_base;
    wire [12:0] ram_address = bank_base + column;

    // Keep RAM and its read register outside the resettable control process
    // so Efinity can infer synchronous block RAM.
    always @(posedge clk) begin
        if (pixel_valid) begin
            line_read_q <= line_ring[ram_address];
            line_ring[ram_address] <= rgb565_in;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            column <= 11'd0;
            row_bank <= 3'd0;
            bank_base <= 13'd0;
            rows_seen <= 3'd0;
            read_valid_q <= 1'b0;
        end else begin
            read_valid_q <= pixel_valid && (rows_seen == ROW_DELAY);
            if (!vsync_n) begin
                column <= 11'd0;
                row_bank <= 3'd0;
                bank_base <= 13'd0;
                rows_seen <= 3'd0;
                read_valid_q <= 1'b0;
            end else if (pixel_valid) begin
                if (column == H_ACTIVE-1) begin
                    column <= 11'd0;
                    if (row_bank == ROW_DELAY-1) begin
                        row_bank <= 3'd0;
                        bank_base <= 13'd0;
                    end else begin
                        row_bank <= row_bank + 3'd1;
                        bank_base <= bank_base + H_ACTIVE;
                    end
                    if (rows_seen != ROW_DELAY)
                        rows_seen <= rows_seen + 3'd1;
                end else begin
                    column <= column + 11'd1;
                end
            end else begin
                column <= 11'd0;
            end
        end
    end

    reg [15:0] pixel_pipe [0:PIXEL_DELAY-1];
    reg [PIXEL_DELAY-1:0] valid_pipe;
    integer stage;
    always @(posedge clk) begin
        pixel_pipe[0] <= line_read_q;
        for (stage = 1; stage < PIXEL_DELAY; stage = stage + 1)
            pixel_pipe[stage] <= pixel_pipe[stage-1];
    end
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            valid_pipe <= {PIXEL_DELAY{1'b0}};
        else
            valid_pipe <= {valid_pipe[PIXEL_DELAY-2:0], read_valid_q};
    end
    assign pixel_valid_out = valid_pipe[PIXEL_DELAY-1];
    assign rgb565_out = pixel_valid_out ? pixel_pipe[PIXEL_DELAY-1] : 16'd0;
endmodule

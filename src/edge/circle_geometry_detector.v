`timescale 1ns/1ps

// One prominent, nearly frontal circle in the edge image. Each 4x4 display
// block contributes one occupancy bit. The inactive bank is searched while
// the next video frame is captured into the other bank.
module circle_geometry_detector #(
    parameter integer H_ACTIVE = 1280,
    parameter integer V_ACTIVE = 720,
    parameter integer R_MIN = 12,
    parameter integer R_MAX = 40,
    parameter integer R_STEP = 4,
    parameter integer CENTER_STEP = 4,
    parameter integer CENTER_MARGIN = 16,
    parameter integer MIN_SCORE = 11,
    parameter integer FINAL_SCORE = 15,
    parameter integer MAX_SIDE_HITS = 6
)(
    input wire clk,
    input wire rst_n,
    input wire vsync_n,
    input wire de,
    input wire edge_pixel,
    input wire [1:0] edge_direction,
    output reg found,
    output reg [10:0] center_x,
    output reg [9:0] center_y,
    output reg [9:0] radius_px
);
    localparam integer GRID_W = H_ACTIVE / 4;
    localparam integer GRID_H = V_ACTIVE / 4;
    localparam integer GRID_CELLS = GRID_W * GRID_H;
    localparam integer CENTER_LAST_X = ((GRID_W-CENTER_MARGIN-CENTER_MARGIN) / CENTER_STEP) * CENTER_STEP + CENTER_MARGIN;
    localparam integer CENTER_LAST_Y = ((GRID_H-CENTER_MARGIN-CENTER_MARGIN) / CENTER_STEP) * CENTER_STEP + CENTER_MARGIN;

    localparam [3:0] ST_INIT0=0, ST_INIT1=1, ST_IDLE=2,
                     ST_SEARCH=3, ST_DRAIN=4, ST_CLEAR=5,
                     ST_REFINE_SETUP=6, ST_VALIDATE_SETUP=7,
                     ST_VALIDATE=8, ST_VALIDATE_DRAIN=9;
    reg [3:0] state;
    reg [15:0] clear_addr;
    reg capture_bank, search_bank;
    reg started, result_ready;
    reg vs_d, de_d;
    reg [10:0] x;
    reg [9:0] y;
    wire vs_fall = vs_d && !vsync_n;
    wire capture_hit = started && de && edge_pixel &&
                       x < H_ACTIVE && y < V_ACTIVE;
    wire [15:0] capture_addr = (y >> 2) * GRID_W + (x >> 2);

    reg [8:0] trial_x;
    reg [7:0] trial_y;
    reg [5:0] trial_r;
    reg [8:0] trial_last_x;
    reg [7:0] trial_last_y;
    reg [5:0] trial_last_r;
    reg [8:0] trial_first_x;
    reg [5:0] trial_first_r;
    reg refining;
    reg [3:0] sector;
    reg [1:0] tap;
    wire [5:0] sample_r = (state == ST_VALIDATE) ?
                          (tap == 0 ? trial_r-6'd5 : trial_r+6'd5) :
                          (tap == 2'd0) ? trial_r-(refining ? 6'd1 : 6'd2) :
                          (tap == 2'd1) ? trial_r :
                          trial_r+(refining ? 6'd1 : 6'd2);
    wire [5:0] shallow_r = (sample_r * 6 + 8) >> 4;
    wire [5:0] diagonal_r = (sample_r * 11 + 8) >> 4;
    wire [5:0] steep_r = (sample_r * 15 + 8) >> 4;
    reg signed [9:0] dx, dy;
    always @* begin
        dx=0; dy=0;
        case (sector)
            0:  begin dx=$signed({4'd0,sample_r}); dy=0; end
            1:  begin dx=$signed({4'd0,steep_r}); dy=$signed({4'd0,shallow_r}); end
            2:  begin dx=$signed({4'd0,diagonal_r}); dy=$signed({4'd0,diagonal_r}); end
            3:  begin dx=$signed({4'd0,shallow_r}); dy=$signed({4'd0,steep_r}); end
            4:  begin dx=0; dy=$signed({4'd0,sample_r}); end
            5:  begin dx=-$signed({4'd0,shallow_r}); dy=$signed({4'd0,steep_r}); end
            6:  begin dx=-$signed({4'd0,diagonal_r}); dy=$signed({4'd0,diagonal_r}); end
            7:  begin dx=-$signed({4'd0,steep_r}); dy=$signed({4'd0,shallow_r}); end
            8:  begin dx=-$signed({4'd0,sample_r}); dy=0; end
            9:  begin dx=-$signed({4'd0,steep_r}); dy=-$signed({4'd0,shallow_r}); end
            10: begin dx=-$signed({4'd0,diagonal_r}); dy=-$signed({4'd0,diagonal_r}); end
            11: begin dx=-$signed({4'd0,shallow_r}); dy=-$signed({4'd0,steep_r}); end
            12: begin dx=0; dy=-$signed({4'd0,sample_r}); end
            13: begin dx=$signed({4'd0,shallow_r}); dy=-$signed({4'd0,steep_r}); end
            14: begin dx=$signed({4'd0,diagonal_r}); dy=-$signed({4'd0,diagonal_r}); end
            15: begin dx=$signed({4'd0,steep_r}); dy=-$signed({4'd0,shallow_r}); end
            default: begin dx=0; dy=0; end
        endcase
    end
    wire signed [10:0] sample_x = $signed({2'd0,trial_x}) + dx;
    wire signed [10:0] sample_y = $signed({3'd0,trial_y}) + dy;
    wire in_bounds = sample_x >= 0 && sample_x < GRID_W &&
                     sample_y >= 0 && sample_y < GRID_H;
    wire [15:0] search_addr = sample_y * GRID_W + sample_x;

    // Both arrays have a synchronous read port and one write port. Clearing
    // happens only on the bank that is not being filled by the video stream.
    reg [2:0] occupancy0 [0:GRID_CELLS-1];
    reg [2:0] occupancy1 [0:GRID_CELLS-1];
    reg [2:0] occupancy0_q, occupancy1_q;
    wire clear_bank0 = state == ST_INIT0 || (state == ST_CLEAR && !search_bank);
    wire clear_bank1 = state == ST_INIT1 || (state == ST_CLEAR && search_bank);
    wire write0 = clear_bank0 || (capture_hit && !capture_bank);
    wire write1 = clear_bank1 || (capture_hit && capture_bank);
    wire [15:0] write_addr0 = clear_bank0 ? clear_addr : capture_addr;
    wire [15:0] write_addr1 = clear_bank1 ? clear_addr : capture_addr;
    always @(posedge clk) begin
        occupancy0_q <= occupancy0[search_addr];
        occupancy1_q <= occupancy1[search_addr];
        if (write0) occupancy0[write_addr0] <= clear_bank0 ? 3'b000 : {edge_direction,1'b1};
        if (write1) occupancy1[write_addr1] <= clear_bank1 ? 3'b000 : {edge_direction,1'b1};
    end

    reg pending, pending_bounds, pending_validation;
    reg [3:0] pending_sector;
    reg [1:0] pending_tap;
    reg [8:0] pending_x;
    reg [7:0] pending_y;
    reg [5:0] pending_r;
    reg sector_hit;
    reg [4:0] score;
    reg [15:0] sector_mask;
    reg [4:0] best_score;
    reg [15:0] best_mask;
    reg [5:0] side_hits;
    reg [8:0] best_x;
    reg [7:0] best_y;
    reg [5:0] best_r;
    function direction_matches;
        input [3:0] angle;
        input [1:0] direction;
        begin
            case (angle)
                0,8: direction_matches = (direction == 2'd0);
                4,12: direction_matches = (direction == 2'd1);
                2,10: direction_matches = (direction == 2'd2);
                6,14: direction_matches = (direction == 2'd3);
                1,9: direction_matches = (direction == 2'd0 || direction == 2'd2);
                3,11: direction_matches = (direction == 2'd1 || direction == 2'd2);
                5,13: direction_matches = (direction == 2'd1 || direction == 2'd3);
                7,15: direction_matches = (direction == 2'd0 || direction == 2'd3);
                default: direction_matches = 1'b0;
            endcase
        end
    endfunction
    wire [2:0] sampled_cell = search_bank ? occupancy1_q : occupancy0_q;
    wire hit = pending_bounds && sampled_cell[0] &&
               direction_matches(pending_sector,sampled_cell[2:1]);
    wire [4:0] completed_score = score + {4'd0,(sector_hit || hit)};
    wire [15:0] completed_mask = {sector_hit || hit,sector_mask[14:0]};
    wire [2:0] diagonal_count = {2'd0,completed_mask[2]} +
                                {2'd0,completed_mask[6]} +
                                {2'd0,completed_mask[10]} +
                                {2'd0,completed_mask[14]};
    wire last_trial = trial_x == trial_last_x && trial_y == trial_last_y &&
                      trial_r == trial_last_r && sector == 15 && tap == 2;

    reg track_valid;
    reg [8:0] track_x;
    reg [7:0] track_y;
    reg [5:0] track_r;
    reg [1:0] confirm_count, miss_count;
    wire close_to_track = (best_x > track_x ? best_x-track_x : track_x-best_x) <= 9'd8 &&
                          (best_y > track_y ? best_y-track_y : track_y-best_y) <= 8'd8 &&
                          (best_r > track_r ? best_r-track_r : track_r-best_r) <= 6'd8;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state<=ST_INIT0; clear_addr<=0;
            capture_bank<=0; search_bank<=0; started<=0; result_ready<=0;
            vs_d<=1; de_d<=0; x<=0; y<=0;
            trial_x<=CENTER_MARGIN; trial_y<=CENTER_MARGIN;
            trial_r<=R_MIN; sector<=0; tap<=0;
            trial_last_x<=CENTER_LAST_X; trial_last_y<=CENTER_LAST_Y;
            trial_last_r<=R_MAX; refining<=0;
            trial_first_x<=CENTER_MARGIN; trial_first_r<=R_MIN;
            pending<=0; pending_bounds<=0; pending_validation<=0;
            pending_sector<=0; pending_tap<=0;
            pending_x<=0; pending_y<=0; pending_r<=0;
            sector_hit<=0; score<=0; sector_mask<=0;
            best_score<=0; best_mask<=0; best_x<=0; best_y<=0; best_r<=0;
            side_hits<=0;
            track_valid<=0; track_x<=0; track_y<=0; track_r<=0;
            confirm_count<=0; miss_count<=0;
            found<=0; center_x<=0; center_y<=0; radius_px<=0;
        end else begin
            vs_d <= vsync_n;
            de_d <= de;
            if (!vsync_n) begin x<=0; y<=0; de_d<=0; end
            else if (de) x<=x+11'd1;
            else begin
                x<=0;
                if (de_d) y<=y+10'd1;
            end

            pending <= (state == ST_SEARCH || state == ST_VALIDATE);
            if (state == ST_SEARCH || state == ST_VALIDATE) begin
                pending_bounds <= in_bounds;
                pending_validation <= (state == ST_VALIDATE);
                pending_sector <= sector;
                pending_tap <= tap;
                pending_x <= trial_x;
                pending_y <= trial_y;
                pending_r <= trial_r;
            end
            if (pending && pending_validation) begin
                if (pending_bounds && sampled_cell[0])
                    side_hits<=side_hits+6'd1;
            end else if (pending) begin
                if (pending_tap == 2) begin
                    sector_hit <= 0;
                    sector_mask[pending_sector] <= sector_hit || hit;
                    if (pending_sector == 15) begin
                        if (completed_score >= MIN_SCORE &&
                            diagonal_count >= 3 && completed_score > best_score) begin
                            best_score <= completed_score;
                            best_mask <= completed_mask;
                            best_x <= pending_x;
                            best_y <= pending_y;
                            best_r <= pending_r;
                        end
                        score <= 0;
                        sector_mask <= 0;
                    end else score <= completed_score;
                end else sector_hit <= sector_hit || hit;
            end

            case (state)
                ST_INIT0: begin
                    if (clear_addr == GRID_CELLS-1) begin
                        clear_addr<=0; state<=ST_INIT1;
                    end else clear_addr<=clear_addr+16'd1;
                end
                ST_INIT1: begin
                    if (clear_addr == GRID_CELLS-1) begin
                        clear_addr<=0; state<=ST_IDLE;
                    end else clear_addr<=clear_addr+16'd1;
                end
                ST_IDLE: if (vs_fall) begin
                    if (!started) started<=1;
                    else begin
                        if (result_ready) begin
                            if (best_score >= FINAL_SCORE &&
                                side_hits <= MAX_SIDE_HITS) begin
                                if (track_valid && close_to_track) begin
                                    if (confirm_count != 2'd3)
                                        confirm_count<=confirm_count+2'd1;
                                    if (confirm_count >= 2'd1) found<=1;
                                end else begin
                                    confirm_count<=2'd1;
                                    found<=0;
                                end
                                track_valid<=1;
                                track_x<=best_x; track_y<=best_y; track_r<=best_r;
                                center_x<={best_x,2'b00};
                                center_y<={best_y,2'b00};
                                radius_px<={best_r,2'b00};
                                miss_count<=0;
                            end else if (found && miss_count < 2'd2)
                                miss_count<=miss_count+2'd1;
                            else begin
                                found<=0; track_valid<=0; confirm_count<=0;
                            end
                        end
                        capture_bank<=~capture_bank;
                        search_bank<=capture_bank;
                        trial_x<=CENTER_MARGIN; trial_y<=CENTER_MARGIN;
                        trial_r<=R_MIN; sector<=0; tap<=0;
                        trial_last_x<=CENTER_LAST_X;
                        trial_last_y<=CENTER_LAST_Y;
                        trial_last_r<=R_MAX; refining<=0;
                        trial_first_x<=CENTER_MARGIN; trial_first_r<=R_MIN;
                        score<=0; sector_hit<=0; sector_mask<=0; best_score<=0;
                        result_ready<=0; side_hits<=0;
                        state<=ST_SEARCH;
                    end
                end
                ST_SEARCH: begin
                    if (last_trial) state<=ST_DRAIN;
                    else if (tap != 2) tap<=tap+2'd1;
                    else begin
                        tap<=0;
                        if (sector != 15) sector<=sector+4'd1;
                        else begin
                            sector<=0;
                            if (trial_r != trial_last_r)
                                trial_r<=trial_r+(refining ? 1 : R_STEP);
                            else begin
                                trial_r<=trial_first_r;
                                if (trial_x != trial_last_x)
                                    trial_x<=trial_x+(refining ? 1 : CENTER_STEP);
                                else begin
                                    trial_x<=trial_first_x;
                                    trial_y<=trial_y+(refining ? 1 : CENTER_STEP);
                                end
                            end
                        end
                    end
                end
                ST_DRAIN: begin
                    clear_addr<=0;
                    if (!refining) state<=ST_REFINE_SETUP;
                    else state<=ST_VALIDATE_SETUP;
                end
                ST_REFINE_SETUP: begin
                    if (best_score < MIN_SCORE) state<=ST_CLEAR;
                    else begin
                        refining<=1;
                        trial_first_x<=best_x > 9'd3 ? best_x-9'd3 : 9'd0;
                        trial_first_r<=best_r > 6'd2 ? best_r-6'd2 : 6'd2;
                        trial_x<=best_x > 9'd3 ? best_x-9'd3 : 9'd0;
                        trial_y<=best_y > 8'd3 ? best_y-8'd3 : 8'd0;
                        trial_r<=best_r > 6'd2 ? best_r-6'd2 : 6'd2;
                        trial_last_x<=best_x+9'd3 < GRID_W ? best_x+9'd3 : GRID_W-1;
                        trial_last_y<=best_y+8'd3 < GRID_H ? best_y+8'd3 : GRID_H-1;
                        trial_last_r<=best_r+6'd2;
                        sector<=0; tap<=0; score<=0; sector_hit<=0;
                        sector_mask<=0; best_score<=0;
                        state<=ST_SEARCH;
                    end
                end
                ST_VALIDATE_SETUP: begin
                    if (best_score < FINAL_SCORE) state<=ST_CLEAR;
                    else begin
                        trial_x<=best_x;
                        trial_y<=best_y;
                        trial_r<=best_r;
                        sector<=0; tap<=0;
                        side_hits<=0;
                        state<=ST_VALIDATE;
                    end
                end
                ST_VALIDATE: begin
                    if (sector == 15 && tap == 1)
                        state<=ST_VALIDATE_DRAIN;
                    else if (tap == 0) tap<=1;
                    else begin tap<=0; sector<=sector+4'd1; end
                end
                ST_VALIDATE_DRAIN: state<=ST_CLEAR;
                ST_CLEAR: begin
                    if (clear_addr == GRID_CELLS-1) begin
                        clear_addr<=0; result_ready<=1; state<=ST_IDLE;
                    end else clear_addr<=clear_addr+16'd1;
                end
                default: state<=ST_INIT0;
            endcase
        end
    end
endmodule

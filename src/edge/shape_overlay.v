`timescale 1ns/1ps

// Draws the shape_detector results on the video: the object's own contour
// (the edge pixels inside its box, widened to 2 pixels) in its class
// colour, and (when there are at most LABELS objects) the class name above
// the box:
//   circle 圆形 yellow, ellipse 椭圆 orange, square 正方形 cyan,
//   rectangle 矩形 green, triangle 三角形 magenta.
// Where boxes overlap, an edge pixel takes the colour of the object it is
// most inside: for the first OWN objects the Mahalanobis distance to the
// object's moment ellipse (its centroid and inverse second moments from
// shape_detector, so it turns with a rotated shape) decides; objects
// beyond OWN, or without moments yet, keep "first box wins". The moments
// of a shown object are found by its box in the detector's latest list
// (the tracker shows detector boxes); a held object keeps the last ones.
// Six-clock pipeline; de/hs/vs are delayed with the colour so the picture
// keeps its position.
module shape_overlay #(
    parameter integer MAX_OBJECTS = 32,
    parameter integer LABELS = 8,
    // Screen position of detector pixel (0, 0): the display delay of the
    // colour image and edges relative to the detector's coordinates.
    parameter integer X_OFF = 0,
    parameter integer Y_OFF = 0,
    parameter integer OWN = 8
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        enable,
    input  wire        vs_in, hs_in, de_in,      // vs active low (lcd_vs)
    input  wire [23:0] rgb_in,
    input  wire        edge_in,                  // edge pixel, same clock as rgb_in
    input  wire [5:0]  obj_count,
    input  wire [MAX_OBJECTS*41-1:0] obj_data,
    // the detector's own list (boxes and moments) for the colouring
    input  wire [5:0]  det_count,
    input  wire [MAX_OBJECTS*41-1:0] det_data,
    output wire [4:0]  mom_raddr,                // shape_detector moment RAM
    input  wire [77:0] mom_q,
    output reg         vs_out, hs_out, de_out,
    output reg  [23:0] rgb_out
);
    // Display position of the incoming pixel
    reg [10:0] x;
    reg [9:0]  y;
    reg        de_d;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin x <= 0; y <= 0; de_d <= 0; end
        else if (!vs_in) begin x <= 0; y <= 0; de_d <= 0; end
        else begin
            de_d <= de_in;
            if (de_in) x <= x + 11'd1;
            else begin
                x <= 0;
                if (de_d) y <= y + 10'd1;
            end
        end
    end

    function [23:0] cls_rgb;
        input [2:0] c;
        case (c)
            3'd1: cls_rgb = 24'hffff00;
            3'd2: cls_rgb = 24'hff8000;
            3'd3: cls_rgb = 24'h00ffff;
            3'd4: cls_rgb = 24'h00ff00;
            3'd5: cls_rgb = 24'hff00ff;
            default: cls_rgb = 24'hffffff;
        endcase
    endfunction
    function [1:0] cls_len;           // glyphs in the name minus one
        input [2:0] c;
        cls_len = (c == 3'd3 || c == 3'd5) ? 2'd2 : 2'd1;
    endfunction
    function [2:0] cls_glyph;         // glyph code of character k of the name
        input [2:0] c;
        input [1:0] k;
        case (c)
            3'd1: cls_glyph = (k == 0) ? 3'd0 : 3'd1;                       // 圆形
            3'd2: cls_glyph = (k == 0) ? 3'd2 : 3'd0;                       // 椭圆
            3'd3: cls_glyph = (k == 0) ? 3'd3 : (k == 1) ? 3'd4 : 3'd1;    // 正方形
            3'd4: cls_glyph = (k == 0) ? 3'd5 : 3'd1;                       // 矩形
            default: cls_glyph = (k == 0) ? 3'd6 : (k == 1) ? 3'd7 : 3'd1;  // 三角形
        endcase
    endfunction

    // ------------------------------------------------------------------
    // Moments of the first OWN shown objects: a scan over (slot, detector
    // entry) pairs, one per clock, copies the moments of the entry with the
    // same box (a whole scan takes OWN * MAX_OBJECTS clocks).
    reg [11:0] m_cx [0:OWN-1];       // centroid x 4 (quarter samples)
    reg [10:0] m_cy [0:OWN-1];
    reg [17:0] m_ka [0:OWN-1];
    reg [17:0] m_kb [0:OWN-1];
    reg        m_kn [0:OWN-1];       // 1: m11 < 0, kb is added
    reg [17:0] m_kc [0:OWN-1];
    reg [OWN-1:0] m_ok;
    reg [3:0]  sc_i, sc_i_d;
    reg [4:0]  sc_j;
    reg        sc_hit_d;
    assign     mom_raddr = sc_j;
    wire [37:0] sc_box = obj_data[sc_i*41 +: 38];
    wire [37:0] sc_det = det_data[sc_j*41 +: 38];
    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sc_i <= 0; sc_j <= 0; sc_i_d <= 0; sc_hit_d <= 0; m_ok <= 0;
            for (k = 0; k < OWN; k = k + 1) begin
                m_cx[k] <= 0; m_cy[k] <= 0; m_ka[k] <= 0; m_kb[k] <= 0; m_kn[k] <= 0; m_kc[k] <= 0;
            end
        end else begin
            // mom_q of entry sc_j arrives one clock later
            sc_hit_d <= {1'b0, sc_j} < det_count && sc_box == sc_det;
            sc_i_d <= sc_i;
            if (sc_hit_d) begin
                m_cx[sc_i_d] <= mom_q[77:66];
                m_cy[sc_i_d] <= mom_q[65:55];
                m_ka[sc_i_d] <= mom_q[54:37];
                m_kn[sc_i_d] <= mom_q[36];
                m_kb[sc_i_d] <= mom_q[35:18];
                m_kc[sc_i_d] <= mom_q[17:0];
                m_ok[sc_i_d] <= 1'b1;
            end
            if (sc_j == MAX_OBJECTS - 1) begin
                sc_j <= 0;
                sc_i <= (sc_i == OWN - 1) ? 4'd0 : sc_i + 4'd1;
            end else sc_j <= sc_j + 5'd1;
        end
    end

    // Distance pipeline (parallel to stage 1 and three delay stages), in
    // doubled screen coordinates (centre of detector sample i is 4i + 1):
    // a: dX = 2x - cx2, dY;  b: dX^2, dY^2, dX*dY;
    // c: ka*dX^2, kb*dX*dY, kc*dY^2;  d: q = ka dX^2 -+ kb dX dY + kc dY^2
    // (2^26 on the moment ellipse of a solid ellipse).
    reg signed [13:0] own_dx [0:OWN-1];
    reg signed [12:0] own_dy [0:OWN-1];
    reg [26:0] own_xx [0:OWN-1];
    reg [24:0] own_yy [0:OWN-1];
    reg signed [26:0] own_xy [0:OWN-1];
    reg [44:0] own_ta [0:OWN-1];
    reg [42:0] own_tc [0:OWN-1];
    reg signed [45:0] own_tb [0:OWN-1];
    reg [46:0] own_q  [0:OWN-1];
    reg signed [47:0] qs;
    always @(posedge clk) begin
        for (k = 0; k < OWN; k = k + 1) begin
            own_dx[k] <= $signed({2'b00, x, 1'b0}) - $signed({2'b00, m_cx[k]}) - (2 * X_OFF + 1);
            own_dy[k] <= $signed({2'b00, y, 1'b0}) - $signed({2'b00, m_cy[k]}) - (2 * Y_OFF + 1);
            own_xx[k] <= own_dx[k] * own_dx[k];
            own_yy[k] <= own_dy[k] * own_dy[k];
            own_xy[k] <= own_dx[k] * own_dy[k];
            own_ta[k] <= own_xx[k] * m_ka[k];
            own_tc[k] <= own_yy[k] * m_kc[k];
            own_tb[k] <= own_xy[k] * $signed({1'b0, m_kb[k]});
            qs = $signed({3'b000, own_ta[k]}) + $signed({5'b00000, own_tc[k]}) +
                 (m_kn[k] ? $signed({{2{own_tb[k][45]}}, own_tb[k]})
                          : -$signed({{2{own_tb[k][45]}}, own_tb[k]}));
            own_q[k] <= qs[47] ? 47'd0 : qs[46:0];
        end
    end

    // ------------------------------------------------------------------
    // Stage 1: per-object outline hits and per-label box hits.
    reg [MAX_OBJECTS-1:0] hit1;
    reg [LABELS-1:0]      lab1;
    reg [10:0] x1r;
    reg [9:0]  y1r;
    reg        v1, h1, d1;
    reg        edge_prev, edge1, edge2;
    reg [23:0] rgb1;
    wire       show_labels = obj_count <= LABELS;
    integer i;
    reg [10:0] bx0, bx1, lx, lw;
    reg [9:0]  by0, by1, ly;
    reg [2:0]  bc;
    always @(posedge clk) begin
        for (i = 0; i < MAX_OBJECTS; i = i + 1) begin
            bc  = obj_data[i*41+38 +: 3];
            bx0 = {obj_data[i*41+28 +: 10], 1'b0} + X_OFF;
            bx1 = {obj_data[i*41+18 +: 10], 1'b1} + X_OFF;
            by0 = {obj_data[i*41+9 +: 9], 1'b0} + Y_OFF;
            by1 = {obj_data[i*41 +: 9], 1'b1} + Y_OFF;
            // inside the box, 4 pixels of margin for the edge line
            hit1[i] <= enable && i < obj_count &&
                       x + 11'd4 >= bx0 && x <= bx1 + 11'd4 && y + 10'd4 >= by0 && y <= by1 + 10'd4;
        end
        for (i = 0; i < LABELS; i = i + 1) begin
            bc  = obj_data[i*41+38 +: 3];
            lx  = {obj_data[i*41+28 +: 10], 1'b0} + X_OFF;
            by0 = {obj_data[i*41+9 +: 9], 1'b0} + Y_OFF;
            by1 = {obj_data[i*41 +: 9], 1'b1} + Y_OFF;
            ly  = (by0 >= 10'd26) ? by0 - 10'd26 : by1 + 10'd4;
            lw  = (cls_len(bc) == 2'd2) ? 11'd64 : 11'd44;
            lab1[i] <= enable && show_labels && i < obj_count &&
                       x >= lx && x < lx + lw && y >= ly && y < ly + 10'd22;
        end
        x1r <= x; y1r <= y;
        edge_prev <= edge_in;
        edge1 <= edge_in || edge_prev;
        v1 <= vs_in; h1 <= hs_in; d1 <= de_in;
        rgb1 <= rgb_in;
    end

    // Three delay stages so stage 2 meets the ownership distances (own_q is
    // registered three clocks after the pixel, like hit1c).
    reg [MAX_OBJECTS-1:0] hit1b, hit1x, hit1c;
    reg [LABELS-1:0]      lab1b, lab1x, lab1c;
    reg [10:0] x1b, x1x, x1c;
    reg [9:0]  y1b, y1x, y1c;
    reg        v1b, v1x, v1c, h1b, h1x, h1c, d1b, d1x, d1c;
    reg        edge1b, edge1x, edge1c;
    reg [23:0] rgb1b, rgb1x, rgb1c;
    always @(posedge clk) begin
        hit1b <= hit1; hit1x <= hit1b; hit1c <= hit1x;
        lab1b <= lab1; lab1x <= lab1b; lab1c <= lab1x;
        x1b <= x1r; x1x <= x1b; x1c <= x1x;
        y1b <= y1r; y1x <= y1b; y1c <= y1x;
        v1b <= v1; v1x <= v1b; v1c <= v1x;
        h1b <= h1; h1x <= h1b; h1c <= h1x;
        d1b <= d1; d1x <= d1b; d1c <= d1x;
        edge1b <= edge1; edge1x <= edge1b; edge1c <= edge1x;
        rgb1b <= rgb1; rgb1x <= rgb1b; rgb1c <= rgb1x;
    end

    // Stage 2: owner of the pixel (smallest moment-ellipse distance among the
    // first OWN boxes that contain it and have moments, else the first
    // containing box); label position inside its box.
    reg        out2, txt2;
    reg [2:0]  ocls2, tcls2;
    reg [10:0] tx2;
    reg [9:0]  ty2;
    reg        v2, h2, d2;
    reg [23:0] rgb2;
    reg        found;
    reg [2:0]  fc;
    reg [10:0] flx;
    reg [9:0]  fly, fby0, fby1;
    reg [46:0] best;
    always @(posedge clk) begin
        found = 1'b0; fc = 3'd0;
        for (i = MAX_OBJECTS-1; i >= OWN; i = i - 1)
            if (hit1c[i]) begin found = 1'b1; fc = obj_data[i*41+38 +: 3]; end
        for (i = OWN-1; i >= 0; i = i - 1)
            if (hit1c[i] && !m_ok[i]) begin found = 1'b1; fc = obj_data[i*41+38 +: 3]; end
        best = {47{1'b1}};
        for (i = OWN-1; i >= 0; i = i - 1)
            if (hit1c[i] && m_ok[i] && own_q[i] <= best) begin
                found = 1'b1; fc = obj_data[i*41+38 +: 3]; best = own_q[i];
            end
        out2 <= found;
        ocls2 <= fc;
        found = 1'b0; fc = 3'd0; flx = 0; fly = 0;
        for (i = LABELS-1; i >= 0; i = i - 1)
            if (lab1c[i]) begin
                found = 1'b1;
                fc = obj_data[i*41+38 +: 3];
                flx = {obj_data[i*41+28 +: 10], 1'b0} + X_OFF;
                fby0 = {obj_data[i*41+9 +: 9], 1'b0} + Y_OFF;
                fby1 = {obj_data[i*41 +: 9], 1'b1} + Y_OFF;
                fly = (fby0 >= 10'd26) ? fby0 - 10'd26 : fby1 + 10'd4;
            end
        txt2 <= found;
        tcls2 <= fc;
        tx2 <= x1c - flx;
        ty2 <= y1c - fly;
        v2 <= v1c; h2 <= h1c; d2 <= d1c;
        edge2 <= edge1c;
        rgb2 <= rgb1c;
    end

    // Stage 3: glyph lookup and colour.
    wire [10:0] gx_all = (tx2 >= 11'd2) ? tx2 - 11'd2 : 11'd60;
    wire [1:0]  gk = (gx_all < 11'd20) ? 2'd0 : (gx_all < 11'd40) ? 2'd1 : 2'd2;
    wire [4:0]  gx = gx_all - {gk, 4'd0} - {gk, 2'd0};
    wire [4:0]  gy = ty2[4:0] - 5'd1;
    wire        in_glyph = gx_all < 11'd60 && gk <= cls_len(tcls2) && ty2 >= 10'd1 && ty2 < 10'd21;
    wire [19:0] glyph_pixels;
    shape_font_rom u_shape_font_rom (.glyph(cls_glyph(tcls2, gk)), .row(gy), .pixels(glyph_pixels));
    wire        ink = in_glyph && glyph_pixels[5'd19 - gx];
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            vs_out <= 1; hs_out <= 0; de_out <= 0; rgb_out <= 0;
        end else begin
            vs_out <= v2; hs_out <= h2; de_out <= d2;
            rgb_out <= txt2 ? (ink ? cls_rgb(tcls2) : 24'h101010) :
                       (out2 && edge2) ? cls_rgb(ocls2) : rgb2;
        end
    end
endmodule

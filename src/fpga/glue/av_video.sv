// av_video: Saturn core video (clk_sys domain) -> Analogue Pocket scaler (APF video_* on clk_pix).
//
// Clocks: clk_pix = clk_sys / 2 from the same PLL (glue/rtl/clk_pll_core.v outclk_2, rising edges on clk_sys rising
// edges; outclk_3 is the 90-degree copy for video_rgb_clock_90). It follows clk_sys through the 320 / 352 / PAL
// changes, so the core's dots map onto whole clk_pix clocks in every mode: a dot (DCLK) every 8 clk_sys = 4 clk_pix
// (320 / 352 wide) or every 4 clk_sys = 2 clk_pix (640 / 704 wide); clk_pix clocks without a new pixel are skipped.
// The pixel clock is 26.7-28.6 MHz (APF: 1-50 MHz).
//
// Scaler slots (video.json, 8): every line is sent 640 or 704 pixels wide (320 / 352 dots are sent twice), so a
// game's switch between normal and hi-res keeps its slot; height = 240 lines (NTSC) / 256 (PAL) per field, the
// 224 / 240-line modes centred in it with black lines (TV framing), interlaced modes 480 / 512 woven by the APF:
//   slot 0 640x240  1 704x240  2 640x256 (PAL)  3 704x256 (PAL)  4 640x480i  5 704x480i  6 640x512i (PAL)  7 704x512i
//   slot = {interlaced, PAL, 352/704 wide}; interlaced = the core's INTERLACE and not BOB.
// The slot is taken at VS for the frame that starts there and sent after every line of it (the APF applies it to
// the next frame: a mode change shows one frame in the previous slot).
// Interlace (INTERLACE = 1, single or double density): the APF frame feature word on VS: bit 1 interlaced, bit 2 the
// field (FIELD ^ FIELD_INV), bit 3 "last field" (LASTF: on field 1). BOB = 1 sends each field as a progressive
// frame in the 240 / 256 slots instead (no APF weave: no tear, half the lines).
// Vertical framing: the DE window opens PAD lines before the first active line (lines from VS to the first active
// line, measured on the previous field of the same parity: 18..55 lines, per parity because interlaced fields differ
// by 1 (NTSC) or 2 (PAL 240) lines; after a mode change the first field or two are framed with the old measurement,
// 19 before the first one: every field has DE lines) and lasts exactly 240 / 256 lines (fewer only if VS comes
// first: a stale measurement after a mode change): lines outside the core's active area are black. A line
// whose VBL_N changes mid-line (the VDP2's half-line phase shifts when HRESO changes mid-line in a field: the field
// then has a part-black first line and one more part line at the bottom, cut in the 240 / 256-line modes) is sent
// whole, black where VBL_N is low. Horizontal: DE from the first active dot to the first inactive one: 640 / 704
// pixels (the VDP2 gives exactly 320 / 352 / 640 / 704 dots), never wider than the slot the APF applies to the
// frame (the last one announced, in an earlier frame) nor the frame's own (maxpx): after a 320 -> 352 change the
// lines are cut to 640 until the 704 slot is in force; after 352 -> 320 one frame has 640 in a 704 slot.
// APF rules kept (checked by sim/glue_av_video): single-clock VS / HS, HS >= 3 clocks after VS, DE once per line,
// skip only with DE, RGB 0 outside DE except the feature word on VS and the slot word right after DE falls.
//
// A6 (work/a6, diagnostic build 0.0.1-a6dbg, 2026-11-01), only with `define A6_DBG (without it the file is A5's): debug
// squares over the picture. The A5 registers and their logic are untouched: the squares are laid over video_rgb AFTER
// its register (output video_rgb_ov = ov_sq ? square colour : video_rgb, in front of the APF's DDIO registers, as A4's
// page did), from ov_sq / ov_c, registered at the same edge as video_rgb from the same pixel's position. Drawn while
// ovl_on (Core Settings "Debug flags" On) in the LAST 8 LINES of the DE window
// (wl < 8; in the 224-line modes these are the bottom black padding lines), 16 pixels wide (8 dots of a 320-dot line)
// every 32 pixels: square k at output pixels 32k .. 32k + 15 of the line (pc[9:5] = k, pc[4] = 0). Colours (each
// channel 0x00, 0x40 or 0xC0):
//   k = 1      displayed VDP1 frame buffer (vdp1fb_ext c_sel, live): green = FB0, blue = FB1
//   k = 2..9   sticky flags 0..7 (vdp1fb_ext dbg_flags): red = the event has happened, grey = not
//                2 FB0 queue overflow  3 FB1 queue overflow  4 display underrun  5 / 6 READ WAIT anomaly die 0 / 1
//                of PSRAM 1  7 / 8 WRITE WAIT anomaly die 0 / 1 of PSRAM 1  9 PSRAM 0 WAIT anomaly (control)
//   k = 10     FB layout echo: grey 0, green 1, blue 2, cyan 3
//   k = 11     echo: grey = write combining On and gap 1; red = combining Off; blue = gap 2; magenta = both
// The inputs are quasi-static (settings, sticky flags) or a level that changes once a field (c_sel, at the frame
// change just before line 0): 2-flop synchronisers into clk_pix (*_s0 / *_s1; first stages false-pathed in the SDC,
// as pk_settings' s0).
//
// A7d (work/a7d, 0.0.1-a7d, 2026-11-03), only with `define A7D_VSIG: the APF signalling of A7c's "PSX-style" option
// (work/a7c) as the fixed behaviour. Hardware test 7: it removes the pink, which is the Pocket scaler's own memory in
// rows the A5-A7b signalling never writes in interlaced modes. No "last field" bit (feature[3]) in the VS word; the
// end-of-line slot word also on the clock after (not after a line cut by VS); in interlaced fields a lead line before
// the window (the scaler drops a field's first line) and a pad line after it: 242 / 258 DE lines a field (even).
// Progressive frames (and BOB fields) keep 240 / 256 lines. The logic is A7c's with vsig_psx = 1, slot override Auto.
`default_nettype none
module av_video #(
    parameter FIELD_INV = 0,
    parameter LASTF     = 1
) (
    input  wire        clk_sys,
    input  wire        dclk,                 // core DCLK (one clk_sys clock per dot)
    input  wire [7:0]  r, g, b,
    input  wire        hbl_n, vbl_n, hs_n, vs_n,
    input  wire        field, interlace,
    input  wire [1:0]  hres,                 // [1] hi-res, [0] 352 / 704
    input  wire [1:0]  vres,                 // 0 224, 1 240, 2 256 lines
    input  wire        pal,
    input  wire        bob,                  // setting: interlaced fields as progressive frames
`ifdef A6_DBG
    input  wire        ovl_on,               // (A6, clk_sys) debug squares on
    input  wire [7:0]  ovl_flags,            // (A6, clk_ram) sticky flags
    input  wire        ovl_disp,             // (A6, clk_ram) displayed buffer: 0 = FB0, 1 = FB1
    input  wire [3:0]  ovl_set,              // (A6, clk_sys) settings echo {layout[1:0], wcoff, gap2}
    output wire [23:0] video_rgb_ov,         // (A6) video_rgb with the debug squares (to the APF)
`endif
    input  wire        clk_pix,
    output reg  [23:0] video_rgb  = 24'd0,
    output reg         video_de   = 1'b0,
    output reg         video_skip = 1'b0,
    output reg         video_vs   = 1'b0,
    output reg         video_hs   = 1'b0
);
    // ---------------------------------------------------------------- clk_sys: dots and sync edges as events
    reg [23:0] s_pix = 24'd0;
    reg        s_hact = 1'b0, s_vact = 1'b0, s_dbl = 1'b0, s_tog = 1'b0;
    reg        s_hs_tog = 1'b0, s_vs_tog = 1'b0, p_hs_n = 1'b1, p_vs_n = 1'b1;
    reg        s_fld = 1'b0, s_il = 1'b0, s_pal = 1'b0, s_wide = 1'b0;
    reg [1:0]  s_vres = 2'd0;
    always @(posedge clk_sys) begin
        p_hs_n <= hs_n;
        p_vs_n <= vs_n;
        if (dclk) begin
            s_pix  <= (hbl_n & vbl_n) ? {r, g, b} : 24'd0;
            s_hact <= hbl_n;
            s_vact <= vbl_n;
            s_dbl  <= ~hres[1];
            s_tog  <= ~s_tog;
        end
        if (p_hs_n & ~hs_n) s_hs_tog <= ~s_hs_tog;
        if (p_vs_n & ~vs_n) begin
            s_vs_tog <= ~s_vs_tog;
            s_fld    <= field ^ FIELD_INV[0];
            s_il     <= interlace & ~bob;
            s_pal    <= pal;
            s_wide   <= hres[0];
            s_vres   <= vres;
        end
    end

    // ---------------------------------------------------------------- clk_pix
    reg       p_tog = 1'b0, p_hs_tog = 1'b0, p_vs_tog = 1'b0;
    wire      newdot = s_tog ^ p_tog;
    wire      hs_ev  = s_hs_tog ^ p_hs_tog;
    wire      vs_ev  = s_vs_tog ^ p_vs_tog;

    // frame geometry (from the s_ values latched at VS, stable for the whole frame)
    wire       h256  = s_pal;                                   // 256-line field (PAL) or 240 (NTSC)
    wire [4:0] pad   = h256 ? (s_vres == 2'd0 ? 5'd16 : s_vres == 2'd1 ? 5'd8 : 5'd0)
                            : (s_vres == 2'd0 ? 5'd8  : 5'd0);
    wire [8:0] hgt   = h256 ? 9'd256 : 9'd240;
    reg        ann = 1'b0, ann_wide = 1'b0, a_wide = 1'b0;      // slot word sent this frame / its width / the
                                                                 // width of the last one sent (what the APF applies)
    wire [9:0] maxpx = (s_wide & a_wide) ? 10'd704 : 10'd640;
    wire [2:0] slot  = {s_il, s_pal, s_wide};

    reg [8:0] vl = 9'd0;                                         // lines since VS
    reg [5:0] meas0 = 6'd19, meas1 = 6'd19;                      // first active line after VS, per field parity
                                                                 // (19 until measured: every field gets a window)
    reg       seen = 1'b0;                                       // first active line of this field found
    reg [8:0] wl = 9'd0;                                         // lines left in the DE window
    reg       win = 1'b0;                                        // this line is in the DE window
    reg       rep = 1'b0;
    reg [9:0] pc = 10'd0;                                        // pixels sent on this line
    reg       hs_pend = 1'b0;
    reg [1:0] hs_dly = 2'd0;
    reg [1:0] vs_age = 2'd3;
`ifdef A7D_VSIG
    reg       lead = 1'b0;                                       // (A7d) this field has the lead + pad lines
    reg       de_d2 = 1'b0;                                      // (A7d) the clock after DE fell (slot word twice)
`endif

    wire [5:0] meas   = s_fld ? meas1 : meas0;
    // window opens at this line: >= 2 in every mode (meas >= 18, pad <= 16); 1 if a measurement made in a transient
    // (a VDP2 reset starts with VBL_N high) is below the padding: every field gets DE lines
    wire [8:0] wopen  = (meas > {1'b0, pad}) ? {3'd0, meas} - {4'd0, pad} : 9'd1;
    reg  [8:0] wo     = 9'd11;                                   // wopen latched at VS: this field's measurement
                                                                 // (made in it) must not move its own window
`ifdef A7D_VSIG
    wire       lead_nx = s_il & (wopen > 9'd1);                  // (A7d) interlaced field: lead + pad line
`endif
    // DE for this clk_pix clock (s_hact changes with s_tog); never with VS (a window still open at VS: stale framing
    // after a mode change, VS mid-line in interlaced field 0)
    wire       de_n   = win & s_hact & ~vs_ev;
    wire       emit   = de_n & (newdot | rep) & (pc != maxpx);
`ifdef A6_DBG
    // (A6) debug squares (header): the overlay colour of the pixel registered now (pc), 2-bit levels per channel
    reg        on_s0 = 1'b0, on_s1 = 1'b0, disp_s0 = 1'b0, disp_s1 = 1'b0;
    reg  [7:0] f_s0 = 8'd0, f_s1 = 8'd0;
    reg  [3:0] set_s0 = 4'd0, set_s1 = 4'd0;
    always @(posedge clk_pix) begin
        on_s0 <= ovl_on; f_s0 <= ovl_flags; disp_s0 <= ovl_disp; set_s0 <= ovl_set;
        on_s1 <= on_s0;  f_s1 <= f_s0;      disp_s1 <= disp_s0;  set_s1 <= set_s0;
    end
    wire       o_on = on_s1, o_disp = disp_s1;
    wire [7:0] o_f = f_s1;
    wire [3:0] o_set = set_s1;
    reg        sq;
    reg  [1:0] lr, lg, lb;
    always @* begin
        sq = 1'b0; lr = 2'd0; lg = 2'd0; lb = 2'd0;
        if (o_on && win && wl[8:3] == 6'd0 && !pc[4]) case (pc[9:5])
            5'd1: begin sq = 1'b1; if (o_disp) lb = 2'd3; else lg = 2'd3; end
            5'd2, 5'd3, 5'd4, 5'd5, 5'd6, 5'd7, 5'd8, 5'd9: begin
                sq = 1'b1;
                if (o_f[pc[7:5] - 3'd2]) lr = 2'd3; else begin lr = 2'd1; lg = 2'd1; lb = 2'd1; end
            end
            5'd10: begin
                sq = 1'b1;
                case (o_set[3:2]) 2'd0: begin lr = 2'd1; lg = 2'd1; lb = 2'd1; end 2'd1: lg = 2'd3; 2'd2: lb = 2'd3;
                                  default: begin lg = 2'd3; lb = 2'd3; end endcase
            end
            5'd11: begin
                sq = 1'b1;
                if (o_set[1:0] == 2'd0) begin lr = 2'd1; lg = 2'd1; lb = 2'd1; end
                else begin if (o_set[1]) lr = 2'd3; if (o_set[0]) lb = 2'd3; end
            end
            default: ;
        endcase
    end
    // registered with video_rgb (the s_pix branch: de_n), laid over it after the register
    reg        ov_sq = 1'b0;
    reg  [5:0] ov_c = 6'd0;
    always @(posedge clk_pix) begin ov_sq <= de_n & sq; ov_c <= {lr, lg, lb}; end
    assign video_rgb_ov = ov_sq ? {ov_c[5:4], 6'd0, ov_c[3:2], 6'd0, ov_c[1:0], 6'd0} : video_rgb;
`endif

    always @(posedge clk_pix) begin
        p_tog    <= s_tog;
        p_hs_tog <= s_hs_tog;
        p_vs_tog <= s_vs_tog;

        // dots
        if (newdot) begin
            rep      <= s_dbl & s_hact;
            if (s_hact & s_vact & ~seen) begin                  // first active dot of the field: measure
                seen <= 1'b1;
                if (s_fld) meas1 <= vl[5:0]; else meas0 <= vl[5:0];
            end
        end else
            rep <= 1'b0;
        if (emit) pc <= pc + 10'd1;

        // lines and the vertical window
        if (vs_ev) begin
`ifdef A7D_VSIG
            vl <= 9'd0; seen <= 1'b0; win <= 1'b0; wl <= 9'd0; wo <= lead_nx ? wopen - 9'd1 : wopen; lead <= lead_nx;
`else
            vl <= 9'd0; seen <= 1'b0; win <= 1'b0; wl <= 9'd0; wo <= wopen;
`endif
            if (ann) a_wide <= ann_wide;
            ann <= 1'b0;
        end else if (hs_ev) begin
            vl <= vl + 9'd1;
            pc <= 10'd0;
`ifdef A7D_VSIG
            if (vl + 9'd1 == wo) begin win <= 1'b1; wl <= lead ? hgt + 9'd1 : hgt - 9'd1; end   // (A7d) 242 with lead
`else
            if (vl + 9'd1 == wo) begin win <= 1'b1; wl <= hgt - 9'd1; end
`endif
            else if (wl != 9'd0) wl <= wl - 9'd1;
            else win <= 1'b0;
        end

        // outputs
        video_de   <= de_n;
`ifdef A7D_VSIG
        de_d2      <= video_de & ~de_n & ~vs_ev;                 // (A7d) the clock after DE fell (not at VS)
`endif
        video_skip <= de_n & ~emit;
        video_vs   <= vs_ev;
        if (vs_ev)
`ifdef A7D_VSIG
            video_rgb <= {20'd0, 1'b0, s_il & s_fld, s_il, 1'b0};   // (A7d) no "last field" bit
`else
            video_rgb <= {20'd0, LASTF[0] & s_il & s_fld, s_il & s_fld, s_il, 1'b0};
`endif
        else if (de_n)
            video_rgb <= s_pix;
`ifdef A7D_VSIG
        else if (video_de || de_d2) begin                        // (A7d) the slot word on two clocks
`else
        else if (video_de) begin
`endif
            video_rgb <= {8'd0, slot, 13'd0};                    // end of line: scaler slot
            ann <= 1'b1; ann_wide <= s_wide;
        end
        else
            video_rgb <= 24'd0;

        // HS: one clock, at least 3 clocks after VS
        video_hs <= 1'b0;
        if (vs_ev) vs_age <= 2'd0; else if (vs_age != 2'd3) vs_age <= vs_age + 2'd1;
        if (hs_ev) begin hs_pend <= 1'b1; hs_dly <= 2'd2; end
        else if (hs_dly != 2'd0) hs_dly <= hs_dly - 2'd1;
        else if (hs_pend && !vs_ev && vs_age == 2'd3 && !de_n) begin video_hs <= 1'b1; hs_pend <= 1'b0; end
    end
endmodule
`default_nettype wire

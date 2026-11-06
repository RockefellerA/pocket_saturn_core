// pk_settings: Core Settings registers of the Saturn Pocket top (work/pocket, P2), in place of MiSTer's OSD status
// bits (hps_io) for the options that apply on the Pocket, plus the real-time clock for the SMPC.
//
// APF writes the interact.json variables through the bridge (clk_74a) when they change and at start for persisted
// values; a register keeps its reset value (= the JSON default) until then. As in the sotn PSX port the value is taken
// from the low bits OR the top byte, so it does not matter whether it arrives byte-swapped (bridge_endian_little = 1).
//   0x80000000  W  action "Reset"                       any write: a 2^16 clk_74a (0.9 ms) reset pulse (MiSTer R0 =
//                                                       status[0]: the core's reset and SRES_N)
//   0x80000004  W  Cartridge (MiSTer O[23:21])          0 Auto, 1 ROM 2M, 2 DRAM 1M, 3 DRAM 4M, 4 DRAM 6M DEV,
//                                                       5 Backup, 6 None                         (reset 0 = Auto)
//   0x80000008  W  Region (MiSTer O[35:33])             0 Japan, 1 Taiwan, 2 USA, 3 Brazil, 4 Korea, 5 Asia PAL,
//                                                       6 Europe, 7 Auto                         (reset 7 = Auto)
//   0x8000000C  W  Timing (MiSTer OS)                   0 Original, 1 Fast                       (reset 0)
//   0x80000010  W  Blurred VDP1 mesh (MiSTer OV)        0 Off, 1 On                              (reset 0)
//   0x80000014  W  Deinterlacing (MiSTer O[29])         0 Weave (APF), 1 Bob                     (reset 0)
//   0x80000018  W  Pad mapping (pk_pad presets)         0..3                                     (reset 0)
//   not in interact.json, for an instance JSON's "memory_writes" (per game; MiSTer's main program takes these from
//   the disc header and its database, which the Pocket does not have; the area code is also read from the disc, below):
//   0x80000020  W  area code for Region = Auto          SMPC area code 4 bits                    (reset 0 = none:
//                                                       the disc's area, else USA)
//   0x80000024  W  cartridge for Cartridge = Auto       0..5 as above                            (reset 0 = none)
//   0x80000028  W  Dezaemon 2 RAM patch (MiSTer: on when the disc's product number is T-16804G)  (reset 0)
//   (A6, work/a6: diagnostic build 0.0.1-a6dbg, only with `define A6_DBG; interact.json ids 8-11, "persist": false, so
//   every launch starts at the reset values = the JSON defaults)
//   0x80000030  W  FB layout                            0..3 (glue/vdp1fb_ext.sv header)          (reset 0 = A5)
//   0x80000034  W  Write combining                      0 On, 1 Off (draw / CPU writes)           (reset 0 = On)
//   0x80000038  W  Debug flags                          0 On, 1 Off                               (reset 0 = On;
//                                                       A7_FIX: reset 1 = Off, interact.json defaultval 1)
//   0x8000003C  W  PSRAM gap                            0 one PSRAM cycle, 1 two                  (reset 0 = one)
//   outputs dbg_* = the clk_sys synchroniser's second stage (s1), as quasi-static as the other settings
//   (A8, work/a8, with `define A8_TRIM: Timing and the four A6 settings leave the menu, interact.json ids 4 and 8-11;
//   fast = 0 (Original) and dbg_* = the defaults (layout 0, write combining on, flags off, gap one) as constants, so
//   synthesis removes the logic behind them; writes to 0x8000000C and 0x80000030-3C are ignored)
// Derived as in MiSTer's emu: cart_type = Auto ? auto_cart : sel < 6 ? sel : 0; area_code from the region list
// (Auto -> the auto register, else the disc's area, else USA); PAL = area_code >= 0xA.
// The disc's area (disc_area, clk_sys): the CD block firmware reads it from the disc's system ID once per disc scan,
// before the disc goes in (cd_src.c disc_area(), cd_src_b AREA), so only after the core has left reset: the BIOS may
// already have read the SMPC's area code by then. A write that changes area_code (Region = Auto, no area code from
// the instance JSON) therefore resets the core once, as the Core Settings "Reset" does (2^16 clk_sys); the scan after
// that reset writes the same area again, which changes nothing. d_area is not reset by the core's reset.
// RTC: core_bridge_cmd's host command 0x0090 (rtc_valid rising, BCD date 0xYYYYMMDD / time 0x00HHMMSS) -> MiSTer's
// 65-bit RTC bus {toggle[64], 0[63:48], year[47:40], month[39:32], day[31:24], hour[23:16], min[15:8], sec[7:0]}: the
// data are registered in clk_74a one clock before the toggle flips; the toggle reaches the core (the SMPC firmware polls
// it) through a 2-flop synchroniser in clk_sys, so the data are stable whenever a change of it is seen.
// Crossings: every setting is quasi-static (written while the user is in the menu): 2-flop synchronisers per bit into
// clk_sys; the RTC data cross as stable data behind the toggle (core_constraints.sdc).
`default_nettype none
module pk_settings (
	input  wire        clk_74a,
	input  wire [31:0] bridge_addr,
	input  wire        bridge_wr,
	input  wire [31:0] bridge_wr_data,
	input  wire        rtc_valid,
	input  wire [31:0] rtc_date_bcd,
	input  wire [31:0] rtc_time_bcd,

	input  wire        clk_sys,
	input  wire [ 3:0] disc_area,          // clk_sys: the disc's SMPC area code (cd_src_b; 0: none)
	input  wire        disc_area_wr,       // clk_sys: one clock with each firmware write of it
	output reg  [ 2:0] cart_type = 3'd0,   // clk_sys: the core's CART_MODE
	output reg  [ 3:0] area_code = 4'h4,   // clk_sys: SMPC_AREA
	output reg         pal = 1'b0,         // clk_sys: PAL (core, CEGen rate select, clk_reconf mode, av_video)
	output reg         fast = 1'b0,        // clk_sys: FAST ("Timing")
	output reg         blur = 1'b0,        // clk_sys: BLUR_MESH
	output reg         bob = 1'b0,         // clk_sys: av_video BOB
	output reg  [ 1:0] padmap = 2'd0,      // clk_sys: pk_pad preset
	output reg         dz_en = 1'b0,       // clk_sys: Dezaemon 2 patch
	output wire        usr_reset,          // clk_sys: reset request
	output wire [64:0] rtc,                // [63:0] clk_74a registers (stable behind the toggle), [64] clk_sys
`ifdef A6_DBG
	output wire [ 1:0] dbg_layout,         // (A6) clk_sys: FB layout
	output wire        dbg_wcoff,          // (A6) clk_sys: 1 = write combining off
	output wire        dbg_flgoff,         // (A6) clk_sys: 1 = debug flags off
	output wire        dbg_gap2,           // (A6) clk_sys: 1 = PSRAM gap of two cycles
`endif
	output wire [ 2:0] cart_type_74        // clk_74a: cart_type as set (pk_save: backup cartridge slot size)
);
	// ---------------------------------------------------------------- clk_74a registers
	reg  [2:0] r_cart = 3'd0, r_region = 3'd7, r_acart = 3'd0;
	reg  [3:0] r_aarea = 4'h0;             // (0: not written, the disc's area)
	reg        r_fast = 1'b0, r_blur = 1'b0, r_bob = 1'b0, r_dz = 1'b0;
	reg  [1:0] r_pad = 2'd0;
	reg [16:0] r_rst = 17'd0;              // [16]: reset pulse running
`ifdef A6_DBG
	reg  [1:0] r_lay = 2'd0;               // (A6)
`ifdef A7_FIX
	localparam bit FLG_OFF0 = 1'b1;        // (A7) "Debug flags" Off at start (the squares hidden until switched On)
`else
	localparam bit FLG_OFF0 = 1'b0;
`endif
	reg        r_wcoff = 1'b0, r_flgoff = FLG_OFF0, r_gap2 = 1'b0;
`endif
	wire [7:0] v = bridge_wr_data[7:0] | bridge_wr_data[31:24];
	always @(posedge clk_74a) begin
		if (r_rst[16]) r_rst <= r_rst + 17'd1;
		if (bridge_wr && bridge_addr[31:8] == 24'h800000) case (bridge_addr[7:2])
			6'h00: r_rst <= 17'h10000;
			6'h01: r_cart <= v[2:0];
			6'h02: r_region <= v[2:0];
`ifndef A8_TRIM
			6'h03: r_fast <= v[0];
`endif
			6'h04: r_blur <= v[0];
			6'h05: r_bob <= v[0];
			6'h06: r_pad <= v[1:0];
			6'h08: r_aarea <= v[3:0];
			6'h09: r_acart <= v[2:0];
			6'h0A: r_dz <= v[0];
`ifdef A6_DBG
`ifndef A8_TRIM
			6'h0C: r_lay <= v[1:0];
			6'h0D: r_wcoff <= v[0];
			6'h0E: r_flgoff <= v[0];
			6'h0F: r_gap2 <= v[0];
`endif
`endif
			default: ;
		endcase
	end
	wire [2:0] ct74 = (r_cart == 3'd0) ? r_acart : (r_cart < 3'd6) ? r_cart : 3'd0;
	assign cart_type_74 = ct74;

	// RTC: data first, then the toggle (one clk_74a later)
	reg [47:0] rtc_d = 48'd0;
	reg        rtc_tgl = 1'b0;
	reg rtc_v1 = 1'b0, rtc_tgl_pend = 1'b0;
	always @(posedge clk_74a) begin
		rtc_v1 <= rtc_valid;
		rtc_tgl_pend <= 1'b0;
		if (rtc_valid && !rtc_v1) begin
			rtc_d <= {rtc_date_bcd[23:16], rtc_date_bcd[15:8], rtc_date_bcd[7:0],
			          rtc_time_bcd[23:16], rtc_time_bcd[15:8], rtc_time_bcd[7:0]};
			rtc_tgl_pend <= 1'b1;
		end
		if (rtc_tgl_pend) rtc_tgl <= ~rtc_tgl;
	end
	reg [1:0] rtc_tgl_s = 2'b00;
	always @(posedge clk_sys) rtc_tgl_s <= {rtc_tgl_s[0], rtc_tgl};
	assign rtc = {rtc_tgl_s[1], 16'h0000, rtc_d};

	// ---------------------------------------------------------------- clk_sys: 2-flop synchronisers, derived values
	// {rst [19], region [18:16], cart [15:13], fast [12], blur [11], bob [10], pad [9:8], auto area [7:4],
	//  auto cart [3:1], dz [0]}
`ifdef A6_DBG
	// (A6) {layout [24:23], wcoff [22], flgoff [21], gap2 [20], then the bits above at [19:0]}
	localparam [24:0] S_INIT = {2'd0, 1'b0, FLG_OFF0, 1'b0, 1'b0, 3'd7, 3'd0, 1'b0, 1'b0, 1'b0, 2'd0, 4'h0, 3'd0, 1'b0};   // (A7: FLG_OFF0)
	reg [24:0] s0 = S_INIT, s1 = S_INIT;
	always @(posedge clk_sys) begin
		s0 <= {r_lay, r_wcoff, r_flgoff, r_gap2, r_rst[16], r_region, r_cart, r_fast, r_blur, r_bob, r_pad, r_aarea, r_acart, r_dz};
		s1 <= s0;
	end
`ifdef A8_TRIM
	assign dbg_layout = 2'd0;                // (A8) the defaults as constants
	assign dbg_wcoff  = 1'b0;
	assign dbg_flgoff = 1'b1;
	assign dbg_gap2   = 1'b0;
`else
	assign dbg_layout = s1[24:23];
	assign dbg_wcoff  = s1[22];
	assign dbg_flgoff = s1[21];
	assign dbg_gap2   = s1[20];
`endif
`else
	localparam [19:0] S_INIT = {1'b0, 3'd7, 3'd0, 1'b0, 1'b0, 1'b0, 2'd0, 4'h0, 3'd0, 1'b0};
	reg [19:0] s0 = S_INIT, s1 = S_INIT;
	always @(posedge clk_sys) begin
		s0 <= {r_rst[16], r_region, r_cart, r_fast, r_blur, r_bob, r_pad, r_aarea, r_acart, r_dz};
		s1 <= s0;
	end
`endif
	wire [2:0] s_region = s1[18:16], s_cart = s1[15:13], s_acart = s1[3:1];
	wire [3:0] s_aarea = s1[7:4];

	// the disc's area (kept across the core's resets) and the one reset when it changes area_code
	reg  [ 3:0] d_area = 4'h0;
	reg  [16:0] d_rst = 17'd0;             // [16]: the reset pulse running
	wire [ 3:0] auto_area = (s_aarea != 4'h0) ? s_aarea : (d_area != 4'h0) ? d_area : 4'h4;   // (USA: no area)
	always @(posedge clk_sys) begin
		if (d_rst[16]) d_rst <= d_rst + 17'd1;
		if (disc_area_wr) begin
			d_area <= disc_area;
			if (s_region == 3'd7 && s_aarea == 4'h0 && disc_area != 4'h0 && disc_area != area_code) d_rst <= 17'h10000;
		end
	end
	assign usr_reset = s1[19] | d_rst[16];

	always @(posedge clk_sys) begin
`ifdef A8_TRIM
		fast   <= 1'b0;                        // (A8) Timing = Original
`else
		fast   <= s1[12];
`endif
		blur   <= s1[11];
		bob    <= s1[10];
		padmap <= s1[9:8];
		dz_en  <= s1[0];
		cart_type <= (s_cart == 3'd0) ? s_acart : (s_cart < 3'd6) ? s_cart : 3'd0;
		case (s_region)
			3'd0: area_code <= 4'h1;           // Japan
			3'd1: area_code <= 4'h2;           // Asia NTSC (Taiwan)
			3'd2: area_code <= 4'h4;           // North America
			3'd3: area_code <= 4'h5;           // Central / South America NTSC (Brazil)
			3'd4: area_code <= 4'h6;           // Korea
			3'd5: area_code <= 4'hA;           // Asia PAL
			3'd6: area_code <= 4'hC;           // Europe PAL
			default: area_code <= auto_area;   // Auto
		endcase
		pal <= area_code >= 4'hA;
	end
endmodule
`default_nettype wire

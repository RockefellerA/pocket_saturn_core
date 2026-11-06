// saturn_top: the Analogue Pocket's replacement for MiSTer's emu (Saturn_MiSTer/Saturn.sv) (work/pocket, P2).
//
// The core (rtl/Saturn/Saturn.sv, macros VDP1_FB_EXT + CD_EXTIO + the harness set) is hooked up as emu does it:
// RAMH_SLOW = 1, the CEGens (SCSP x2 with the four clk_sys rates, SMPC, CD), SYS_CE from MCLK_DIV, sdram1 for VDP2
// VRAM + SCSP RAM, the MEM_* / VDP1 VRAM / CD RAM / cartridge ports on the DDR3-type memory, HPS2PAD on port 1, the
// SMPC area code / RTC / TIME_SET inputs, FAST / BLUR_MESH, the debug inputs tied off. MiSTer's platform blocks are
// replaced (glue/REPORT.txt, decisions D2-D9 as fixed for P2):
//   pll + pll_cfg        -> clk_pll_core (one reconfigurable PLL) + clk_reconf (DPRIO writer, all four modes) (D6 a)
//   ddram.sv + DDR3      -> psram0_arb on PSRAM 0 (work/pocket/rtl copy: flush input, LEAN switch off)  (D2, D3, D4)
//   vdp1_fb (M10K + DDR3) -> vdp1fb_ext: FB0 = SRAM, FB1 = PSRAM 1, PS_BWC = 1 (D1 g)                   (D5: core's fetch)
//   HPS2SEC              -> cd_src_b (design B2: EXT port registers, APF crossing, 6-slot ring, streamer) (D9)
//   video_freak / mixer / cofi -> av_video (clk_pix = clk_sys / 2 + video_skip; APF weave or bob)       (D8)
//                           + av_blank (black frames while av_video sends none: core reset, VDP2 held)
//   audio_out            -> sound_i2s in core_top: sample and hold (D7; glue's av_audio48 INTERP = 0 is only a
//                           register stage in front of it, left out: P2 report, "glue savings")
//   hps_io status / joystick / ioctl / sd -> pk_settings, pk_pad, pk_loader, pk_save, pk_reset (work/pocket/rtl)
// Clock domains: clk_sys (core, CEGens, video in, audio, CD source, pad, settings), clk_ram = 2 x clk_sys from the
// same PLL, phase aligned (sdram1, psram0_arb, vdp1fb_ext, loader / save drains), clk_pix = clk_sys / 2 (video out),
// clk_74a (APF bridge side of everything, clk_reconf). Crossings: see work/pocket/src/fpga/core/core_constraints.sdc.
// A6 (work/a6, diagnostic build 0.0.1-a6dbg, 2026-11-01), only with `define A6_DBG (without it the file is A5's): the
// four Core Settings options of pk_settings (FB layout, write combining, debug flags, PSRAM gap) go to vdp1fb_ext (and
// the echo squares), vdp1fb_ext's sticky flags and displayed-buffer bit to av_video's debug squares; the flags are
// cleared at power-on and while "Debug flags" is Off. Nothing else changes.
`default_nettype none
module saturn_top #(
	parameter bit ARB_LEAN = 1'b0          // D4: psram0_arb lean option (default off)
) (
	input  wire        clk_74a,

	// APF bridge (clk_74a)
	input  wire [31:0] bridge_addr,
	input  wire        bridge_wr,
	input  wire [31:0] bridge_wr_data,
	input  wire        bridge_rd,
	output wire [31:0] save_rd_data,       // bridge read data for the save windows 0x1xxxxxxx / 0x2xxxxxxx

	// core_bridge_cmd (clk_74a)
	input  wire        apf_reset_n,
	input  wire        ds_requestwrite,
	input  wire        ds_allcomplete,
	input  wire        rtc_valid,
	input  wire [31:0] rtc_date_bcd,
	input  wire [31:0] rtc_time_bcd,
	output wire [ 9:0] datatable_addr,
	output wire        datatable_wren,
	output wire [31:0] datatable_data,
	input  wire [31:0] datatable_q,
	output wire        dsr_read,
	output wire [15:0] dsr_id,
	output wire [31:0] dsr_offset,
	output wire [31:0] dsr_bridgeaddr,
	output wire [31:0] dsr_length,
	input  wire        dsr_done,
	input  wire [ 2:0] dsr_err,
	output wire        boot_done,
	input  wire [15:0] cont1_key,

	// PSRAM 0 (cram0)
	output wire [21:16] cram0_a,
	output wire [15:0] cram0_dq_out,
	output wire        cram0_dq_oe,
	input  wire [15:0] cram0_dq_in,
	output wire        cram0_clk,
	output wire        cram0_adv_n,
	output wire        cram0_cre,
	output wire        cram0_ce0_n,
	output wire        cram0_ce1_n,
	output wire        cram0_oe_n,
	output wire        cram0_we_n,
	output wire        cram0_ub_n,
	output wire        cram0_lb_n,
	input  wire        cram0_wait,
	// PSRAM 1 (cram1)
	output wire [21:16] cram1_a,
	output wire [15:0] cram1_dq_out,
	output wire        cram1_dq_oe,
	input  wire [15:0] cram1_dq_in,
	output wire        cram1_clk,
	output wire        cram1_adv_n,
	output wire        cram1_cre,
	output wire        cram1_ce0_n,
	output wire        cram1_ce1_n,
	output wire        cram1_oe_n,
	output wire        cram1_we_n,
	output wire        cram1_ub_n,
	output wire        cram1_lb_n,
	input  wire        cram1_wait,
	// SRAM
	output wire [16:0] sram_a,
	output wire [15:0] sram_dq_out,
	output wire        sram_dq_oe,
	input  wire [15:0] sram_dq_in,
	output wire        sram_oe_n,
	output wire        sram_we_n,
	output wire        sram_ub_n,
	output wire        sram_lb_n,
	// SDRAM
	output wire [12:0] dram_a,
	output wire [ 1:0] dram_ba,
	inout  wire [15:0] dram_dq,
	output wire [ 1:0] dram_dqm,
	output wire        dram_clk,
	output wire        dram_cke,
	output wire        dram_ras_n,
	output wire        dram_cas_n,
	output wire        dram_we_n,

	// video (clk_pix) and audio (clk_sys)
	output wire        clk_pix,
	output wire        clk_pix_90,
	output wire [23:0] video_rgb,
	output wire        video_de,
	output wire        video_skip,
	output wire        video_vs,
	output wire        video_hs,
	output wire        clk_audio,
	output wire [15:0] audio_l,
	output wire [15:0] audio_r
);
	// ============================================================================================== clocks
	wire        clk_sys, clk_ram;
	wire [63:0] to_pll, from_pll;
	wire        rc_busy, rc_locked;
	wire        PAL, SMPC_DOTSEL;
	clk_pll_core ipll (
		.refclk(clk_74a), .rst(1'b0), .clk_sys(clk_sys), .clk_ram(clk_ram), .clk_pix(clk_pix),
		.clk_pix_90(clk_pix_90), .clk_ram_rd(), .locked(), .reconfig_to_pll(to_pll), .reconfig_from_pll(from_pll)
	);
	// mode as the core gives it ({PAL, SMPC_DOTSEL}, clk_sys), 3-flop synchronised inside the writer (clk_74a)
	reg  [1:0] pll_mode = 2'b00;
	always @(posedge clk_sys) pll_mode <= {PAL, SMPC_DOTSEL};
	clk_reconf irec (
		.clk(clk_74a), .mode(pll_mode), .reconfig_to_pll(to_pll), .reconfig_from_pll(from_pll),
		.busy(rc_busy), .locked(rc_locked)
	);
	assign clk_audio = clk_sys;

	// ============================================================================================== resets, settings
	wire        por_ram, rst_sys, rst_ram, flush_ram, held_74, loading_74, usr_reset;
	wire        ps0_ready, ps1_ready, ld_busy;
`ifdef A7_FIX
	wire        ps1_cfg;                   // (A7b) clk_ram: PSRAM 1 configured (its frame-buffer clear may still run)
`endif
	wire [ 2:0] cart_type, cart_type_74;
	wire [ 3:0] area_code;
	wire        set_fast, set_blur, set_bob, set_dz;
	wire [ 1:0] set_padmap;
	wire [64:0] RTC;
`ifdef A6_DBG
	wire [ 1:0] set_lay;                   // (A6) clk_sys settings
	wire        set_wcoff, set_flgoff, set_gap2;
	wire [ 7:0] dbg_flags;                 // (A6) clk_ram: vdp1fb_ext sticky flags
	wire        dbg_wait0;                 // (A6) clk_ram: PSRAM 0's WAIT anomaly pulse
	wire        dbg_disp;                  // (A6) clk_ram: the displayed VDP1 buffer
`endif
	pk_reset irst (
		.clk_74a(clk_74a), .clk_sys(clk_sys), .clk_ram(clk_ram), .rc_locked(rc_locked), .rc_busy(rc_busy),
		.ps_ready(ps0_ready & ps1_ready), .apf_reset_n(apf_reset_n), .ds_requestwrite(ds_requestwrite),
		.ds_allcomplete(ds_allcomplete), .ld_busy(ld_busy), .usr_reset(usr_reset), .por_ram(por_ram),
		.boot_done(boot_done), .rst_sys(rst_sys), .rst_ram(rst_ram), .flush(flush_ram), .held_74(held_74),
		.loading_74(loading_74)
`ifdef A7_FIX
		, .ps_cfg(ps0_ready & ps1_cfg)   // (A7b) boot_done: both PSRAMs configured (A6's ps_ready), not the FB clear
`endif
	);
	pk_settings iset (
		.clk_74a(clk_74a), .bridge_addr(bridge_addr), .bridge_wr(bridge_wr), .bridge_wr_data(bridge_wr_data),
		.rtc_valid(rtc_valid), .rtc_date_bcd(rtc_date_bcd), .rtc_time_bcd(rtc_time_bcd),
		.clk_sys(clk_sys), .cart_type(cart_type), .area_code(area_code), .pal(PAL), .fast(set_fast), .blur(set_blur),
		.bob(set_bob), .padmap(set_padmap), .dz_en(set_dz), .usr_reset(usr_reset), .rtc(RTC), .cart_type_74(cart_type_74)
`ifdef A6_DBG
		, .dbg_layout(set_lay), .dbg_wcoff(set_wcoff), .dbg_flgoff(set_flgoff), .dbg_gap2(set_gap2)
`endif
	);

	// ============================================================================================== clock enables (emu)
	reg MCLK_DIV = 1'b0;
	always @(posedge clk_sys) MCLK_DIV <= ~MCLK_DIV;
	wire SYS_CE_R =  MCLK_DIV;
	wire SYS_CE_F = ~MCLK_DIV;

	// clk_sys rate: 53748200 (NTSC) / 57272800 (NTSC, SMPC_DOTSEL) / 53375000 (PAL) / 56875000 (PAL, SMPC_DOTSEL)
	reg [1:0] in_sel = 2'b00;
	reg       in_ok = 1'b0;
	always @(posedge clk_sys) begin
		in_sel <= {PAL, SMPC_DOTSEL};
		in_ok <= 1'b1;
	end
	wire SCSP_2X_CE;
	CEGen #(.OUT_CLK(22579200*2), .IN_CLK0(53748200), .IN_CLK1(57272800), .IN_CLK2(53375000), .IN_CLK3(56875000)) SCSP_CEGen (
		.CLK(clk_sys), .RST_N(1'b1), .IN_SEL(in_sel), .IN_OK(in_ok), .IN_CE(1'b1), .CE(SCSP_2X_CE)
	);
	reg SCSP_DIV = 1'b0;
	always @(posedge clk_sys) if (SCSP_2X_CE) SCSP_DIV <= ~SCSP_DIV;
	wire SCSP_CE = SCSP_2X_CE & SCSP_DIV;   // SCSP clock 22.5792 MHz
	wire SMPC_CE;                           // SMPC clock 4.0000 MHz
	CEGen #(.OUT_CLK(4000000), .IN_CLK0(22579200*2)) SMPC_CEGen (
		.CLK(clk_sys), .RST_N(1'b1), .IN_SEL(2'b00), .IN_OK(1'b1), .IN_CE(SCSP_2X_CE), .CE(SMPC_CE)
	);
	wire CD_CE;                             // CD clock 20.000 MHz
	CEGen #(.OUT_CLK(20000000*2), .IN_CLK0(22579200*2)) CD_CEGen (
		.CLK(clk_sys), .RST_N(1'b1), .IN_SEL(2'b00), .IN_OK(1'b1), .IN_CE(SCSP_2X_CE), .CE(CD_CE)
	);

	// ============================================================================================== the core
	wire [24:0] MEM_A;
	wire [31:0] MEM_DI, MEM_DO;
	wire        ROM_CS_N, SRAM_CS_N, RAML_CS_N, RAMH_CS_N, MEM_RD_N, MEM_WAIT_N;
	wire [ 3:0] MEM_DQM_N;
	wire [18:1] VDP1_VRAM_A;
	wire [15:0] VDP1_VRAM_D, VDP1_VRAM_Q;
	wire [ 1:0] VDP1_VRAM_WE;
	wire        VDP1_VRAM_RD, VDP1_VRAM_RDY;
	wire [ 8:0] VDP1_VRAM_BLEN;
	wire [17:1] VDP1_FBD_A, VDP1_FBV_A;
	wire [15:0] VDP1_FBD_D, VDP1_FBD_Q, VDP1_FBV_Q, VDP1_FBE_D;
	wire [ 1:0] VDP1_FBD_WE;
	wire        VDP1_FBD_RD, VDP1_FBE_WE, VDP1_FB_SEL, VDP1_FBV_VB, VDP1_FB_RDY;
	wire [18:1] VDP2_RA0_A, VDP2_RB0_A;
	wire [16:1] VDP2_RA1_A, VDP2_RB1_A;
	wire [63:0] VDP2_RA_D, VDP2_RB_D;
	wire [ 7:0] VDP2_RA_WE, VDP2_RB_WE;
	wire        VDP2_RA_RD, VDP2_RB_RD;
	wire [31:0] VDP2_RA0_Q, VDP2_RA1_Q, VDP2_RB0_Q, VDP2_RB1_Q;
	wire [18:1] SCSP_RAM_A;
	wire [15:0] SCSP_RAM_D, SCSP_RAM_Q;
	wire [ 1:0] SCSP_RAM_WE;
	wire        SCSP_RAM_RD, SCSP_RAM_CS, SCSP_RAM_RDY;
	wire [ 6:0] SMPC_PDR1I, SMPC_PDR1O, SMPC_DDR1, SMPC_PDR2I, SMPC_PDR2O, SMPC_DDR2;
	wire        CD_DISC_IN, CD_SEC_REQ, CD_SEC_WR, CD_SEC_WAIT;
	wire [23:0] CD_SEC_LBA;
	wire [15:0] CD_SEC_DATA;
	wire [ 2:0] CD_EXT_A;
	wire        CD_EXT_WE;
	wire [31:0] CD_EXT_WD, CD_EXT_RD;
	wire [18:1] CD_RAM_A;
	wire [15:0] CD_RAM_D, CD_RAM_Q;
	wire [ 1:0] CD_RAM_WE;
	wire        CD_RAM_RD, CD_RAM_CS, CD_RAM_RDY;
	wire [25:1] CART_MEM_A;
	wire [15:0] CART_MEM_D, CART_MEM_Q;
	wire [ 1:0] CART_MEM_WE;
	wire        CART_MEM_RD, CART_MEM_RDY;
	wire [ 7:0] R, G, B;
	wire        DCLK, HS_N, VS_N, HBL_N, VBL_N, FIELD, INTERLACE, DCE_R;
	wire [ 1:0] HRES, VRES;
	wire [15:0] SOUND_L, SOUND_R;

	Saturn #(.RAMH_SLOW(1)) saturn (
		.CLK(clk_sys),
		.RST_N(~rst_sys),
		.EN(1'b1),                                         // emu: ~DBG_PAUSE (0 outside DEBUG builds)
		.SYS_CE_F(SYS_CE_F),
		.SYS_CE_R(SYS_CE_R),
		.SRES_N(~usr_reset),                               // emu: ~status[0]
		.PAL(PAL),

		.MEM_A(MEM_A), .MEM_DI(MEM_DI), .MEM_DO(MEM_DO), .MEM_DQM_N(MEM_DQM_N),
		.ROM_CS_N(ROM_CS_N), .SRAM_CS_N(SRAM_CS_N), .RAML_CS_N(RAML_CS_N), .RAMH_CS_N(RAMH_CS_N),
		.RAMH_BURST(), .RAMH_RFS(),                        // (emu: unused)
		.MEM_RD_N(MEM_RD_N), .MEM_WAIT_N(MEM_WAIT_N),

		.VDP1_VRAM_A(VDP1_VRAM_A), .VDP1_VRAM_D(VDP1_VRAM_D), .VDP1_VRAM_WE(VDP1_VRAM_WE), .VDP1_VRAM_RD(VDP1_VRAM_RD),
		.VDP1_VRAM_BLEN(VDP1_VRAM_BLEN), .VDP1_VRAM_Q(VDP1_VRAM_Q), .VDP1_VRAM_RDY(VDP1_VRAM_RDY),
		.VDP1_FBD_A(VDP1_FBD_A), .VDP1_FBD_D(VDP1_FBD_D), .VDP1_FBD_WE(VDP1_FBD_WE), .VDP1_FBD_RD(VDP1_FBD_RD),
		.VDP1_FBD_Q(VDP1_FBD_Q), .VDP1_FBV_A(VDP1_FBV_A), .VDP1_FBV_Q(VDP1_FBV_Q), .VDP1_FBE_WE(VDP1_FBE_WE),
		.VDP1_FBE_D(VDP1_FBE_D), .VDP1_FB_SEL(VDP1_FB_SEL), .VDP1_FBV_VB(VDP1_FBV_VB),
		.VDP1_FB_RDY(VDP1_FB_RDY), .VDP1_FB_MODE3(),       // (constant 0 with VDP1_FB_EXT)

		.VDP2_RA0_A(VDP2_RA0_A), .VDP2_RA1_A(VDP2_RA1_A), .VDP2_RA_D(VDP2_RA_D), .VDP2_RA_WE(VDP2_RA_WE),
		.VDP2_RA_RD(VDP2_RA_RD), .VDP2_RA0_Q(VDP2_RA0_Q), .VDP2_RA1_Q(VDP2_RA1_Q),
		.VDP2_RB0_A(VDP2_RB0_A), .VDP2_RB1_A(VDP2_RB1_A), .VDP2_RB_D(VDP2_RB_D), .VDP2_RB_WE(VDP2_RB_WE),
		.VDP2_RB_RD(VDP2_RB_RD), .VDP2_RB0_Q(VDP2_RB0_Q), .VDP2_RB1_Q(VDP2_RB1_Q),

		.SCSP_CE(SCSP_CE), .SCSP_RAM_A(SCSP_RAM_A), .SCSP_RAM_D(SCSP_RAM_D), .SCSP_RAM_WE(SCSP_RAM_WE),
		.SCSP_RAM_RD(SCSP_RAM_RD), .SCSP_RAM_CS(SCSP_RAM_CS), .SCSP_RAM_Q(SCSP_RAM_Q), .SCSP_RAM_RFS(),
		.SCSP_RAM_RDY(SCSP_RAM_RDY),

		.SMPC_CE(SMPC_CE), .TIME_SET(1'b1),                // emu: ~status[32] (status[32] is not in the CONF_STR: 1)
		.RTC(RTC), .SMPC_AREA(area_code), .SMPC_DOTSEL(SMPC_DOTSEL),
		.SMPC_PDR1I(SMPC_PDR1I), .SMPC_PDR1O(SMPC_PDR1O), .SMPC_DDR1(SMPC_DDR1),
		.SMPC_PDR2I(SMPC_PDR2I), .SMPC_PDR2O(SMPC_PDR2O), .SMPC_DDR2(SMPC_DDR2),

		.CD_CE(CD_CE),
		.CD_DISC_IN(CD_DISC_IN), .CD_SEC_REQ(CD_SEC_REQ), .CD_SEC_LBA(CD_SEC_LBA), .CD_SEC_WR(CD_SEC_WR),
		.CD_SEC_DATA(CD_SEC_DATA), .CD_SEC_WAIT(CD_SEC_WAIT),
		.CD_EXT_A(CD_EXT_A), .CD_EXT_WE(CD_EXT_WE), .CD_EXT_WD(CD_EXT_WD), .CD_EXT_RD(CD_EXT_RD),
		.CD_RAM_A(CD_RAM_A), .CD_RAM_D(CD_RAM_D), .CD_RAM_WE(CD_RAM_WE), .CD_RAM_RD(CD_RAM_RD), .CD_RAM_CS(CD_RAM_CS),
		.CD_RAM_Q(CD_RAM_Q), .CD_RAM_RDY(CD_RAM_RDY),

		.CART_MODE(cart_type), .CART_MEM_A(CART_MEM_A), .CART_MEM_D(CART_MEM_D), .CART_MEM_WE(CART_MEM_WE),
		.CART_MEM_RD(CART_MEM_RD), .CART_MEM_Q(CART_MEM_Q), .CART_MEM_RDY(CART_MEM_RDY),

		.R(R), .G(G), .B(B), .DCLK(DCLK), .VS_N(VS_N), .HS_N(HS_N), .HBL_N(HBL_N), .VBL_N(VBL_N),
		.FIELD(FIELD), .INTERLACE(INTERLACE), .HRES(HRES), .VRES(VRES), .DCE_R(DCE_R), .DCE_F(),

		.SOUND_L(SOUND_L), .SOUND_R(SOUND_R),
		.FAST(set_fast), .BLUR_MESH(set_blur),
		.SCRN_EN(8'hFF), .SND_EN(3'b111), .DBG_PAUSE(1'b0), .DBG_BREAK(1'b0), .DBG_RUN(1'b0), .DBG_EXT(8'h00)
	);

	// ============================================================================================== pad (port 1)
	wire [15:0] joy1;
	pk_pad ipad (.clk_sys(clk_sys), .keys_74(cont1_key), .map(set_padmap), .joy1(joy1));
	HPS2PAD PAD (
		.PDR1I(SMPC_PDR1I), .PDR1O(SMPC_PDR1O), .DDR1(SMPC_DDR1),
		.PDR2I(SMPC_PDR2I), .PDR2O(SMPC_PDR2O), .DDR2(SMPC_DDR2),
		.JOY1(joy1)
	);

	// ============================================================================================== SDRAM (sdram1, emu)
	sdram1 sdram1 (
		.SDRAM_CLK(dram_clk), .SDRAM_A(dram_a), .SDRAM_BA(dram_ba), .SDRAM_DQ(dram_dq),
		.SDRAM_DQML(dram_dqm[0]), .SDRAM_DQMH(dram_dqm[1]),
		.SDRAM_nCS(),                                      // the Pocket's SDRAM chip select is tied on the board
		.SDRAM_nWE(dram_we_n), .SDRAM_nRAS(dram_ras_n), .SDRAM_nCAS(dram_cas_n), .SDRAM_CKE(dram_cke),
		.clk(clk_ram), .init(rst_ram), .sync(DCE_R),
		.addr_a0(VDP2_RA0_A[17:1]), .addr_a1(VDP2_RA1_A[16:1]), .din_a(VDP2_RA_D), .wr_a(VDP2_RA_WE), .rd_a(VDP2_RA_RD),
		.dout_a0(VDP2_RA0_Q), .dout_a1(VDP2_RA1_Q),
		.addr_b0(VDP2_RB0_A[17:1]), .addr_b1(VDP2_RB1_A[16:1]), .din_b(VDP2_RA_D),   // (emu: din_b = VDP2_RA_D)
		.wr_b(VDP2_RB_WE), .rd_b(VDP2_RB_RD), .dout_b0(VDP2_RB0_Q), .dout_b1(VDP2_RB1_Q),
		.ch2addr({1'b0, SCSP_RAM_A}), .ch2din(SCSP_RAM_D), .ch2wr(SCSP_RAM_WE & {2{SCSP_RAM_CS}}),
		.ch2rd(SCSP_RAM_RD & SCSP_RAM_CS), .ch2dout(SCSP_RAM_Q), .ch2rdy(SCSP_RAM_RDY),
		.dbg_ctrl_bank(), .dbg_ctrl_cmd(), .dbg_ctrl_we(), .dbg_ctrl_rfs(), .dbg_data0_read(), .dbg_out0_read(),
		.dbg_out0_bank(), .dbg_sdram_d()
	);

	// ============================================================================================== PSRAM 0 (emu's ddram)
	// RAM-H write data with MiSTer's Dezaemon 2 patch (emu: ramh_din; 0x5A015E01 -> 0x5A115E01 differs in bit 20);
	// the arbiter samples the clk_sys-domain client signals directly (glue/REPORT 3.1; its bench drove them so)
	// (A2) the arbiter applies the patch to its captured write word (psram0_arb change 5): dz_adr is the address part
	wire        dz_adr = set_dz && MEM_A[19:0] == 20'h1746C;
	wire [21:1] raml_addr = {~RAML_CS_N, ~SRAM_CS_N, ROM_CS_N & SRAM_CS_N & MEM_A[19], MEM_A[18:1]};
	wire [31:0] ramh_do;
	wire [15:0] raml_do;
	wire        ramh_busy, raml_busy, vdp1vram_busy, cdram_busy, cart_busy;
	wire [23:1] ld_addr;
	wire [15:0] ld_din;
	wire [ 1:0] ld_wr;
	wire        ld_port_busy;
	wire [20:1] sv_addr;
	wire        sv_rd, sv_busy;
	wire [15:0] sv_dout;
	psram0_arb #(.LEAN(ARB_LEAN)) iarb (
		.clk(clk_ram), .rst(por_ram), .flush(flush_ram), .ready(ps0_ready),
		.ramh_addr(MEM_A[19:2]), .ramh_dout(ramh_do), .ramh_din(MEM_DO), .ramh_dz(dz_adr), .ramh_rd(~RAMH_CS_N & ~MEM_RD_N),
		.ramh_wr({4{~RAMH_CS_N}} & ~MEM_DQM_N), .ramh_busy(ramh_busy),
		.cdram_addr(CD_RAM_A[18:1]), .cdram_dout(CD_RAM_Q), .cdram_din(CD_RAM_D), .cdram_rd(CD_RAM_RD & CD_RAM_CS),
		.cdram_wr(CD_RAM_WE & {2{CD_RAM_CS}}), .cdram_busy(cdram_busy),
		.raml_addr(raml_addr), .raml_dout(raml_do), .raml_din(MEM_DO[15:0]),
		.raml_rd((~ROM_CS_N | ~SRAM_CS_N | ~RAML_CS_N) & ~MEM_RD_N),
		.raml_wr({2{~SRAM_CS_N | ~RAML_CS_N}} & ~MEM_DQM_N[1:0]), .raml_busy(raml_busy),
		.vdp1vram_addr(VDP1_VRAM_A[18:1]), .vdp1vram_dout(VDP1_VRAM_Q), .vdp1vram_din(VDP1_VRAM_D),
		.vdp1vram_rd(VDP1_VRAM_RD), .vdp1vram_wr(VDP1_VRAM_WE), .vdp1vram_blen(VDP1_VRAM_BLEN),
		.vdp1vram_busy(vdp1vram_busy),
		.cart_addr(CART_MEM_A), .cart_dout(CART_MEM_Q), .cart_din(CART_MEM_D), .cart_rd(CART_MEM_RD),
		.cart_wr(CART_MEM_WE), .cart_busy(cart_busy),
		.bios_addr(ld_addr), .bios_din(ld_din), .bios_wr(ld_wr), .bios_busy(ld_port_busy),
		.bsram_addr(sv_addr), .bsram_dout(sv_dout), .bsram_din(16'h0000), .bsram_rd(sv_rd), .bsram_wr(2'b00),
		.bsram_busy(sv_busy),
		.p_a(cram0_a), .p_dq_out(cram0_dq_out), .p_dq_oe(cram0_dq_oe), .p_dq_in(cram0_dq_in), .p_clk(cram0_clk),
		.p_adv_n(cram0_adv_n), .p_cre(cram0_cre), .p_ce0_n(cram0_ce0_n), .p_ce1_n(cram0_ce1_n), .p_oe_n(cram0_oe_n),
		.p_we_n(cram0_we_n), .p_ub_n(cram0_ub_n), .p_lb_n(cram0_lb_n), .p_wait(cram0_wait)
`ifdef A6_DBG
		, .dbg_wait(dbg_wait0)
`endif
	);
	assign VDP1_VRAM_RDY = ~vdp1vram_busy;
	assign CD_RAM_RDY    = ~cdram_busy;
	assign CART_MEM_RDY  = ~cart_busy;
	assign MEM_DI     = !RAMH_CS_N ? ramh_do : {16'h0000, raml_do};   // (emu: 16-bit raml_do zero-extended)
	assign MEM_WAIT_N = !RAMH_CS_N ? ~ramh_busy : ~raml_busy;

	// ============================================================================================== VDP1 frame buffers
	wire fb_overflow;
	vdp1fb_ext #(.PS_BWC(1'b1)) ifb (
		.clk_sys(clk_sys), .clk_ram(clk_ram), .rst(por_ram),
		.FB_SEL(VDP1_FB_SEL), .FBD_A(VDP1_FBD_A), .FBD_D(VDP1_FBD_D), .FBD_WE(VDP1_FBD_WE), .FBD_RD(VDP1_FBD_RD),
		.FBD_Q(VDP1_FBD_Q), .FB_RDY(VDP1_FB_RDY), .FBV_A(VDP1_FBV_A), .FBV_Q(VDP1_FBV_Q), .FBE_WE(VDP1_FBE_WE),
		.FBE_D(VDP1_FBE_D), .FBV_VB(VDP1_FBV_VB),
		.sram_a(sram_a), .sram_dq_out(sram_dq_out), .sram_dq_oe(sram_dq_oe), .sram_dq_in(sram_dq_in),
		.sram_oe_n(sram_oe_n), .sram_we_n(sram_we_n), .sram_ub_n(sram_ub_n), .sram_lb_n(sram_lb_n),
		.cram1_a(cram1_a), .cram1_dq_out(cram1_dq_out), .cram1_dq_oe(cram1_dq_oe), .cram1_dq_in(cram1_dq_in),
		.cram1_clk(cram1_clk), .cram1_adv_n(cram1_adv_n), .cram1_cre(cram1_cre), .cram1_ce0_n(cram1_ce0_n),
		.cram1_ce1_n(cram1_ce1_n), .cram1_oe_n(cram1_oe_n), .cram1_we_n(cram1_we_n), .cram1_ub_n(cram1_ub_n),
		.cram1_lb_n(cram1_lb_n), .cram1_wait(cram1_wait),
		.ready(ps1_ready), .overflow(fb_overflow), .idle()  // (overflow / idle: bench checks, unused here)
`ifdef A6_DBG
		, .dbg_layout(set_lay), .dbg_wcoff(set_wcoff), .dbg_gap2(set_gap2), .dbg_clr(set_flgoff), .dbg_crst(flush_ram),
		.dbg_ext(dbg_wait0), .dbg_flags(dbg_flags), .dbg_disp(dbg_disp)
`endif
`ifdef A7_FIX
		, .cfg(ps1_cfg)
`endif
	);

	// ============================================================================================== loader, saves
	wire       ld_overflow;
	pk_loader ild (
		.clk_74a(clk_74a), .bridge_addr(bridge_addr), .bridge_wr(bridge_wr), .bridge_wr_data(bridge_wr_data),
		.overflow(ld_overflow), .clk_ram(clk_ram), .rst(por_ram),
		.bios_addr(ld_addr), .bios_din(ld_din), .bios_wr(ld_wr), .bios_busy(ld_port_busy), .busy(ld_busy)
	);
	wire [ 9:0] sv_dt_addr, cd_dt_addr;
	wire        sv_dt_wren, sv_dt_active;
	wire [31:0] sv_dt_data;
	pk_save #(.SLOT_INT(2), .SLOT_CART(3)) isv (
		.clk_74a(clk_74a), .bridge_addr(bridge_addr), .bridge_rd(bridge_rd), .bridge_wr(bridge_wr), .rd_data(save_rd_data),
		.table_ok(held_74 && !loading_74), .cart_type(cart_type_74),
		.dt_addr(sv_dt_addr), .dt_wren(sv_dt_wren), .dt_data(sv_dt_data), .dt_active(sv_dt_active),
		.clk_ram(clk_ram), .rst(por_ram),
		.bsram_addr(sv_addr), .bsram_rd(sv_rd), .bsram_dout(sv_dout), .bsram_busy(sv_busy)
	);
	// data slot table port a: the save sizes while the core is held in reset, else the CD source's reads
	assign datatable_addr = sv_dt_active ? sv_dt_addr : cd_dt_addr;
	assign datatable_wren = sv_dt_active & sv_dt_wren;
	assign datatable_data = sv_dt_data;

	// ============================================================================================== CD (design B2)
	cd_src_b #(.SLOTS(6), .BRIDGE_LE(1), .BASE(4'h4)) icd (
		.clk(clk_sys), .rst_n(~rst_sys),
		.ext_we(CD_EXT_WE), .ext_a(CD_EXT_A), .ext_wd(CD_EXT_WD), .ext_rd(CD_EXT_RD),
		.disc_in(CD_DISC_IN), .sec_req(CD_SEC_REQ), .sec_lba(CD_SEC_LBA), .sec_wr(CD_SEC_WR), .sec_data(CD_SEC_DATA),
		.sec_wait(CD_SEC_WAIT),
		.clk_74a(clk_74a), .datatable_addr(cd_dt_addr), .datatable_q(datatable_q), .dsr_read(dsr_read), .dsr_id(dsr_id),
		.dsr_offset(dsr_offset), .dsr_bridgeaddr(dsr_bridgeaddr), .dsr_length(dsr_length), .dsr_done(dsr_done),
		.dsr_err(dsr_err), .bridge_addr(bridge_addr), .bridge_wr(bridge_wr), .bridge_wr_data(bridge_wr_data)
	);

	// ============================================================================================== video, audio
	wire [23:0] av_rgb;                    // clk_pix: av_video's APF signals, to av_blank
	wire        av_de, av_skip, av_vs, av_hs;
	av_video #(.FIELD_INV(0), .LASTF(1)) ivid (
		.clk_sys(clk_sys), .dclk(DCLK), .r(R), .g(G), .b(B), .hbl_n(HBL_N), .vbl_n(VBL_N), .hs_n(HS_N), .vs_n(VS_N),
		.field(FIELD), .interlace(INTERLACE), .hres(HRES), .vres(VRES), .pal(PAL), .bob(set_bob),
`ifdef A6_DBG
		.ovl_on(~set_flgoff), .ovl_flags(dbg_flags), .ovl_disp(dbg_disp), .ovl_set({set_lay, set_wcoff, set_gap2}),
		.video_rgb_ov(av_rgb), .video_rgb(),
		.clk_pix(clk_pix), .video_de(av_de), .video_skip(av_skip), .video_vs(av_vs),
`else
		.clk_pix(clk_pix), .video_rgb(av_rgb), .video_de(av_de), .video_skip(av_skip), .video_vs(av_vs),
`endif
		.video_hs(av_hs)
	);
	// black frames while av_video sends none (the core in reset, the VDP2 held by the SMPC): the scaler's memory, the
	// last picture of whatever ran before, is overwritten from power-on (glue/av_blank.sv)
	av_blank iblk (
		.clk_pix(clk_pix), .dotsel(SMPC_DOTSEL),
		.in_rgb(av_rgb), .in_de(av_de), .in_skip(av_skip), .in_vs(av_vs), .in_hs(av_hs),
		.video_rgb(video_rgb), .video_de(video_de), .video_skip(video_skip), .video_vs(video_vs), .video_hs(video_hs)
	);
	// audio (D7): sound_i2s (core_top) takes the SCSP's held output itself (its FIFO writes on a change); glue's
	// av_audio48 INTERP = 0 would only add a register stage (8 ALMs; left out, P2 report section 5)
	assign audio_l = SOUND_L;
	assign audio_r = SOUND_R;
endmodule
`default_nettype wire

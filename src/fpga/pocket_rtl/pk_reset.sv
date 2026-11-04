// pk_reset: reset sequencing of the Saturn Pocket top (work/pocket, P2).
//
// Power-on: the core PLL comes up in the mode it is compiled in (clk_pll_core: NTSC 352) and clk_reconf reprograms it
// to the mode the core asks for ({PAL, SMPC_DOTSEL}) right after its DPRIO init. por_done (clk_74a) is set once the
// writer is idle and the PLL locked, and is never cleared again (glue/clk/REPORT 5.3: a later relock at a 320 / 352
// change must not reset anything; the clocks never stop). Until then the memory glue (psram0_arb, vdp1fb_ext, the
// loader's drain) is held in reset (por_ram, clk_ram): their PSRAM power-up waits and BCR writes start on stable clocks.
//
// The core's reset (rst_sys, clk_sys) follows MiSTer's emu (Saturn.sv): rst_sys = reset | download | rst_ram, with
//   reset    = !por_done | !PSRAMs configured | !APF reset_n | the Core Settings "Reset" (MiSTer: RESET | status[0])
//   download = APF is loading data slots (Data slot request write .. all complete) | the loader still writes
//              (MiSTer: bios / cartridge download)
//   rst_ram  = high while reset and for 255 clk_sys after reset or a download ends (MiSTer's rst_ram); its falling
//              edge (re)initialises the SDRAM (sdram1 init), as on MiSTer.
// flush (clk_ram) = rst_sys: psram0_arb holds its buffer valid bits clear while the core is in reset (loads write
// PSRAM 0 behind the buffers). held_74 (clk_74a) = rst_sys: pk_save writes the save slot sizes into APF's data slot
// table only then (port a is shared with the CD source's table reads, which need the core running).
// Crossings: level signals through 2-flop synchronisers (3 for the PLL lock path into clk_ram, as in clk_reconf).
// (A7b, work/a7b, with A7_FIX) ps_ready includes PSRAM 1's frame-buffer clear (vdp1fb_ext, 10.3 ms); boot_done uses
// ps_cfg (both PHYs configured, = A6's ps_ready) instead, so APF's "booting" status ends when it did in A6 (A7 waited
// for the clear and the Pocket firmware refused the core: "Error in framework RS: Host commands ignored"). The core's
// reset still waits for ps_ready: the clear overlaps APF's slot loads (PSRAM 0) and ends before the core runs.
`default_nettype none
module pk_reset (
	input  wire clk_74a,
	input  wire clk_sys,
	input  wire clk_ram,
	input  wire rc_locked,             // clk_74a: clk_reconf (PLL locked, synchronised there)
	input  wire rc_busy,               // clk_74a: clk_reconf reprogramming / not initialised
	input  wire ps_ready,              // clk_ram: both PSRAM PHYs have written their BCR
`ifdef A7_FIX
	input  wire ps_cfg,                // (A7b) clk_ram: the same without PSRAM 1's frame-buffer clear (boot_done only)
`endif
	input  wire apf_reset_n,           // clk_74a: core_bridge_cmd reset_n (APF Reset Enter / Exit)
	input  wire ds_requestwrite,       // clk_74a: core_bridge_cmd dataslot_requestwrite
	input  wire ds_allcomplete,        // clk_74a: core_bridge_cmd dataslot_allcomplete
	input  wire ld_busy,               // clk_ram: pk_loader has words to write
	input  wire usr_reset,             // clk_sys: Core Settings reset (pk_settings)
	output wire por_ram,               // clk_ram: power-on reset of the memory glue
	output wire boot_done,             // clk_74a: clocks set up and both PSRAMs configured (core_bridge_cmd status)
	output reg  rst_sys = 1'b1,        // clk_sys: the core's reset (RST_N = ~rst_sys)
	output reg  rst_ram = 1'b0,        // clk_sys: sdram1 init (MiSTer emu's rst_ram)
	output wire flush,                 // clk_ram: rst_sys
	output wire held_74,               // clk_74a: rst_sys
	output wire loading_74             // clk_74a: APF loads data slots
);
	// ---------------------------------------------------------------- clk_74a
	reg por_done = 1'b0;
	reg loading = 1'b0;
	always @(posedge clk_74a) begin
		if (rc_locked && !rc_busy) por_done <= 1'b1;
		if (ds_requestwrite) loading <= 1'b1;
		else if (ds_allcomplete) loading <= 1'b0;
	end
	assign loading_74 = loading;

	reg [1:0] rdy_74 = 2'b00, held_s = 2'b11;
	always @(posedge clk_74a) begin
`ifdef A7_FIX
		rdy_74 <= {rdy_74[0], ps_cfg};     // (A7b) boot_done does not wait for the clear; the core's reset does (rdy_ss)
`else
		rdy_74 <= {rdy_74[0], ps_ready};
`endif
		held_s <= {held_s[0], rst_sys};
	end
	assign boot_done = por_done & rdy_74[1];
	assign held_74 = held_s[1];

	// ---------------------------------------------------------------- clk_ram
	reg [2:0] por_s = 3'b111;
	reg [1:0] fl_s = 2'b11;
	always @(posedge clk_ram) begin
		por_s <= {por_s[1:0], ~por_done};
		fl_s  <= {fl_s[0], rst_sys};
	end
	assign por_ram = por_s[2];
	assign flush = fl_s[1];

	// ---------------------------------------------------------------- clk_sys
	reg [1:0] por_ss = 2'b00, rdy_ss = 2'b00, apf_ss = 2'b00, ld74_ss = 2'b00, ldr_ss = 2'b00;
	always @(posedge clk_sys) begin
		por_ss  <= {por_ss[0], por_done};
		rdy_ss  <= {rdy_ss[0], ps_ready};
		apf_ss  <= {apf_ss[0], apf_reset_n};
		ld74_ss <= {ld74_ss[0], loading};
		ldr_ss  <= {ldr_ss[0], ld_busy};
	end
	wire reset    = !por_ss[1] || !rdy_ss[1] || !apf_ss[1] || usr_reset;
	wire download = ld74_ss[1] || ldr_ss[1];

	reg       download_d = 1'b0;
	reg [7:0] delay_cnt = 8'd0;
	always @(posedge clk_sys) begin
		download_d <= download;
		if (delay_cnt != 8'd0) delay_cnt <= delay_cnt - 8'd1;
		else rst_ram <= 1'b0;
		if ((!download && download_d) || reset) begin
			rst_ram <= 1'b1;
			delay_cnt <= 8'hFF;
		end
		rst_sys <= reset || download || rst_ram;
	end
endmodule
`default_nettype wire

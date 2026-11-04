// A7b (work/a7b, candidate 0.0.1-a7b, 2026-11-02), with A7_FIX: new output cfg = the PHY's cfg_done (PSRAM 1 configured),
// for pk_reset's boot_done; `ready` (configured and the clear done) still holds the core's reset. On the Pocket, A7's
// boot_done waiting 10.3 ms for the clear made the firmware refuse the core ("Error in framework RS: Host commands
// ignored", hardware test 5); with cfg, APF's "booting" status ends as early as A6's and the clear overlaps the slot loads
// (they write PSRAM 0 only). Without A7_FIX there is no cfg port.
// A7 (work/a7, candidate 0.0.1-a7, 2026-11-02), only with `define A7_FIX (needs FB0_PSRAM and A6_DBG; without A7_FIX the
// file is A6's, apart from the alias q_rst = rst): the frame-buffer clear at core start. After the PHY has configured
// PSRAM 1 (its cfg_done) and before `ready` rises (pk_reset: ps_ready, so boot_done and the core's reset wait for it),
// every word of both dies at word addresses 0 .. 0x3FFFF (each place an FB layout can put a buffer: A[17] and the die)
// is written with 0x0000: 16,384 write bursts of 32 words, both byte enables on, die 0 first, in address order. The
// frame buffers then start transparent, as MiSTer's on-chip buffers after configuration (the PSRAM keeps its contents
// across core loads, and areas a game never draws or erases showed them). It runs once per power-on of the memory glue
// (rst = pk_reset's por_ram), never on a Core Settings or APF reset. Meanwhile the request side (both queues, the
// line-buffer prefetch, the arbiter) is held in reset (q_rst), so no queue command can reach the PHY (a queue sees
// m_ready from the PHY's cmd_ready whoever drives the command: an empty queue cannot be "taken"); the clear drives the
// PHY's command and write-data inputs (clr_on). `ready` rises when the PHY is idle again after the last burst; the
// queues leave reset one clk_ram after the clear ends (then their data-area sweep, 256 clk_ram, with full set). Time:
// 36 PSRAM cycles per burst (LC 2 + 32 words + address cycle + CE# high) = 72 clk_ram, x 16,384 = 1,179,648 clk_ram
// (11.0 ms at 107.4 MHz) added before boot_done.
// A6 (work/a6, diagnostic build 0.0.1-a6dbg, 2026-11-01), only with `define A6_DBG (needs FB0_PSRAM; without A6_DBG the
// file is A5's). Core Settings options for bisecting the hardware-only frame-buffer static of 0.0.1-a5 (clk_sys inputs,
// registered here in clk_ram: clk_sys -> clk_ram is synchronous; a change takes effect at the next PHY command):
//   dbg_layout  where the two buffers live in PSRAM 1, as {die, A[21:0]} with A[17] the offset bit (cmd_addr below):
//                 0 = A5: FB0 die 1, FB1 die 0 (word 0 of each)       1 = both in die 0: FB1 at word 0, FB0 at 0x20000
//                 2 = both in die 1: FB0 at word 0, FB1 at 0x20000     3 = swapped: FB0 die 0, FB1 die 1
//               (layouts 1 and 2: no die interleaving; layout 0 = A5 exactly)
//   dbg_wcoff   1 = draw / CPU writes (FBD side) are never combined (fb_queue req_nm): each is a one-word PSRAM write
//               with its own byte enables, so no multi-word write burst carries a masked (be = 00) or partial word.
//               Erase writes (FBE side: full words at ascending addresses, no flow control) still combine, so the
//               V-blank erase (one write per 4 clk_ram) cannot overflow the queue; their bursts have no holes.
//               Line-buffer reads unchanged.
//   dbg_gap2    1 = two PSRAM cycles of CE# high between accesses (psram_phy gap2)
//   dbg_clr     1 = debug flags off: the sticky flags are held clear (switching the flags on starts a new watch)
// Sticky flags (dbg_flags, clk_ram; cleared at power-on and while dbg_clr):
//   [0] fb_queue 0 overflow (FB0's queue: a request with no room = a lost write; also its protocol checks)
//   [1] fb_queue 1 overflow (FB1's queue)
//   [2] display underrun: a display read (V-blank over, the raster's line y = c_fbv_a[17:10] != 255, word x =
//       c_fbv_a[9:1] < 352) whose 32-word block x[8:5] has not fully arrived in the line-buffer half y[0] from the
//       half's current fill (lb_done: bursts completed since the fill started). Armed only after the raster has shown
//       y = 255 in this active period (u_arm), so the one clk_sys after V-blank in which OUT_Y still holds EWLR.Y1, and
//       the core's reset, are not counted; y = 255 itself (the line before line 0; a displayed line only in 256-line
//       modes, a known A3/A5 limitation) is not checked.
//   [3] / [4] READ WAIT anomaly on die 0 / die 1 of PSRAM 1 (psram_phy dbg_rw)
//   [5] / [6] WRITE WAIT anomaly on die 0 / die 1 of PSRAM 1 (psram_phy dbg_ww)
//   [7] PSRAM 0 WAIT anomaly, READ or WRITE, either die (input dbg_ext from psram0_arb's PHY: the same monitors on the
//       chip that holds the CPUs' memory, as a control)
//   dbg_disp = c_sel: the buffer being displayed (0 = FB0, 1 = FB1).
// A5 (work/a5, 2026-11-01) option (b), `ifdef FB0_PSRAM (qsf VERILOG_MACRO "FB0_PSRAM=1"): frame buffer 0 lives in PSRAM 1's
// die 1 (unused before) instead of the SRAM, which the Pocket's 55 ns part (AS6C2016-55) makes too slow for the display
// role (hardware test 2; work/a5/REPORT.txt). Frame buffer 1 stays in die 0. Both queues are then the PSRAM kind (block
// write combining with PS_BWC), so the two buffers behave the same, and they share the one PHY through a two-way
// arbiter (below: the display buffer's queue first). The SRAM is not used: its pins idle (WE#, OE#, UB#, LB# high, DQ
// released). Without FB0_PSRAM this file is A3's.
// A2 (work/a2, timing closure, 2026-10-31): the core's request signals (FB_SEL, FBD_*, FBE_*, FBV_A for the queues
// and the line-buffer fills, FBV_VB) go through a clk_ram capture register (c_*) before the request logic, which
// works one clk_ram later than before (the display read FBV_Q still uses the core's FBV_A directly; the write data
// FBD_D / FBE_D are taken from the core directly: the VDP1 holds FB_D from a request until its next one, at least two
// clk_sys later, and FBE_D is the EWDR register). The VDP1 looks at
// FB_RDY at the earliest one clk_sys after a read request (the read word is there when FB_RDY is back) and two clk_sys
// after a write request (FS_DRAW / FS_CPU_WRITE, then FS_IDLE): FB_RDY now also drops for a read request that is in
// the capture register and not yet pending (d_rd), and a write's queue count is there one clk_ram before FS_IDLE
// looks at it (before: two).
// vdp1fb_ext: the VDP1's two frame buffers off-chip on the Pocket (option (b) of glue/REPORT.txt):
//   frame buffer 0 = the SRAM (fb_sram), frame buffer 1 = PSRAM 1 (psram_phy, die 0, words 0-131071).
// Each memory has one role per frame, as the two frame-buffer DRAMs of the real VDP1: the draw buffer (drawing, CPU
// accesses, read-modify-write) or the display buffer (raster read-out, erase-while-displaying, V-blank erase),
// swapped with FB_SEL. Every request goes, in order, into the queue of the memory that holds its buffer
// (fb_queue: write combining for sequential writes); so a read sees every earlier write to its buffer.
//
// Core interface (VDP1 with `VDP1_FB_EXT, clk_sys domain; see glue/core/vdp1_fbext.diff):
//   FB_SEL         1: frame buffer 0 (SRAM) is the draw buffer, 1 (PSRAM) is displayed
//   FBD_*          draw / CPU side: A, D, WE (one-clk pulses), RD (one-clk pulse for draw reads, held for CPU
//                  reads); FBD_Q holds the last read word; FB_RDY = no read outstanding and room in the queue
//                  (the VDP1 waits on it before every draw / CPU access and for read data)
//   FBV_A, FBV_Q   display side: the raster address; FBV_Q = the word at the address of the previous clk_sys, as
//                  the on-chip M10K gave it (it comes from a two-line buffer filled ahead of the raster)
//   FBE_WE, FBE_D  erase writes (EWDR) to the display buffer at FBV_A
//   FBV_VB         vertical blank (VTIM_N low): no line fills
// The line buffer (two halves of 384 words): the half of the displayed line Y (FBV_A[17:10]) holds line Y and the
// other half line Y + 1, read ahead in 12 bursts of 32 words while line Y is shown; at the end of V-blank (Y = 255)
// lines 0 and 1 are read (alternating bursts), and again from the new display buffer when FB_SEL toggles (the
// frame change, ~23 dots before line 0 is shown). No fills in V-blank (FBV_VB). Erase writes reach the memory after the line was read (they are
// queued behind its reads), as the original read-then-erase per pixel.
// Clocks: clk_ram = 2 x clk_sys, phase aligned (the core's requests are seen on the clk_ram edge in the middle of
// their clk_sys cycle, so FB_RDY drops before the next clk_sys edge, as MiSTer's ddram.sv busy flags do).
// M10K: the line buffer (1,024 x 16: 2); the queues' FIFOs are MLABs.
module vdp1fb_ext #(
	parameter int PS_LC     = 2,
	parameter int PS_INIT   = 16384,
	parameter int SR_UNUSED = 0,
	parameter bit PS_BWC    = 1'b0   // D1 option (g): block write combining on the PSRAM's queue (fb_queue BWC)
) (
	input  logic        clk_sys,
	input  logic        clk_ram,
	input  logic        rst,          // clk_ram domain

	input  logic        FB_SEL,
	input  logic [17:1] FBD_A,
	input  logic [15:0] FBD_D,
	input  logic  [1:0] FBD_WE,
	input  logic        FBD_RD,
	output logic [15:0] FBD_Q,
	output logic        FB_RDY,
	input  logic [17:1] FBV_A,
	output logic [15:0] FBV_Q,
	input  logic        FBE_WE,
	input  logic [15:0] FBE_D,
	input  logic        FBV_VB,       // vertical blank: no line fills (the raster address only sweeps V-blank erases)

	// SRAM
	output logic [16:0] sram_a,
	output logic [15:0] sram_dq_out,
	output logic        sram_dq_oe,
	input  logic [15:0] sram_dq_in,
	output logic        sram_oe_n,
	output logic        sram_we_n,
	output logic        sram_ub_n,
	output logic        sram_lb_n,
	// PSRAM 1
	output logic [21:16] cram1_a,
	output logic [15:0] cram1_dq_out,
	output logic        cram1_dq_oe,
	input  logic [15:0] cram1_dq_in,
	output logic        cram1_clk,
	output logic        cram1_adv_n,
	output logic        cram1_cre,
	output logic        cram1_ce0_n,
	output logic        cram1_ce1_n,
	output logic        cram1_oe_n,
	output logic        cram1_we_n,
	output logic        cram1_ub_n,
	output logic        cram1_lb_n,
	input  logic        cram1_wait,
	output logic        ready,         // PSRAM configured (hold the core in reset until then)
`ifdef A7_FIX
	output logic        cfg,           // (A7b) PSRAM configured, the frame-buffer clear may still run (boot_done)
`endif
	output logic        overflow,      // a queue overflowed (bench check; never in a correct configuration)
`ifdef A6_DBG
	input  logic  [1:0] dbg_layout,    // (A6, clk_sys) FB layout 0-3 (header)
	input  logic        dbg_wcoff,     // (A6, clk_sys) 1: draw / CPU writes are never combined
	input  logic        dbg_gap2,      // (A6, clk_sys) 1: CE# high two PSRAM cycles between accesses
	input  logic        dbg_clr,       // (A6, clk_sys) 1: debug flags off (held clear)
	input  logic        dbg_crst,      // (A6, clk_ram) the core is held in reset (flush = rst_sys)
	input  logic        dbg_ext,       // (A6, clk_ram) PSRAM 0's WAIT anomaly pulse (psram0_arb dbg_wait)
	output logic  [7:0] dbg_flags,     // (A6, clk_ram) sticky flags (header)
	output logic        dbg_disp,      // (A6, clk_ram) the displayed buffer (0 = FB0, 1 = FB1)
`endif
	output logic        idle           // both queues empty, nothing in flight
);
	// ---------------------------------------------------------------------------------------------- core requests
	// (A2) capture register: the request logic below works on these
	logic        c_sel, c_fbd_rd, c_fbe_we, c_fbv_vb;
	logic [17:1] c_fbd_a, c_fbv_a;
	logic  [1:0] c_fbd_we;
	always_ff @(posedge clk_ram) begin
		c_sel <= FB_SEL; c_fbd_a <= FBD_A; c_fbd_we <= FBD_WE; c_fbd_rd <= FBD_RD;
		c_fbv_a <= FBV_A; c_fbe_we <= FBE_WE; c_fbv_vb <= FBV_VB;
	end
	// (A7) reset of the request side (both queues, the line-buffer prefetch, the arbiter): rst, and with A7_FIX also while
	// the frame-buffer clear runs (header; a register, as rst)
`ifdef A7_FIX
	logic        q_rst = 1'b1;
`else
	wire         q_rst = rst;
`endif
`ifdef A6_DBG
	// (A6) the Core Settings options, registered in clk_ram (header)
	logic  [1:0] d_lay;
	logic        d_wcoff, d_gap2, d_clr;
	always_ff @(posedge clk_ram) begin
		d_lay <= dbg_layout; d_wcoff <= dbg_wcoff; d_gap2 <= dbg_gap2; d_clr <= dbg_clr;
	end
`endif
	// read tag: {lb, half, gen[1:0], blk[3:0]} for line-buffer reads, 0 for the draw / CPU read
	localparam int TW = 8;
	logic        we_old, rd_old, ewe_old, sel_old;
	wire         d_we  = (|c_fbd_we) && !we_old;
	wire         d_rd  = c_fbd_rd && !rd_old;
	wire         e_we  = c_fbe_we && !ewe_old;
	wire         mdraw = !c_sel;            // memory of the draw buffer: 0 = SRAM, 1 = PSRAM
	logic        rd_pend;

	// line buffer: half h holds (or is being filled with) line hl_line[h]; the halves should hold the displayed line
	// y and the next one, y + 1 (want). A half that does not gets a fill of 12 bursts of 32 words; when both halves
	// fill, their bursts alternate. At y = 255 (OUT_Y = 511: from the end of V-blank to line 0, nothing is shown)
	// the halves want lines 0 and 1: the VDP1 may step from 511 to line 0 and on to line 1 within a few clocks
	// (its V-blank erase sweep runs until the next dot clock), so line 1 has to be on its way early too.
	logic  [7:0] hl_line [2];
	logic        hl_valid [2];
	logic        fl_on [2];
	logic  [3:0] fl_blk [2];
	logic  [1:0] gen [2];
	logic        rr;
	// (A2) want is registered from FBV_A in the clk_ram clock that loads c_fbv_a, so it equals the old function of
	// the displayed line y = c_fbv_a[17:10] in every clock; the increment / compare is no longer in the request paths
	logic  [7:0] want [2];
	wire   [7:0] y_in = FBV_A[17:10];
	always_ff @(posedge clk_ram) begin
		want[0] <= y_in[0] ? y_in + 8'd1 : y_in;
		want[1] <= y_in[0] ? (y_in == 8'hFF ? 8'd1 : y_in) : y_in + 8'd1;
	end
	wire         pf_sel = (fl_on[0] && fl_on[1]) ? rr : fl_on[1];   // the half whose fill pushes next
	wire         pf_mem = c_sel;                                     // the display memory

	// queues (0 = SRAM, 1 = PSRAM)
	logic        q_valid [2], q_we [2], q_full [2], q_empty [2], q_ovf [2];
	logic  [3:0] q_cnt   [2];
	logic [16:0] q_addr  [2];
	logic  [4:0] q_len   [2];
	logic [15:0] q_data  [2];
	logic  [1:0] q_be    [2];
	logic [TW-1:0] q_tag [2];
	logic        r_valid [2], r_last [2];
	logic [15:0] r_data  [2];
	logic [TW-1:0] r_tag [2];
	logic  [4:0] r_word  [2];
`ifdef FB0_PSRAM
	localparam bit FB0_PS = 1'b1;   // (A5 option b) both queues are PSRAM queues
`else
	localparam bit FB0_PS = 1'b0;
`endif
`ifdef A6_DBG
	// (A6) no merge for the draw buffer's queue: only draw / CPU accesses go there (erase writes and line-buffer reads
	// go to the display buffer's queue), so with the option every draw / CPU write becomes a command of its own
	logic        q_nm [2];
	always_comb for (int m = 0; m < 2; m++) q_nm[m] = d_wcoff && (mdraw == m);
`endif

	// requests to queue m this clk: the draw access (draw memory), else the erase write (display memory), else a
	// prefetch burst (display memory); the prefetch keeps at most two bursts queued (the erase writes, which have no
	// flow control, always find room) and waits while an erase write goes in
	wire pf_push = fl_on[pf_sel] && hl_line[pf_sel] == want[pf_sel] && !c_fbv_vb && c_sel == sel_old &&
	               q_cnt[pf_mem] <= 4'd1 && !(e_we && !mdraw == pf_mem) && !((d_we || d_rd) && mdraw == pf_mem);
	always_comb begin
		for (int m = 0; m < 2; m++) begin
			q_valid[m] = 1'b0; q_we[m] = 1'b0; q_addr[m] = '0; q_len[m] = '0; q_data[m] = '0; q_be[m] = '0; q_tag[m] = '0;
			if ((d_we || d_rd) && mdraw == m) begin
				q_valid[m] = 1'b1; q_we[m] = d_we; q_addr[m] = c_fbd_a; q_data[m] = FBD_D; q_be[m] = c_fbd_we;
			end else if (e_we && !mdraw == m) begin
				q_valid[m] = 1'b1; q_we[m] = 1'b1; q_addr[m] = c_fbv_a; q_data[m] = FBE_D; q_be[m] = 2'b11;
			end else begin
				// (A2) the prefetch burst's fields whenever neither a draw access nor an erase write goes to this queue;
				// only q_valid needs pf_push (the queue registers the fields every clk and uses them only with a
				// valid request), so pf_push is no longer a select of the address mux (the queue's block compare)
				q_addr[m] = {hl_line[pf_sel], fl_blk[pf_sel], 5'd0}; q_len[m] = 5'd31;
				q_tag[m] = {1'b1, pf_sel, gen[pf_sel], fl_blk[pf_sel]};
				if (pf_push && pf_mem == m) q_valid[m] = 1'b1;
			end
		end
	end

	always_ff @(posedge clk_ram) begin
		we_old <= |c_fbd_we; rd_old <= c_fbd_rd; ewe_old <= c_fbe_we;
		if (q_rst) begin   // (A7: q_rst, = rst without A7_FIX)
			rd_pend <= 1'b0; sel_old <= c_sel; rr <= 1'b0;
			for (int h = 0; h < 2; h++) begin hl_valid[h] <= 1'b0; fl_on[h] <= 1'b0; gen[h] <= '0; end
		end else begin
			if (d_rd) rd_pend <= 1'b1;
			sel_old <= c_sel;
			if (pf_push) begin
				fl_blk[pf_sel] <= fl_blk[pf_sel] + 4'd1;
				if (fl_blk[pf_sel] == 4'd11) fl_on[pf_sel] <= 1'b0;
				rr <= ~pf_sel;
			end
			for (int h = 0; h < 2; h++) begin
				if (c_fbv_vb || c_sel != sel_old) begin
					// V-blank (nothing shown; FBV_A may sweep the V-blank erase, which needs all of a PSRAM's time),
					// or the buffers were swapped: the halves are refilled afterwards (from the new display buffer)
					hl_valid[h] <= 1'b0; fl_on[h] <= 1'b0;
				end else if (!hl_valid[h] || hl_line[h] != want[h]) begin
					// (re)fill; bursts of an earlier fill of this half still in flight are dropped (gen)
					hl_valid[h] <= 1'b1; hl_line[h] <= want[h]; fl_on[h] <= 1'b1; fl_blk[h] <= '0; gen[h] <= gen[h] + 2'd1;
				end
			end
			// read data back: the draw / CPU word, or line-buffer words of a current fill
			for (int m = 0; m < 2; m++) if (r_valid[m]) begin
				r_word[m] <= r_last[m] ? 5'd0 : r_word[m] + 5'd1;
				if (!r_tag[m][TW-1]) begin FBD_Q <= r_data[m]; rd_pend <= 1'b0; end
			end
		end
	end
	// (A2) also low while a read request sits in the capture register (it is pending from the next clk_ram on); the
	// queue is the one of the core's current draw buffer (FB_SEL), where its next request goes
	assign FB_RDY = !rd_pend && !d_rd && !q_full[!FB_SEL];
	assign overflow = q_ovf[0] | q_ovf[1];
	assign idle     = q_empty[0] & q_empty[1];

	// ---------------------------------------------------------------------------------------------- line buffer
	logic [15:0] lb [1024];
	logic        lb_we;
	logic  [9:0] lb_wa;
	logic [15:0] lb_wd;
	always_comb begin
		lb_we = 1'b0; lb_wa = '0; lb_wd = '0;
		for (int m = 1; m >= 0; m--)
			if (r_valid[m] && r_tag[m][TW-1] && r_tag[m][5:4] == gen[r_tag[m][6]] && r_tag[m][3:0] < 4'd12) begin
				lb_we = 1'b1; lb_wa = {r_tag[m][6], r_tag[m][3:0], r_word[m]}; lb_wd = r_data[m];
			end
	end
	always_ff @(posedge clk_ram) if (lb_we) lb[lb_wa] <= lb_wd;
	always_ff @(posedge clk_sys) FBV_Q <= lb[{FBV_A[10], FBV_A[9:1]}];

	// ---------------------------------------------------------------------------------------------- memories
	logic        m_valid [2], m_ready [2], m_we [2], m_pop [2];
	logic [16:0] m_addr  [2];
	logic  [4:0] m_len   [2];
	logic [15:0] m_wd    [2];
	logic  [1:0] m_wbe   [2];
	logic        m_rv    [2], m_rl [2];
	logic [15:0] m_rd    [2];
	genvar gm;
	generate for (gm = 0; gm < 2; gm++) begin : q
		localparam int m = gm;
		// byte merge on the PSRAM's queue only (8 bpp draws there would otherwise cost two accesses per word; the
		// SRAM keeps up with them)
		fb_queue #(.AW(17), .TW(TW), .BM((m == 1 || FB0_PS) && !PS_BWC), .BWC((m == 1 || FB0_PS) && PS_BWC)) queue (
			.clk(clk_ram), .rst(q_rst),   // (A7: q_rst)
			.req_valid(q_valid[m]), .req_we(q_we[m]), .req_addr(q_addr[m]), .req_len(q_len[m]), .req_data(q_data[m]),
`ifdef A6_DBG
			.req_nm(q_nm[m]),
`endif
			.req_be(q_be[m]), .req_tag(q_tag[m]), .full(q_full[m]), .empty(q_empty[m]), .cmd_count(q_cnt[m]),
			.overflow(q_ovf[m]),
			.m_valid(m_valid[m]), .m_ready(m_ready[m]), .m_we(m_we[m]), .m_addr(m_addr[m]), .m_len(m_len[m]),
			.m_wd_pop(m_pop[m]), .m_wd_data(m_wd[m]), .m_wd_be(m_wbe[m]),
			.m_rd_valid(m_rv[m]), .m_rd_data(m_rd[m]), .m_rd_last(m_rl[m]),
			.rsp_valid(r_valid[m]), .rsp_data(r_data[m]), .rsp_tag(r_tag[m]), .rsp_last(r_last[m])
		);
	end endgenerate

`ifdef FB0_PSRAM
	// (A5 option b) one PHY for both buffers: frame buffer 0 = die 1 (CE1#: cmd_addr[22] = 1), frame buffer 1 = die 0
	// (CE0#), the same word addresses. The arbiter offers the PHY one queue's command per PHY command slot: the queue of
	// the display buffer (line fills, erase writes; c_sel, the memory the prefetch reads) when it has one, else the draw
	// buffer's. The choice psel is a register, made every clk from the queues' m_valid (so m_ready = cmd_ready & psel
	// stays a decode of registers, and so do the PHY's command inputs' selects); a command that becomes valid in the
	// PHY's take clk waits one PSRAM cycle. The PHY runs one command at a time: the queue whose command it took (own) gets
	// the write-data pops and the read words until the next take (the last read word comes in the clk after the PHY's
	// return to idle, before the next take's edge; write pops end before the PHY is idle).
	logic psel, own;
	wire  p_ready, p_pop, p_rv, p_rl;
	wire  [15:0] p_rd;
	wire  p_valid = psel ? m_valid[1] : m_valid[0];
	always_ff @(posedge clk_ram) begin
		if (q_rst) begin   // (A7: q_rst)
			psel <= 1'b0; own <= 1'b0;
		end else begin
			psel <= (c_sel ? m_valid[1] : m_valid[0]) ? c_sel : (c_sel ? m_valid[0] : m_valid[1]) ? !c_sel : psel;
			if (p_ready && p_valid) own <= psel;
		end
	end
	assign m_ready[0] = p_ready && !psel;
	assign m_ready[1] = p_ready && psel;
	assign m_pop[0] = p_pop && !own;  assign m_pop[1] = p_pop && own;
	assign m_rv[0]  = p_rv && !own;   assign m_rv[1]  = p_rv && own;
	assign m_rl[0]  = p_rl && !own;   assign m_rl[1]  = p_rl && own;
	assign m_rd[0]  = p_rd;           assign m_rd[1]  = p_rd;
`ifdef A6_DBG
	// (A6) FB layout (header): the die (cmd_addr[22]) and A[17] of each buffer's words
	wire  a_die0 = !d_lay[0], a_a17_0 = (d_lay == 2'd1);   // FB0: die 1 in layouts 0 and 2; at 0x20000 in layout 1
	wire  a_die1 = d_lay[1],  a_a17_1 = (d_lay == 2'd2);   // FB1: die 1 in layouts 2 and 3; at 0x20000 in layout 2
	logic [1:0] p_rw, p_ww;
`endif
`ifdef A7_FIX
	// (A7) the frame-buffer clear (header). clr_on: set by rst (power-on of the memory glue) only; while it is set the
	// PHY's command / write-data inputs are the clear's and q_rst holds the request side. A command (32 words of 0x0000 at
	// {die, A[17:5]} = clr_blk, A[4:0] = 0) is offered from the PHY's configuration on (p_cfg); the PHY takes it in a clk
	// with cmd_ready (p_ready), and clr_blk steps. After the last take (clr_all) the next p_ready means the PHY is back in
	// S_IDLE, the last burst written: clr_on falls, and with it `ready` rises.
	logic        clr_on = 1'b1, clr_all = 1'b0;
	logic [13:0] clr_blk = '0;
	wire         p_cfg;
	wire         clr_go = clr_on && !clr_all && p_cfg;
	always_ff @(posedge clk_ram) begin
		if (rst) begin
			clr_on <= 1'b1; clr_all <= 1'b0; clr_blk <= '0;
		end else if (clr_on && p_cfg && p_ready) begin
			if (clr_all) clr_on <= 1'b0;
			else begin clr_blk <= clr_blk + 14'd1; if (&clr_blk) clr_all <= 1'b1; end
		end
		q_rst <= rst || clr_on;
	end
	assign ready = p_cfg && !clr_on;
	assign cfg   = p_cfg;   // (A7b) boot_done's PSRAM 1 term: configured, the clear may still run
`endif
	psram_phy #(.LC(PS_LC), .INIT_CYC(PS_INIT)) psram (
		.clk(clk_ram), .rst(rst),
`ifdef A7_FIX
		// (A7) the clear's command and data while clr_on, else A6's (the queues are held in reset meanwhile: p_valid = 0)
		.cmd_valid(clr_on ? clr_go : p_valid), .cmd_ready(p_ready), .cmd_we(clr_on || (psel ? m_we[1] : m_we[0])),
		.cmd_addr(clr_on ? {clr_blk[13], 4'd0, clr_blk[12:0], 5'd0} :
		          psel ? {a_die1, 4'd0, a_a17_1, m_addr[1]} : {a_die0, 4'd0, a_a17_0, m_addr[0]}),
		.cmd_len(clr_on ? 5'd31 : psel ? m_len[1] : m_len[0]),
		.gap2(d_gap2), .dbg_rw(p_rw), .dbg_ww(p_ww),
		.wd_pop(p_pop), .wd_data(clr_on ? 16'h0000 : own ? m_wd[1] : m_wd[0]), .wd_be(clr_on ? 2'b11 : own ? m_wbe[1] : m_wbe[0]),
		.rd_valid(p_rv), .rd_data(p_rd), .rd_last(p_rl), .cfg_done(p_cfg),
`else
		.cmd_valid(p_valid), .cmd_ready(p_ready), .cmd_we(psel ? m_we[1] : m_we[0]),
`ifdef A6_DBG
		.cmd_addr(psel ? {a_die1, 4'd0, a_a17_1, m_addr[1]} : {a_die0, 4'd0, a_a17_0, m_addr[0]}), .cmd_len(psel ? m_len[1] : m_len[0]),
		.gap2(d_gap2), .dbg_rw(p_rw), .dbg_ww(p_ww),
`else
		.cmd_addr(psel ? {6'd0, m_addr[1]} : {1'b1, 5'd0, m_addr[0]}), .cmd_len(psel ? m_len[1] : m_len[0]),
`endif
		.wd_pop(p_pop), .wd_data(own ? m_wd[1] : m_wd[0]), .wd_be(own ? m_wbe[1] : m_wbe[0]),
		.rd_valid(p_rv), .rd_data(p_rd), .rd_last(p_rl), .cfg_done(ready),
`endif
		.p_a(cram1_a), .p_dq_out(cram1_dq_out), .p_dq_oe(cram1_dq_oe), .p_dq_in(cram1_dq_in), .p_clk(cram1_clk),
		.p_adv_n(cram1_adv_n), .p_cre(cram1_cre), .p_ce0_n(cram1_ce0_n), .p_ce1_n(cram1_ce1_n), .p_oe_n(cram1_oe_n),
		.p_we_n(cram1_we_n), .p_ub_n(cram1_ub_n), .p_lb_n(cram1_lb_n), .p_wait(cram1_wait)
	);
	// the SRAM is not used: idle pins
	assign sram_a = '0; assign sram_dq_out = '0; assign sram_dq_oe = 1'b0;
	assign sram_oe_n = 1'b1; assign sram_we_n = 1'b1; assign sram_ub_n = 1'b1; assign sram_lb_n = 1'b1;
`ifdef A6_DBG
	// (A6) display underrun monitor and the sticky flags (header). lbl_v: a line-buffer burst of a current fill
	// completes in this clk (the line-buffer write condition at the burst's last word), lbl_h its half
	logic       lbl_v, lbl_h;
	always_comb begin
		lbl_v = 1'b0; lbl_h = 1'b0;
		for (int m = 1; m >= 0; m--)
			if (r_valid[m] && r_last[m] && r_tag[m][TW-1] && r_tag[m][5:4] == gen[r_tag[m][6]] && r_tag[m][3:0] < 4'd12) begin
				lbl_v = 1'b1; lbl_h = r_tag[m][6];
			end
	end
	logic [3:0] lb_done [2];   // bursts of half h's current fill that have arrived (cleared where gen[h] is incremented)
	logic       u_arm;         // the raster has shown y = 255 since the last V-blank / core reset
	always_ff @(posedge clk_ram) begin
		for (int h = 0; h < 2; h++)
			if (!q_rst && !(c_fbv_vb || c_sel != sel_old) && (!hl_valid[h] || hl_line[h] != want[h])) lb_done[h] <= '0;   // (A7: q_rst, as gen)
			else if (lbl_v && lbl_h == h) lb_done[h] <= lb_done[h] + 4'd1;
		if (rst || c_fbv_vb || dbg_crst) u_arm <= 1'b0;
		else if (c_fbv_a[17:10] == 8'hFF) u_arm <= 1'b1;
	end
	wire u_late = u_arm && !c_fbv_vb && c_fbv_a[17:10] != 8'hFF && c_fbv_a[9:6] <= 4'd10 && c_fbv_a[9:6] >= lb_done[c_fbv_a[10]];
	logic [7:0] dflags;
	always_ff @(posedge clk_ram) begin
		if (rst || d_clr) dflags <= '0;
		else dflags <= dflags | {dbg_ext, p_ww, p_rw, u_late, q_ovf[1], q_ovf[0]};
	end
	assign dbg_flags = dflags;
	assign dbg_disp  = c_sel;
`endif
`else
`ifdef A7_FIX
	always_ff @(posedge clk_ram) q_rst <= rst;   // (A7) the clear exists only with FB0_PSRAM: here q_rst just follows rst
	assign cfg = ready;                           // (A7b) no clear: configured = ready
`endif
	fb_sram sram (
		.clk(clk_ram), .rst(rst),
		.cmd_valid(m_valid[0]), .cmd_ready(m_ready[0]), .cmd_we(m_we[0]), .cmd_addr(m_addr[0]), .cmd_len(m_len[0]),
		.wd_pop(m_pop[0]), .wd_data(m_wd[0]), .wd_be(m_wbe[0]),
		.rd_valid(m_rv[0]), .rd_data(m_rd[0]), .rd_last(m_rl[0]),
		.s_a(sram_a), .s_dq_out(sram_dq_out), .s_dq_oe(sram_dq_oe), .s_dq_in(sram_dq_in),
		.s_oe_n(sram_oe_n), .s_we_n(sram_we_n), .s_ub_n(sram_ub_n), .s_lb_n(sram_lb_n)
	);

	psram_phy #(.LC(PS_LC), .INIT_CYC(PS_INIT)) psram (
		.clk(clk_ram), .rst(rst),
		.cmd_valid(m_valid[1]), .cmd_ready(m_ready[1]), .cmd_we(m_we[1]), .cmd_addr({6'd0, m_addr[1]}), .cmd_len(m_len[1]),
		.wd_pop(m_pop[1]), .wd_data(m_wd[1]), .wd_be(m_wbe[1]),
		.rd_valid(m_rv[1]), .rd_data(m_rd[1]), .rd_last(m_rl[1]), .cfg_done(ready),
		.p_a(cram1_a), .p_dq_out(cram1_dq_out), .p_dq_oe(cram1_dq_oe), .p_dq_in(cram1_dq_in), .p_clk(cram1_clk),
		.p_adv_n(cram1_adv_n), .p_cre(cram1_cre), .p_ce0_n(cram1_ce0_n), .p_ce1_n(cram1_ce1_n), .p_oe_n(cram1_oe_n),
		.p_we_n(cram1_we_n), .p_ub_n(cram1_ub_n), .p_lb_n(cram1_lb_n), .p_wait(cram1_wait)
	);
`endif
endmodule

// A8 (work/a8, 2026-11-03), only with `define A8_RHC: a RAM-H cache in block RAM in place of the 2-line buffer (section
// "(A8) RAM-H cache" below); without the macro the file is A7d's. A8_RHC_SW (bench only) keeps both and switches at
// run time (rhc_on). A8_RHC_SL = log2 of the sets (default 6: 4 KB); A8_RHC_NOPF = no next-line prefetch.
// A6 (work/a6, diagnostic build, 2026-11-01), only with `define A6_DBG: psram_phy's new A6 ports: gap2 tied to 0 (A5's
// timing, so PSRAM 0 is A5's exactly); its WAIT monitors' pulses (any die, READ or WRITE) leave as dbg_wait (the debug
// squares' PSRAM 0 control flag).
// A2 (work/a2, timing closure, 2026-10-31), six changes, none visible to the core except as noted:
//   1. RAM-H writes go through a clk_ram capture register (rw_addr / rw_din / rw_wr), as MiSTer's emu registers
//      ramh_din / ramh_wr before ddram.sv (here the address too): every write reaches the write queue, the on-chip
//      4 KB and the cache invalidation one clk_ram later. The core sees the queue's full flag (ramh_busy) at the
//      earliest 2 clk_sys after a write strobe (SH-2 BSC: WAIT sampled at the CE_R after TRAS; SCU: at the CE_R of
//      CBUS_WRITE_WAIT), the push is now 2 clk_ram after it: the flag is there in time (MiSTer's ddram.sv, with the
//      same 1-clk_ram register and a FIFO that is full only when completely full, depends on the same timing).
//      Reads still sample the core's address and strobe directly.
//   2. rl_tag / cd_tag / ct_tag load on every read request of their port (exact: when the tag matches, it is loaded
//      with its own value), so the tag compare is no longer in the enable path of the tag registers.
//   3. rh_preq loads on every RAM-H read request while no fill request is pending (it is read only while one is;
//      a new request while one is pending cannot happen: ramh_busy is high then).
//   4. a VDP1 VRAM read request that starts a new fill is set up one clk_ram after the request edge: the request edge
//      registers the request's address / length (v_rqa / v_rqb, enable = the request edge only) and whether it starts
//      a new fill (v_nf, the compare); v_start / v_ca / v_end / v_left / v_val / v_fill / v_got / v_gen are loaded from
//      them in the next clk (the request compare no longer drives the enables of ~80 registers). v_wait is still set
//      at the request edge (the VDP1 looks at RDY one clk_sys after its request) and held in the set-up clk; a chunk
//      of the old fill is not issued in the set-up clk (it would be dropped). A new fill starts one clk_ram later.
//   5. the Dezaemon 2 patch of the RAM-H write word (was in the Pocket top) is applied to the captured word (rw_din):
//      same stored word, the 32-bit compare moved behind the capture register (input ramh_dz: its address part).
//   6. timing, exact: the RAM-H write queue's request address bit 0 is rh_lo_pend || !(|rw_wr[3:2]) (= !rh_push_hi
//      whenever a request is valid; the queue ignores the address otherwise); rh_want_w / rh_want_h load at every
//      RAM-H read request (they are read only while rh_wait is high, and no request comes then).
//   The PHY (glue psram_phy, A2) takes a command in the first clk of a PSRAM cycle (cmd_ready high then). So that a
//   read followed by another access loses no PSRAM cycle, the next command is also offered in the clk in which the
//   read's last word is presented (fin = rd_valid && rd_last; the PHY is idle from that clk on): the access
//   bookkeeping below now comes after the read-word bookkeeping (a new access in that clk wins busy_m / rcnt), and the
//   line client whose read ends in that clk is not offered again (its done pulse comes one clk later).
// POCKET COPY (work/pocket/rtl, P2): glue/rtl/psram0_arb.sv (md5 0af41259a210220877e0f7c9aa291ce0) with two changes,
// both inert at their defaults (LEAN = 0, flush = 0 give the original logic):
//   1. input flush: while high, every buffer / cache valid bit is held clear (RAM-H halves, the VDP1 burst buffer, the
//      line buffers). The Pocket top drives it with the core's reset: the loader port writes PSRAM 0 directly (BIOS,
//      cartridge, save images) without touching the client buffers, so after a load nothing stale may stay valid
//      (MiSTer resets ddram.sv after every download for the same reason). No client of the core runs during it.
//   2. parameter LEAN (decision D4, glue/REPORT 3.5, default 0): 1 = the backup port reads single words (a one-word
//      buffer: tag = the word address, 1-word fills) instead of 8-word lines. The other lean option of 3.5 (one line
//      buffer shared by the RAM-L port and the cartridge port) is NOT built: the two ports can be busy at once (SCU
//      DMA reading the cartridge while an SH-2 reads RAM-L / BIOS, whose data the core may take several clk_sys after
//      a hit), so a shared buffer could hand one of them the other's line (see work/pocket/REPORT.txt).
// psram0_arb: the Saturn core's memory clients that MiSTer serves from DDR3 (rtl/ddram.sv), on the Pocket's PSRAM 0
// (AS1C8M16PL, two dies, psram_phy: synchronous bursts, PSRAM clock = clk_ram / 2). A lean replacement for ddram.sv
// with the same client ports and handshakes (minus vdp1fb, which glue/rtl/vdp1fb_ext.sv replaces, and cdbuf, unused
// with CD_HLE). clk = clk_ram (2 x clk_sys, phase aligned): the clk_sys-domain client signals are sampled directly.
//
// Clients (requests are rising edges of rd / |wr; busy as in ddram.sv; read data come from small block-RAM buffers
// read at the client's address every clk, so a hit answers in the next clk without busy):
//   ramh   Work RAM-H (SH-2 bus, 32-bit): first 4 KB on chip (as ddram.sv); else a 2-way cache of 32-byte lines
//          (FIFO replacement), a line fill = one 16-word burst. Writes go through a write-combining queue
//          (wr_queue: consecutive words of an aligned 64-byte block become one burst); a write invalidates its line
//          in the cache, and a fill waits until the queue is empty (no read passes a write). Busy: queue full or a
//          fill pending.
//   raml   RAM-L / BIOS ROM / internal backup RAM (16-bit): one 32-byte line buffer.
//   vdp1vram  VDP1 VRAM: bursts of blen words (texture rows, up to 511) go into a 512-word buffer by address and are
//          read in chunks of at most 32 words (other clients get the memory between chunks); a read is answered
//          as soon as ITS word has arrived (streaming; ddram.sv waited for the whole burst). Reads without blen
//          outside the burst read one 16-word line. Writes through a write-combining queue (SCU DMA uploads become
//          bursts); a write in the buffered range invalidates it; reads wait until the queue is empty.
//   cdram  CD block buffer RAM (16-bit): one line buffer.
//   cart   cartridge RAM / ROM (16-bit): one line buffer.
//   bsram  backup RAM load / save port (16-bit, 16-byte lines as ddram.sv): internal RAM or cartridge backup.
//   bios   loader writes (BIOS / cartridge ROM / backup images); bios_addr is the PSRAM word address itself.
// The 16-bit clients hold address and data while busy (as on MiSTer): their writes are not captured, only the data
// word at the PSRAM access. Arbitration: RAM-H first, but after a RAM-H access a waiting other client goes next;
// the others take turns (round robin); within a client, writes before reads. (ddram.sv's fixed priority starved
// the low clients once the PSRAM was saturated.)
//
// PSRAM 0 word map ({die, A[21:0]}):
//   0x000000 RAM-H (1 MB)      0x080000 RAM-L (1 MB)   0x100000 BIOS ROM (512 KB)   0x140000 internal backup RAM
//   0x180000 VDP1 VRAM (512 KB)  0x1C0000 CD RAM (512 KB)   0x400000 (die 1) cartridge (8 MB; cartridge backup at its
//   start, as ddram.sv)
module psram0_arb #(
	parameter int PS_LC   = 2,
	parameter int PS_INIT = 16384,
	parameter bit LEAN    = 1'b0,     // (Pocket copy) D4: backup port without its line buffer
	// (A8) RAM-H cache: log2 of the sets, the smallest set count the bench's mask may select (tag width), prefetch
`ifdef A8_RHC_SL
	parameter int RHC_SL    = `A8_RHC_SL,
`else
	parameter int RHC_SL    = 6,
`endif
`ifdef A8_RHC_SLMIN
	parameter int RHC_SLMIN = `A8_RHC_SLMIN,
`else
	parameter int RHC_SLMIN = RHC_SL,
`endif
`ifdef A8_RHC_NOPF
	parameter bit RHC_PF    = 1'b0
`else
	parameter bit RHC_PF    = 1'b1
`endif
) (
	input  logic        clk,
	input  logic        rst,
	input  logic        flush,        // (Pocket copy) hold every buffer / cache valid bit clear
	output logic        ready,

	input  logic [19:2] ramh_addr,
	output logic [31:0] ramh_dout,
	input  logic [31:0] ramh_din,
	input  logic        ramh_dz,      // (A2) Dezaemon 2 patch, address part (Pocket top); the data part is checked here
	input  logic        ramh_rd,
	input  logic  [3:0] ramh_wr,
	output logic        ramh_busy,

	input  logic [18:1] cdram_addr,
	output logic [15:0] cdram_dout,
	input  logic [15:0] cdram_din,
	input  logic        cdram_rd,
	input  logic  [1:0] cdram_wr,
	output logic        cdram_busy,

	input  logic [21:1] raml_addr,
	output logic [15:0] raml_dout,
	input  logic [15:0] raml_din,
	input  logic        raml_rd,
	input  logic  [1:0] raml_wr,
	output logic        raml_busy,

	input  logic [18:1] vdp1vram_addr,
	output logic [15:0] vdp1vram_dout,
	input  logic [15:0] vdp1vram_din,
	input  logic        vdp1vram_rd,
	input  logic  [1:0] vdp1vram_wr,
	input  logic  [8:0] vdp1vram_blen,
	output logic        vdp1vram_busy,

	input  logic [25:1] cart_addr,
	output logic [15:0] cart_dout,
	input  logic [15:0] cart_din,
	input  logic        cart_rd,
	input  logic  [1:0] cart_wr,
	output logic        cart_busy,

	input  logic [23:1] bios_addr,
	input  logic [15:0] bios_din,
	input  logic  [1:0] bios_wr,
	output logic        bios_busy,

	input  logic [20:1] bsram_addr,
	output logic [15:0] bsram_dout,
	input  logic [15:0] bsram_din,
	input  logic        bsram_rd,
	input  logic  [1:0] bsram_wr,
	output logic        bsram_busy,

	// PSRAM 0
	output logic [21:16] p_a,
	output logic [15:0] p_dq_out,
	output logic        p_dq_oe,
	input  logic [15:0] p_dq_in,
	output logic        p_clk,
	output logic        p_adv_n,
	output logic        p_cre,
	output logic        p_ce0_n,
	output logic        p_ce1_n,
	output logic        p_oe_n,
	output logic        p_we_n,
	output logic        p_ub_n,
	output logic        p_lb_n,
`ifdef A6_DBG
	output logic        dbg_wait,      // (A6) a WAIT anomaly of PSRAM 0's PHY (pulse; psram_phy dbg_rw / dbg_ww, any die)
`endif
	input  logic        p_wait
);
	// ------------------------------------------------------------------------------------------- request edges
	// (A2) RAM-H write capture: the write path works on these registers (one clk_ram after the core's strobe)
	// (A2) MiSTer's Dezaemon 2 patch (emu: ramh_din; the word 0x5A015E01 written at RAM-H 0x1746C is stored as 0x5A115E01
	// when the option is on): the Pocket top passes the address part (ramh_dz) and the raw word; the word compare is made
	// on the captured word, so the 32-bit compare is no longer in the path from the core's data bus into the register
	logic [19:2] rw_addr;
	logic [31:0] rw_d;
	logic        rw_dz;
	logic  [3:0] rw_wr;
	always_ff @(posedge clk) begin
		rw_addr <= ramh_addr; rw_d <= ramh_din; rw_dz <= ramh_dz; rw_wr <= ramh_wr;
	end
	wire [31:0] rw_din = {rw_d[31:21], rw_d[20] | (rw_dz && rw_d == 32'h5A015E01), rw_d[19:0]};
	wire  rw_onchip = rw_addr[19:12] == 8'd0;
	logic ramh_rd_o, ramh_wr_o, cd_rd_o, cd_wr_o, rl_rd_o, rl_wr_o, v_rd_o, v_wr_o, ct_rd_o, ct_wr_o, bi_wr_o, bs_rd_o, bs_wr_o;
	always_ff @(posedge clk) begin
		{ramh_rd_o, ramh_wr_o} <= {ramh_rd, |rw_wr};
		{cd_rd_o, cd_wr_o} <= {cdram_rd, |cdram_wr};
		{rl_rd_o, rl_wr_o} <= {raml_rd, |raml_wr};
		{v_rd_o, v_wr_o} <= {vdp1vram_rd, |vdp1vram_wr};
		{ct_rd_o, ct_wr_o} <= {cart_rd, |cart_wr};
		bi_wr_o <= |bios_wr;
		{bs_rd_o, bs_wr_o} <= {bsram_rd, |bsram_wr};
	end
	wire ramh_rq = ramh_rd && !ramh_rd_o, ramh_wq = |rw_wr && !ramh_wr_o;   // (A2: ramh_wq on the captured write)
	wire cd_rq = cdram_rd && !cd_rd_o, cd_wq = |cdram_wr && !cd_wr_o;
	wire rl_rq = raml_rd && !rl_rd_o, rl_wq = |raml_wr && !rl_wr_o;
	wire v_rq = vdp1vram_rd && !v_rd_o, v_wq = |vdp1vram_wr && !v_wr_o;
	wire ct_rq = cart_rd && !ct_rd_o, ct_wq = |cart_wr && !ct_wr_o;
	wire bi_wq = |bios_wr && !bi_wr_o;
	wire bs_rq = bsram_rd && !bs_rd_o, bs_wq = |bsram_wr && !bs_wr_o;

	// ------------------------------------------------------------------------------------------- PSRAM side
	typedef enum logic [3:0] { C_RAMH_W, C_RAMH_R, C_CD_W, C_CD_R, C_RL_W, C_RL_R, C_V_W, C_V_R, C_CT_W, C_CT_R, C_BS_W, C_BS_R, C_BI_W } cl_t;
	logic        cmd_valid, cmd_ready, wd_pop, rd_valid, rd_last;
	logic [15:0] wd_data, rd_data;
	logic  [1:0] wd_be;
	logic        busy_m;             // an access is running (issued, data not all moved yet)
	wire         issue_ok;           // (A2) a new access may be issued: none running, or the last read word comes now
	cl_t         cur;
	logic  [4:0] wcnt, rcnt, len_r;
	logic [15:0] w0;                 // write word of a 16-bit client's access
	logic  [1:0] be0;
	logic  [8:0] rbase;              // VDP1 chunk: buffer index of its first word
	logic  [1:0] rgen;               // VDP1 chunk: fill generation
	logic        sel_v;              // next access (arbiter, below)
	cl_t         sel;                // (the registered choice, gsel)
	logic        sel_we;
	logic [22:0] sel_addr;
	logic  [4:0] sel_len;

	// ------------------------------------------------------------------------------------------- RAM-H
	wire         ramh_onchip = ramh_addr[19:12] == 8'd0;
	logic [31:0] ramh_ram [1024];
	logic [31:0] ramh_ram_q;
	always_ff @(posedge clk) begin
		// (A2) written from the capture registers (simple dual port: write at rw_addr, read at the live address)
		for (int b = 0; b < 4; b++) if (rw_wr[b] && rw_onchip) ramh_ram[rw_addr[11:2]][b*8 +: 8] <= rw_din[b*8 +: 8];
		ramh_ram_q <= ramh_ram[ramh_addr[11:2]];
	end
	// 2-way cache of 32-byte lines, valid per 16-byte half (= an SH-2 cache line). A miss reads from the requested
	// half on: half 0 -> 16 words (half 1 is read ahead), half 1 -> 8 words; the CPU goes on as soon as its half is
	// in. The buffer is read at the way whose tag matches the address now.
	logic [19:5] rh_tag [2];
	logic  [1:0] rh_hv [2];          // valid halves
	logic        rh_rr;              // next victim
	logic        rh_fill, rh_fill_w, rh_fill_h0, rh_fill_two, rh_kill, rh_done, rh_issued;
	logic [19:5] rh_fill_tag;
	logic        rh_pend;            // a request waits for the fill engine
	logic [19:4] rh_preq;            // its line and half
	logic        rh_wait, rh_want_w, rh_want_h;
	logic        rh_mark, rh_mark_w, rh_mark_h;
	logic [31:0] rh_buf [16];        // {way, half, longword}
	logic [31:0] rh_buf_q;
	logic [15:0] rh_hi;
	wire         rh_tm0 = rh_tag[0] == ramh_addr[19:5];
	wire         rh_tm1 = rh_tag[1] == ramh_addr[19:5];
	wire         rh_hit = (rh_tm0 && rh_hv[0][ramh_addr[4]]) || (rh_tm1 && rh_hv[1][ramh_addr[4]]);
	// the running fill brings this half (and was not spoiled by a write): wait for it
	wire         rh_coming = rh_fill && !rh_kill && rh_fill_tag == ramh_addr[19:5] && (rh_fill_h0 == ramh_addr[4] || rh_fill_two);
	always_ff @(posedge clk) rh_buf_q <= rh_buf[{rh_tm1, ramh_addr[4:2]}];
`ifdef A8_RHC
	logic [31:0] dt_qa;              // (A8) the cache's longword at the live address
	assign ramh_dout = ramh_onchip ? ramh_ram_q : rhc_on ? dt_qa : rh_buf_q;
`else
	assign ramh_dout = ramh_onchip ? ramh_ram_q : rh_buf_q;
`endif
	// write queue: a 32-bit write = the high word (if enabled) in the clk of the request, the low word in the next
	logic        rh_lo_pend;
	logic        rq_full, rq_empty, rq_valid;
	logic [18:0] rq_addr;
	logic  [4:0] rq_len;
	logic [15:0] rq_wd;
	logic  [1:0] rq_wbe;
	wire         rh_push_hi = ramh_wq && !rw_onchip && |rw_wr[3:2];                        // (A2: rw_*)
	wire         rh_push_lo = (ramh_wq && !rw_onchip && !(|rw_wr[3:2])) || rh_lo_pend;
	wr_queue #(.AW(19), .CD(3), .DD(5)) rq (
		.clk(clk), .rst(rst),
		.req_valid(rh_push_hi || rh_push_lo), .req_addr({rw_addr, rh_lo_pend || !(|rw_wr[3:2])}),   // (A2) [0]: = !rh_push_hi when valid
		.req_data(rh_push_hi ? rw_din[31:16] : rw_din[15:0]), .req_be(rh_push_hi ? rw_wr[3:2] : rw_wr[1:0]),
		.full(rq_full), .empty(rq_empty),
`ifdef FRESH_VBUSY
		.full_n(),
`endif
		.m_valid(rq_valid), .m_ready(cmd_ready && issue_ok && sel == C_RAMH_W), .m_addr(rq_addr), .m_len(rq_len),
		.m_wd_pop(wd_pop && cur == C_RAMH_W), .m_wd_data(rq_wd), .m_wd_be(rq_wbe)
	);
`ifdef A8_RHC
	logic rhc_busy;                  // (A8)
	assign ramh_busy = rq_full || (rhc_on ? rhc_busy : rh_pend || (rh_wait && !rh_hv[rh_want_w][rh_want_h]));
`else
	assign ramh_busy = rq_full || rh_pend || (rh_wait && !rh_hv[rh_want_w][rh_want_h]);
`endif

`ifdef A8_RHC
	// ------------------------------------------------------------------------------------------- (A8) RAM-H cache
	// A 2-way set-associative cache of 32-byte lines in block RAM in place of the 2-line buffer above (which the bench's
	// A8_RHC_SW keeps for its run-time switch): 2^RHC_SL sets (6: 4 KB, 8: 16 KB), valid per 16-byte half, LRU victim
	// (a way that holds no line first), write-update. The first 4 KB stay on chip. A miss fills as the buffer did
	// (half 0: 16 words, half 1: 8 words, into the way that holds the line if one does); with RHC_PF the end of a
	// demand fill starts a fill of the next line if no way holds it (16 words, into the set's empty way or the other
	// way by turns, never the way of the last hit's line, left as the set's next victim). A demand miss cancels a
	// prefetch that is not yet issued.
	// Requests: a new read strobe, or a new 16-byte half while the strobe stays low (the SCU's DMA reads). A request in
	// the line of the last hit whose half is valid is answered at once (data in the next clk, as the buffer's hits);
	// any other is looked up in two clks (timing, A8 fix): LK1 compares the set's entries and registers the outcome,
	// LK2 acts on it; busy in both (the SCU samples MEM_WAIT_N in LK1, at its clk_sys edge; the SH-2 BSC only at
	// TRCAS, ~8 clk later); a hit answers from the clk after LK2 on, a miss is busy until its half is in. Data are read
	// every clk at {way, set, longword}: the way from the last hit, so beats 1-3 of an SH-2 line fill (one per SH-2
	// clock, data needed one clk after the address) keep it.
	// Tag RAMs: one per way, {tag, valid halves}; port A reads at the live address, port B serves (in this order) the
	// flush sweep, the write path's reads, the fill's tag writes (set-up, half marks), the prefetch's set-up and
	// lookup. The fill registers hold the entry of the last fill's way (f_set / f_way, with a half being marked in
	// this clk): lookups, writes and set-ups take that entry from them, so a tag RAM write still on its way never
	// matters, and nothing else changes a tag entry.
	// Writes (A2 capture registers): U0 reads the set's tags, U1 finds whether the longword's half is valid in the
	// cache and registers that, U2 writes the longword (byte enables; a fill longword in the same clk goes first and
	// the update follows a clk later). The write's address and data stay in u1_* until the next write (writes come
	// at most every 2 clk_sys, reads of the longword far later: the SCU's next read strobe is >= 3 CE_R away). A
	// write to the line of a running fill kills it (its halves are not marked, as rh_kill); writes into slots of a
	// line being filled before its words come are overwritten by them.
	// (A8 timing fix, 2026-11-04: the measured version decided and wrote in U1, looked up and acted in one clk, and
	// compared the fill registers at the set-up; its fits missed clk_ram by 1.7-4.6 ns on those paths.)
	localparam int SL = RHC_SL;
	localparam int TL = 5 + RHC_SLMIN;     // tag = addr[19:TL]
	localparam int TW = 20 - TL;
`ifdef A8_RHC_SW
	// (bench, public: set from the testbench) rhc_on 0 = the 2-line buffer (A7d), 1 = the cache, set once while the
	// buffer is idle (rhc_safe); rhc_msk = the set index mask (a smaller cache); rhc_pf = prefetch
	logic          rhc_on  = 1'b0;
	logic [SL-1:0] rhc_msk = '1;
	logic          rhc_pf  = 1'b1;
`else
	localparam bit          rhc_on  = 1'b1;
	localparam bit [SL-1:0] rhc_msk = '1;
	localparam bit          rhc_pf  = RHC_PF;
`endif
	// fill engine (the arbiter's C_RAMH_R reads while rhc_on)
	logic          f_has;              // the fill registers hold the entry of way f_way of set f_set
	logic          f_act;              // a fill is set up and its words are not all in
	logic          f_iss;              // its PSRAM read is issued
	logic          f_pf;               // it is a prefetch
	logic          f_kill;             // a write to its line came: its halves are not marked
	logic [14:0]   f_line;             // its line (RAM-H addr[19:5])
	logic          f_h0, f_two;        // its first half, 16 words
	logic [SL-1:0] f_set;
	logic          f_way;
	logic [TW-1:0] f_tag;
	logic  [1:0]   f_v;                // the entry's valid halves
	wire           rhc_fill_rq = f_act && !f_iss && rq_empty;   // (a fill waits until the write queue is empty)
`endif

	// ------------------------------------------------------------------------------------------- 16-bit line clients
	// one 16-word line buffer each (bsram: 8 words); writes use the client's held address and data
	logic [21:5] rl_tag;  logic rl_val, rl_fill, rl_wp, rl_done;
	logic [18:5] cd_tag;  logic cd_val, cd_fill, cd_wp, cd_done;
	logic [25:5] ct_tag;  logic ct_val, ct_fill, ct_wp, ct_done;
	logic [20:1] bs_tag;  logic bs_val, bs_fill, bs_wp, bs_done;   // (Pocket copy: [3:1] used with LEAN only)
	logic        bi_wp;
	logic [15:0] rl_buf [16], cd_buf [16], ct_buf [16], bs_buf [8];
	always_ff @(posedge clk) begin
		raml_dout  <= rl_buf[raml_addr[4:1]];
		cdram_dout <= cd_buf[cdram_addr[4:1]];
		cart_dout  <= ct_buf[cart_addr[4:1]];
		bsram_dout <= bs_buf[LEAN ? 3'd0 : bsram_addr[3:1]];   // (Pocket copy: LEAN = one-word buffer)
	end
	// (no busy on a hit: the buffer is read at the client's address every clk, so the word is there in the next clk;
	// ddram.sv needed one clk of busy for its registered word select)
	// (Pocket copy) the backup port's buffer holds this address: its 8-word line, or with LEAN its word
	wire bs_same = bs_tag[20:4] == bsram_addr[20:4] && (!LEAN || bs_tag[3:1] == bsram_addr[3:1]);
	assign raml_busy  = rl_wp || rl_fill;
	assign cdram_busy = cd_wp || cd_fill;
	assign cart_busy  = ct_wp || ct_fill;
	assign bsram_busy = bs_wp || bs_fill;
	assign bios_busy  = bi_wp;

	// ------------------------------------------------------------------------------------------- VDP1 VRAM
	logic [15:0] v_buf [512];
	logic        v_burst;            // the buffer holds (is filling) the burst [v_start, v_end)
	logic [18:1] v_start;
	logic [18:1] v_ca;               // address of the next chunk
	logic  [8:0] v_left;             // words still to request
	logic  [8:0] v_got;              // words written into the buffer (readable one clk later: v_vis)
	logic  [8:0] v_vis;
	logic        v_val;              // contents valid (not invalidated by a write)
	logic        v_fill;             // chunks still to be read
	logic  [1:0] v_gen;              // fill generation (a new fill drops the words of an old chunk in flight)
	logic        v_wait;             // the VDP1 waits for a word that has not arrived
	logic        v_nf;               // (A2) the request of the last clk starts a new fill: set up in this clk
	logic [18:1] v_rqa;              // (A2) its address
	logic  [8:0] v_rqb;              // (A2) its burst length
	logic        vq_full, vq_empty, vq_valid;
	logic [17:0] vq_addr;
	logic  [4:0] vq_len;
	logic [15:0] vq_wd;
	logic  [1:0] vq_wbe;
	// (A3 option vqcap) VDP1 writes through a clk_ram capture register: the queue takes them one clk_ram later
	logic        vc_v;
	logic [18:1] vc_addr;
	logic [15:0] vc_din;
	logic  [1:0] vc_wr;
	always_ff @(posedge clk) begin vc_v <= v_wq && !rst; vc_addr <= vdp1vram_addr; vc_din <= vdp1vram_din; vc_wr <= vdp1vram_wr; end
`ifdef FRESH_VBUSY
	logic        vq_full_n;          // (FRESH_VBUSY) vq's full one clk ahead
`endif
	wr_queue #(.AW(18), .CD(2), .DD(5)) vq (
		.clk(clk), .rst(rst),
		.req_valid(vc_v), .req_addr(vc_addr), .req_data(vc_din), .req_be(vc_wr),
		.full(vq_full), .empty(vq_empty),
`ifdef FRESH_VBUSY
		.full_n(vq_full_n),
`endif
		.m_valid(vq_valid), .m_ready(cmd_ready && issue_ok && sel == C_V_W), .m_addr(vq_addr), .m_len(vq_len),
		.m_wd_pop(wd_pop && cur == C_V_W), .m_wd_data(vq_wd), .m_wd_be(vq_wbe)
	);
	always_ff @(posedge clk) vdp1vram_dout <= v_buf[vdp1vram_addr[9:1]];
	// the buffered range [v_start, v_end): two compares in parallel (timing); a read in it is answered once its word
	// (offset v_off) is in
	logic [19:1] v_end;              // (19 bits: a burst running past the end of VRAM wraps there; reads of the
	                                 //  wrapped part then fetch lines: correct, slower)
	wire         v_inr      = vdp1vram_addr >= v_start && {1'b0, vdp1vram_addr} < v_end;
	wire         v_inrange  = v_val && v_inr;
	wire   [8:0] v_off      = vdp1vram_addr[9:1] - v_start[9:1];
	// a read that starts a new fill: a burst (blen words from the address) unless it is the buffered burst, or a
	// line (16 words around the address) outside the buffered range
	wire         v_new = vdp1vram_blen != 9'd0 ? (!v_val || !v_burst || vdp1vram_addr != v_start) : !v_inrange;
`ifdef FRESH_VBUSY
	// (FRESH_VBUSY, work/fresh/glue, 2026-11-04; timing, exact) the VDP1's busy as one register loaded with the value
	// vq_full || v_wait takes at the next edge (v_wait's own next value, from its assignments in the state block below;
	// the queue's full_n): the OR gate and one routing hop leave the clk_ram -> clk_sys path into the VDP1's VRAM state
	// (the second worst path of the fitted build)
	logic        v_busy_r;
	wire         v_wait_n = !rst && (v_rq ? (v_new || v_off >= v_vis) : (v_wait && (v_nf || v_off >= v_vis)));
	always_ff @(posedge clk) v_busy_r <= v_wait_n || vq_full_n;
	assign vdp1vram_busy = v_busy_r;
`else
	assign vdp1vram_busy = vq_full || v_wait;
`endif
	// next chunk: from v_ca to the end of its aligned 32-word block, at most v_left words
	wire   [5:0] v_blk   = 6'd32 - {1'b0, v_ca[5:1]};
	wire         v_lastc = {3'd0, v_blk} >= v_left;
	wire   [5:0] v_clen  = v_lastc ? v_left[5:0] : v_blk;

	// ------------------------------------------------------------------------------------------- arbiter
	// next access; issued when none runs (the PHY takes one command at a time). RAM-H (the SH-2s and DMA: latency
	// counts) goes first, but after a RAM-H access a waiting other client gets the next one; the other clients take
	// turns (round robin over CD RAM, RAM-L port, VDP1 VRAM, cart, backup, loader). Within a client, writes first.
	logic  [5:0] g_req;
	logic  [2:0] g_rr, g_sel;
	logic        g_any, last_ramh;
	always_comb begin
		g_req[0] = cd_wp || (cd_fill && !cd_done);
		g_req[1] = rl_wp || (rl_fill && !rl_done);
		g_req[2] = vq_valid || (v_fill && vq_empty && !v_nf);   // (A2: not in a new fill's set-up clk)
		g_req[3] = ct_wp || (ct_fill && !ct_done);
		g_req[4] = bs_wp || (bs_fill && !bs_done);
		g_req[5] = bi_wp;
		g_any = |g_req; g_sel = g_rr;
		for (int i = 5; i >= 0; i--) begin
			logic [3:0] k;
			k = {1'b0, g_rr} + 4'(i);
			if (k >= 4'd6) k = k - 4'd6;
			if (g_req[k[2:0]]) g_sel = k[2:0];
		end
	end
`ifdef A8_RHC
	wire ramh_req   = rq_valid || (rhc_on ? rhc_fill_rq : rh_fill && !rh_done && !rh_issued && rq_empty);
	// (a pending fill keeps the turn until it is issued: the CPU waits on it, and the writes before it go first;
	// (A8) not a prefetch)
	wire serve_ramh = ramh_req && (!last_ramh || !g_any || (rhc_on ? f_act && !f_iss && !f_pf : rh_fill && !rh_issued));
`else
	wire ramh_req   = rq_valid || (rh_fill && !rh_done && !rh_issued && rq_empty);
	// (a pending fill keeps the turn until it is issued: the CPU waits on it, and the writes before it go first)
	wire serve_ramh = ramh_req && (!last_ramh || !g_any || (rh_fill && !rh_issued));
`endif
	// stage 1: the client to serve next, registered (timing); stage 2 issues it if it is still pending
	cl_t         nsel, gsel;
	logic        nsel_v, gsel_v;
	logic  [2:0] gsel_grp;
	always_comb begin
		nsel_v = 1'b1; nsel = C_BI_W;
		if (serve_ramh) nsel = rq_valid ? C_RAMH_W : C_RAMH_R;
		else if (!g_any) nsel_v = 1'b0;
		else case (g_sel)
			3'd0: nsel = cd_wp ? C_CD_W : C_CD_R;
			3'd1: nsel = rl_wp ? C_RL_W : C_RL_R;
			3'd2: nsel = vq_valid ? C_V_W : C_V_R;
			3'd3: nsel = ct_wp ? C_CT_W : C_CT_R;
			3'd4: nsel = bs_wp ? C_BS_W : C_BS_R;
			default: nsel = C_BI_W;
		endcase
	end
	always_ff @(posedge clk) begin gsel <= nsel; gsel_v <= nsel_v && !rst; gsel_grp <= g_sel; end
	logic still;
	always_comb begin
		case (gsel)
			C_RAMH_W: still = rq_valid;
`ifdef A8_RHC
			C_RAMH_R: still = rhc_on ? rhc_fill_rq : rh_fill && !rh_done && !rh_issued && rq_empty;
`else
			C_RAMH_R: still = rh_fill && !rh_done && !rh_issued && rq_empty;
`endif
			C_CD_W:   still = cd_wp;
			C_CD_R:   still = cd_fill && !cd_done;
			C_RL_W:   still = rl_wp;
			C_RL_R:   still = rl_fill && !rl_done;
			C_V_W:    still = vq_valid;
			C_V_R:    still = v_fill && vq_empty && !v_nf;
			C_CT_W:   still = ct_wp;
			C_CT_R:   still = ct_fill && !ct_done;
			C_BS_W:   still = bs_wp;
			C_BS_R:   still = bs_fill && !bs_done;
			default:  still = bi_wp;
		endcase
	end
	assign sel   = gsel;
	// (A2) not the line client whose read ends in this clk (fin; its done pulse is one clk later): VDP1 VRAM chunks
	// (each issue takes the next chunk) and RAM-H fills (rh_issued) need no such guard
	wire   fin   = rd_valid && rd_last;
	assign sel_v = gsel_v && still && !(fin && gsel == cur && gsel != C_V_R);
	always_comb begin
		sel_we = 1'b1; sel_addr = '0; sel_len = '0;
		case (gsel)
			C_RAMH_W: begin sel_addr = {4'h0, rq_addr}; sel_len = rq_len; end
`ifdef A8_RHC
			C_RAMH_R: begin sel_we = 1'b0;
				sel_addr = rhc_on ? {4'h0, f_line, f_h0, 3'd0} : {4'h0, rh_fill_tag, rh_fill_h0, 3'd0};
				sel_len  = (rhc_on ? f_two : rh_fill_two) ? 5'd15 : 5'd7; end
`else
			C_RAMH_R: begin sel_we = 1'b0; sel_addr = {4'h0, rh_fill_tag, rh_fill_h0, 3'd0}; sel_len = rh_fill_two ? 5'd15 : 5'd7; end
`endif
			C_CD_W:   sel_addr = {5'b00111, cdram_addr};
			C_CD_R:   begin sel_we = 1'b0; sel_addr = {5'b00111, cd_tag, 4'd0}; sel_len = 5'd15; end
			C_RL_W:   sel_addr = rl_map(raml_addr);
			C_RL_R:   begin sel_we = 1'b0; sel_addr = rl_map({rl_tag, 4'd0}); sel_len = 5'd15; end
			C_V_W:    begin sel_addr = {5'b00110, vq_addr}; sel_len = vq_len; end
			C_V_R:    begin sel_we = 1'b0; sel_addr = {5'b00110, v_ca}; sel_len = v_clen[4:0] - 5'd1; end
			C_CT_W:   sel_addr = {1'b1, cart_addr[22:1]};
			C_CT_R:   begin sel_we = 1'b0; sel_addr = {1'b1, ct_tag[22:5], 4'd0}; sel_len = 5'd15; end
			C_BS_W:   sel_addr = bs_map(bsram_addr);
			C_BS_R:   begin sel_we = 1'b0; sel_addr = bs_map(LEAN ? bs_tag : {bs_tag[20:4], 3'd0}); sel_len = LEAN ? 5'd0 : 5'd7; end
			default:  sel_addr = bios_addr;
		endcase
	end
	// RAM-L port: RAM-L (raml_addr[21]), internal backup RAM ([20]) or BIOS ROM
	function automatic logic [22:0] rl_map(input logic [21:1] a);
		rl_map = a[21] ? {4'b0001, a[19:1]} : a[20] ? {5'b00101, a[18:1]} : {5'b00100, a[18:1]};
	endfunction
	// backup port: cartridge backup ([20], start of the cartridge) or the internal backup RAM
	function automatic logic [22:0] bs_map(input logic [20:1] a);
		bs_map = a[20] ? {4'b1000, a[19:1]} : {8'b00101000, a[15:1]};
	endfunction
	// the write word of a 16-bit client's access (its held data), taken at the issue
	logic [15:0] sel_wd;
	logic  [1:0] sel_wbe;
	always_comb begin
		case (sel)
			C_CD_W:  begin sel_wd = cdram_din; sel_wbe = cdram_wr; end
			C_RL_W:  begin sel_wd = raml_din;  sel_wbe = raml_wr;  end
			C_CT_W:  begin sel_wd = cart_din;  sel_wbe = cart_wr;  end
			C_BS_W:  begin sel_wd = bsram_din; sel_wbe = bsram_wr; end
			default: begin sel_wd = bios_din;  sel_wbe = bios_wr;  end
		endcase
	end

	assign issue_ok  = !busy_m || fin;              // (A2: also in the clk the last read word is presented)
	assign cmd_valid = sel_v && issue_ok;
	wire   acc = cmd_valid && cmd_ready;

`ifdef A8_RHC
	// ------------------------------------------------------------------------------------------- (A8) RAM-H cache logic
	logic          sweep, sw_end, sw_req, rl_req;   // flush sweep; the clk after it; a request came during it; a waiter
	                                              // whose fill was spoiled looks again
	logic [SL-1:0] sw_a;
	// requests: a new read strobe, or a new half while the strobe stays low (outside the first 4 KB); a request that came
	// during the sweep, or a spoiled waiter, is looked up again (the requester holds its address while busy; the SCU's
	// strobe is one clk_sys long, so the strobe itself may be gone)
	logic [19:4]   c_old;
	always_ff @(posedge clk) c_old <= ramh_addr[19:4];
	wire           c_new  = ramh_rd && (!ramh_rd_o || c_old != ramh_addr[19:4]);
	wire           c_req  = rhc_on && !ramh_onchip && (c_new || (sw_end && sw_req) || rl_req);
	wire [SL-1:0]  c_set  = ramh_addr[5 +: SL] & rhc_msk;
	// the line of the last hit (or of the half a waiter got): a request in it whose half is valid is answered at once
	logic          cur_ok, cur_way;
	logic [14:0]   cur_line;
	logic  [1:0]   cur_hv;
	wire           c_fast  = cur_ok && cur_line == ramh_addr[19:5] && cur_hv[ramh_addr[4]];
	wire [SL-1:0]  cur_set = cur_line[SL-1:0] & rhc_msk;

	// tag RAMs (per way {tag, valid halves}; port A: the live address, port B: below), LRU RAM (the set's next victim),
	// data RAM ({way, set, longword}; port A: the live address in cur_way, port B: fill longwords and write updates)
`ifdef FRESH_TAGPACK
	// (FRESH_TAGPACK, work/fresh/glue, 2026-11-04; exact) the two ways' entries side by side in one RAM word, each in its
	// own byte lane (TW + 2 = 9 bits with SL = SLMIN = 8: M10K byte enables are 9 bits in the x18 mode), written per way
	// with the lane enables: 2 M10K (the two read ports) in place of 4
	(* ramstyle = "M10K" *) logic [2*TW+3:0] tg [2**SL];
`else
	(* ramstyle = "M10K" *) logic [TW+1:0] tg0 [2**SL];
	(* ramstyle = "M10K" *) logic [TW+1:0] tg1 [2**SL];
`endif
	(* ramstyle = "M10K" *) logic          lru [2**SL];
	(* ramstyle = "M10K" *) logic [31:0]   dt  [2**(SL+4)];
	logic [TW+1:0] ta0, ta1, tb0, tb1, tb_d;
	logic          lru_q, tb_we0, tb_we1, lru_we, lru_wd;
	logic [SL-1:0] tb_a, lru_wa;
	logic          db_we;
	logic [SL+3:0] db_a;
	logic [31:0]   db_d;
	logic  [3:0]   db_be;
`ifdef FRESH_TAGPACK
	always_ff @(posedge clk) begin
		{ta1, ta0} <= tg[c_set];
		if (tb_we0) tg[tb_a][TW+1:0] <= tb_d;
		if (tb_we1) tg[tb_a][2*TW+3:TW+2] <= tb_d;
		{tb1, tb0} <= tg[tb_a];
	end
`else
	always_ff @(posedge clk) begin ta0 <= tg0[c_set]; if (tb_we0) tg0[tb_a] <= tb_d; tb0 <= tg0[tb_a]; end
	always_ff @(posedge clk) begin ta1 <= tg1[c_set]; if (tb_we1) tg1[tb_a] <= tb_d; tb1 <= tg1[tb_a]; end
`endif
	always_ff @(posedge clk) begin lru_q <= lru[c_set]; if (lru_we) lru[lru_wa] <= lru_wd; end
	always_ff @(posedge clk) begin
		dt_qa <= dt[{cur_way, c_set, ramh_addr[4:2]}];
		for (int b = 0; b < 4; b++) if (db_we && db_be[b]) dt[db_a][b*8 +: 8] <= db_d[b*8 +: 8];
	end

	// the fill registers' entry with a half being marked in this clk
	logic          mk_now, mk_h, mk_rq;   // mark a half (one clk after its last longword); its tag RAM write is due
	wire  [1:0]    fv_now = f_v | ((mk_now && !f_kill) ? (2'b01 << mk_h) : 2'b00);

	// lookup: a request's set's entries are out in the clk after it
	logic          lk_v, lk_fast;
	logic [19:4]   lk_a;
	always_ff @(posedge clk) begin lk_v <= c_req && !sweep && !rst && !flush; lk_a <= ramh_addr[19:4]; lk_fast <= c_fast; end
	wire [14:0]    lk_line  = lk_a[19:5];
	wire           lk_half  = lk_a[4];
	wire [SL-1:0]  lk_set   = lk_a[5 +: SL] & rhc_msk;
	wire [TW-1:0]  lk_tag   = lk_a[19:TL];
	wire           lk_ov    = f_has && lk_set == f_set;
	wire [TW+1:0]  le0      = (lk_ov && !f_way) ? {f_tag, fv_now} : ta0;
	wire [TW+1:0]  le1      = (lk_ov &&  f_way) ? {f_tag, fv_now} : ta1;
	wire           lm0      = le0[TW+1:2] == lk_tag, lm1 = le1[TW+1:2] == lk_tag;
	wire  [1:0]    lv0      = le0[1:0], lv1 = le1[1:0];
	wire           lh0      = lm0 && lv0[lk_half], lh1 = lm1 && lv1[lk_half];
	wire           le0_free = le0[1:0] == 2'b00 && !(lk_ov && !f_way && f_act);   // holds no line, not being filled
	wire           le1_free = le1[1:0] == 2'b00 && !(lk_ov &&  f_way && f_act);
	wire           lk_coming = f_act && !f_kill && f_line == lk_line && (f_h0 == lk_half || f_two);
	// LK2: the lookup's outcome (k_*). Between LK1 and LK2 no set-up runs (a demand's needs mp_pend, a prefetch's
	// pf_ok), so the entries it saw stay; a coming half may be marked in LK2, or its fill end unmarked (spoiled):
	// LK2 checks both. A hit's way is lm1 (a line is in one way at most).
	logic          k_v, k_hit, k_coming, k_way, k_pres, k_vic;
	logic  [1:0]   k_pv;
	logic [19:4]   k_a;
	always_ff @(posedge clk) begin
		k_v <= lk_v && !lk_fast && !rst && !flush;
		k_a <= lk_a; k_hit <= lh0 || lh1; k_coming <= lk_coming; k_way <= lm1; k_pres <= lm0 || lm1;
		k_pv <= lm1 ? le1[1:0] : le0[1:0]; k_vic <= le0_free ? 1'b0 : le1_free ? 1'b1 : lru_q;
	end
	wire [14:0]    k_line = k_a[19:5];
	wire           k_half = k_a[4];
	wire [SL-1:0]  k_set  = k_a[5 +: SL] & rhc_msk;
	wire [TW-1:0]  k_tag  = k_a[19:TL];
	wire           k_ovp  = f_has && k_set == f_set && k_way == f_way;   // a miss's present way's entry: the fill registers'

	// demand misses. Set at the miss (LK2), as the fill registers and the line of the last hit do not change until its
	// set-up (no other set-up, lookup or waiter runs meanwhile): mp_ovp = k_ovp, mp_prs: the line is still in that way,
	// mp_kcur: the set-up evicts the line of the last hit
	logic          mp_pend, mp_wait, mp_half, mp_pres, mp_pw, mp_vic, mp_ovp, mp_prs, mp_kcur;
	logic [14:0]   mp_line;
	logic  [1:0]   mp_pv;
	// (a prefetch the arbiter has chosen (stage 1) is not dropped: it may be issued in this clk with its own address)
	wire           eng_free = !f_act || (f_pf && !f_iss && !(gsel_v && gsel == C_RAMH_R));
	wire [SL-1:0]  s_set = mp_line[SL-1:0] & rhc_msk;
	wire [TW-1:0]  s_tag = mp_line[14:TL-5];
	wire  [1:0]    s_pv  = mp_ovp ? fv_now : mp_pv;
	wire           s_way = mp_pres ? mp_pw : mp_vic;
	wire  [1:0]    s_v   = mp_prs ? s_pv : 2'b00;
	wire           su_go = mp_pend && eng_free;

	// prefetch
	logic          pf_rq, pf_look, pf_go, pf_way, f_tgl;
	logic [14:0]   pf_line;
	wire [SL-1:0]  pf_set = pf_line[SL-1:0] & rhc_msk;
	wire [TW-1:0]  pf_tag = pf_line[14:TL-5];
	wire           pf_ok  = !mp_pend && !f_act && !(lk_v && !lk_fast) && !k_v;   // nothing of the demand's in flight
	wire           pf_rd  = pf_rq && !pf_look && !pf_go && pf_ok;
	// never the current line's way: the SH-2 BSC reads beats 1-3 of a line fill without looking at WAIT, so the line
	// of the last hit must stay until another request (a prefetch set up during a burst would evict it under the burst)
	wire           pf_kcur = cur_ok && cur_set == pf_set && cur_way == pf_way;
	wire           pfs_go = pf_go && pf_ok && !pf_kcur;
	wire           pf_ov  = f_has && pf_set == f_set;
	wire [TW+1:0]  pe0    = (pf_ov && !f_way) ? {f_tag, fv_now} : tb0;
	wire [TW+1:0]  pe1    = (pf_ov &&  f_way) ? {f_tag, fv_now} : tb1;
	wire           pf_hit = pe0[TW+1:2] == pf_tag || pe1[TW+1:2] == pf_tag;
	wire           pf_vic = (cur_ok && cur_set == pf_set) ? !cur_way : pe0[1:0] == 2'b00 ? 1'b0 : pe1[1:0] == 2'b00 ? 1'b1 : f_tgl;

	// writes: u1_* = the last write (loaded at its U0, held through its U2); u1_ov (made in U0: no set-up runs then,
	// u0 has tag port B) = its set's entry of way f_way is the fill registers'; u1_upd: U2 writes it (way u2_way)
	wire           u0 = rhc_on && ramh_wq && !rw_onchip && !sweep;
	logic          u1, u1_ov, u2, u2_way;
	logic [19:2]   u1_a;
	logic [31:0]   u1_d;
	logic  [3:0]   u1_be;
	wire [SL-1:0]  u1_set = u1_a[5 +: SL] & rhc_msk;
	wire [TW-1:0]  u1_tag = u1_a[19:TL];
	wire [TW+1:0]  ue0    = (u1_ov && !f_way) ? {f_tag, fv_now} : tb0;
	wire [TW+1:0]  ue1    = (u1_ov &&  f_way) ? {f_tag, fv_now} : tb1;
	wire  [1:0]    uv0    = ue0[1:0], uv1 = ue1[1:0];
	wire           uh0    = ue0[TW+1:2] == u1_tag && uv0[u1_a[4]];
	wire           uh1    = ue1[TW+1:2] == u1_tag && uv1[u1_a[4]];
	wire           u1_upd = u1 && (uh0 || uh1);
	wire           fw     = rhc_on && rd_valid && cur == C_RAMH_R && rcnt[0];   // a fill longword

	// tag RAM port B
	logic          pb_mk, pb_su, pb_pfs, pb_pfr;
	always_comb begin
		tb_we0 = 1'b0; tb_we1 = 1'b0; tb_a = '0; tb_d = '0; pb_mk = 1'b0; pb_su = 1'b0; pb_pfs = 1'b0; pb_pfr = 1'b0;
		if (sweep) begin tb_a = sw_a; tb_we0 = 1'b1; tb_we1 = 1'b1; end
		else if (u0) tb_a = rw_addr[5 +: SL] & rhc_msk;
		else if (mk_rq) begin tb_a = f_set; tb_d = {f_tag, f_v}; tb_we0 = !f_way; tb_we1 = f_way; pb_mk = 1'b1; end
		else if (su_go) begin tb_a = s_set; tb_d = {s_tag, s_v}; tb_we0 = !s_way; tb_we1 = s_way; pb_su = 1'b1; end
		else if (pfs_go) begin tb_a = pf_set; tb_d = {pf_tag, 2'b00}; tb_we0 = !pf_way; tb_we1 = pf_way; pb_pfs = 1'b1; end
		else if (pf_rd) begin tb_a = pf_set; pb_pfr = 1'b1; end
	end
	// data RAM port B
	always_comb begin
		db_we = 1'b0; db_a = '0; db_d = '0; db_be = 4'h0;
		if (fw) begin db_we = 1'b1; db_a = {f_way, f_set, f_h0 | rcnt[3], rcnt[2:1]}; db_d = {rh_hi, rd_data}; db_be = 4'hF; end
		else if (u2) begin db_we = 1'b1; db_a = {u2_way, u1_set, u1_a[4:2]}; db_d = u1_d; db_be = u1_be; end
	end

	assign rhc_busy = sweep || sw_end || rl_req || (lk_v && !lk_fast) || k_v || mp_pend || mp_wait;

	always_ff @(posedge clk) begin
		lru_we <= 1'b0; mk_now <= 1'b0; sw_end <= 1'b0; rl_req <= 1'b0;
		u1 <= u0; u1_ov <= f_has && (rw_addr[5 +: SL] & rhc_msk) == f_set;
		if (u0) begin u1_a <= rw_addr; u1_d <= rw_din; u1_be <= rw_wr; end
		if (u1_upd) begin u2 <= 1'b1; u2_way <= uh1; end
		else if (u2 && !fw) u2 <= 1'b0;
		if (rst || flush) begin
			sweep <= 1'b1; sw_a <= '0; u2 <= 1'b0; sw_req <= 1'b0;
			f_has <= 1'b0; f_act <= 1'b0; f_iss <= 1'b0; f_kill <= 1'b0; mk_rq <= 1'b0;
			cur_ok <= 1'b0; mp_pend <= 1'b0; mp_wait <= 1'b0; pf_rq <= 1'b0; pf_look <= 1'b0; pf_go <= 1'b0;
		end else begin
			// flush sweep: both entries of every set = {0, 00}
			if (sweep) begin
				sw_a <= sw_a + 1'b1;
				if (&sw_a) begin sweep <= 1'b0; sw_end <= 1'b1; end
				if (rhc_on && c_new && !ramh_onchip) sw_req <= 1'b1;
			end
			if (sw_end) sw_req <= 1'b0;
			if (rhc_on && acc && sel == C_RAMH_R) f_iss <= 1'b1;
			// a write to the line of a running fill spoils it (as rh_kill)
			if (u0 && f_act && f_line == rw_addr[19:5]) f_kill <= 1'b1;
			// a half is marked one clk after its last longword was written
			if (rhc_on && rd_valid && cur == C_RAMH_R && rcnt[2:0] == 3'd7) begin mk_now <= 1'b1; mk_h <= f_h0 | rcnt[3]; end
			if (pb_mk) mk_rq <= 1'b0;
			// (a waiter's line is the fill's: mp_wait is set with mp_line = f_line, and no set-up runs while it waits)
			if (mk_now && !f_kill) begin
				f_v <= fv_now; mk_rq <= 1'b1;
				if (mp_wait && mp_half == mk_h) begin
					mp_wait <= 1'b0; cur_ok <= 1'b1; cur_line <= f_line; cur_way <= f_way; cur_hv <= fv_now;
				end else if (cur_ok && cur_line == f_line) cur_hv <= fv_now;
			end
			// the fill's last word is in: done; a demand fill starts the prefetch; a waiter that did not get its half
			// (its fill was spoiled) is looked up again
			if (rh_done && rhc_on && f_act) begin
				f_act <= 1'b0; f_iss <= 1'b0;
				if (!f_pf && rhc_pf && f_line != 15'h7FFF) begin pf_rq <= 1'b1; pf_line <= f_line + 15'd1; end
				if (mp_wait && !(mk_now && !f_kill && mp_half == mk_h)) begin mp_wait <= 1'b0; rl_req <= 1'b1; end
			end
			// lookups (LK2)
			if (k_v) begin
				if (k_hit) begin
					cur_ok <= 1'b1; cur_line <= k_line; cur_way <= k_way; cur_hv <= k_pv;
					lru_we <= 1'b1; lru_wa <= k_set; lru_wd <= !k_way;
				end else if (k_coming) begin
					if (mk_now && !f_kill && mk_h == k_half) begin            // its half is marked now
						cur_ok <= 1'b1; cur_line <= k_line; cur_way <= f_way; cur_hv <= fv_now;
					end else if (rh_done && f_act) rl_req <= 1'b1;            // its fill ended without it: look again
					else begin mp_wait <= 1'b1; mp_line <= k_line; mp_half <= k_half; end
				end else begin
					mp_pend <= 1'b1; mp_line <= k_line; mp_half <= k_half;
					mp_pres <= k_pres; mp_pw <= k_way; mp_pv <= k_pv; mp_vic <= k_vic;
					mp_ovp <= k_ovp; mp_prs <= k_pres && (!k_ovp || f_tag == k_tag);
					mp_kcur <= cur_ok && cur_set == k_set && cur_way == (k_pres ? k_way : k_vic) && cur_line != k_line;
					pf_rq <= 1'b0; pf_look <= 1'b0; pf_go <= 1'b0;   // the demand goes first
				end
			end
			// demand fill set-up (a prefetch not yet issued is dropped)
			if (pb_su) begin
				f_has <= 1'b1; f_act <= 1'b1; f_iss <= 1'b0; f_pf <= 1'b0; f_kill <= 1'b0;
				f_line <= mp_line; f_set <= s_set; f_way <= s_way; f_tag <= s_tag; f_v <= s_v;
				f_h0 <= mp_half; f_two <= !mp_prs && !mp_half;
				lru_we <= 1'b1; lru_wa <= s_set; lru_wd <= !s_way;
				if (mp_kcur) cur_ok <= 1'b0;
				mp_pend <= 1'b0; mp_wait <= 1'b1;
				pf_rq <= 1'b0; pf_look <= 1'b0; pf_go <= 1'b0;
			end
			// prefetch: look the next line up, set it up if no way holds it
			if (pb_pfr) pf_look <= 1'b1;
			if (pf_look) begin
				pf_look <= 1'b0;
				if (pf_hit || mp_pend) pf_rq <= 1'b0;
				else begin pf_go <= 1'b1; pf_way <= pf_vic; end
			end
			if (pf_go && pf_kcur) begin pf_go <= 1'b0; pf_rq <= 1'b0; end   // the current line moved into its way: dropped
			if (pb_pfs) begin
				pf_go <= 1'b0; pf_rq <= 1'b0; f_tgl <= ~f_tgl;
				f_has <= 1'b1; f_act <= 1'b1; f_iss <= 1'b0; f_pf <= 1'b1; f_kill <= 1'b0;
				f_line <= pf_line; f_set <= pf_set; f_way <= pf_way; f_tag <= pf_tag; f_v <= 2'b00; f_h0 <= 1'b0; f_two <= 1'b1;
				lru_we <= 1'b1; lru_wa <= pf_set; lru_wd <= pf_way;   // the prefetched line is its set's next victim
				if (cur_ok && cur_set == pf_set && cur_way == pf_way) cur_ok <= 1'b0;
			end
		end
	end
`ifdef A8_RHC_SW
	// (bench) the buffer has nothing running: the switch to the cache may happen in this clk
	wire rhc_safe = !rh_fill && !rh_pend && !rh_wait && !(busy_m && cur == C_RAMH_R) && !(gsel_v && gsel == C_RAMH_R);
`endif
`endif
	// one block for all state: the access part first, then the client front ends (a new VDP1 fill started in the
	// clk its previous fill's chunk is issued wins)
	always_ff @(posedge clk) begin
		{rh_done, rl_done, cd_done, ct_done, bs_done} <= '0;
		if (rst) begin
			busy_m <= 1'b0; last_ramh <= 1'b0; g_rr <= '0;
			rh_hv[0] <= 2'b00; rh_hv[1] <= 2'b00; rh_fill <= 1'b0; rh_rr <= 1'b0; rh_lo_pend <= 1'b0;
			rh_pend <= 1'b0; rh_wait <= 1'b0; rh_mark <= 1'b0; rh_issued <= 1'b0;
			rl_val <= 1'b0; rl_fill <= 1'b0; rl_wp <= 1'b0;
			cd_val <= 1'b0; cd_fill <= 1'b0; cd_wp <= 1'b0;
			ct_val <= 1'b0; ct_fill <= 1'b0; ct_wp <= 1'b0;
			bs_val <= 1'b0; bs_fill <= 1'b0; bs_wp <= 1'b0; bi_wp <= 1'b0;
			v_val <= 1'b0; v_fill <= 1'b0; v_wait <= 1'b0; v_burst <= 1'b0; v_gen <= '0; v_nf <= 1'b0;
		end else begin
			// write words
			if (wd_pop) begin
				wcnt <= wcnt + 5'd1;
				if (wcnt == len_r) busy_m <= 1'b0;
			end
			// read words (into the client's buffer, below)
			if (rd_valid) begin
				rcnt <= rcnt + 5'd1;
				if (cur == C_RAMH_R && !rcnt[0]) rh_hi <= rd_data;
				if (cur == C_RAMH_R && rcnt[2:0] == 3'd7) begin rh_mark_w <= rh_fill_w; rh_mark_h <= rh_fill_h0 | rcnt[3]; end
				if (cur == C_V_R && rgen == v_gen) v_got <= v_got + 9'd1;
				if (rd_last) begin
					busy_m <= 1'b0;
					case (cur)
						C_RAMH_R: rh_done <= 1'b1;
						C_CD_R:   cd_done <= 1'b1;
						C_RL_R:   rl_done <= 1'b1;
						C_CT_R:   ct_done <= 1'b1;
						C_BS_R:   bs_done <= 1'b1;
						default: ;
					endcase
				end
			end
			// ---- accesses (A2: after the read words: a new access in the clk the last read word comes wins busy_m / rcnt)
			if (acc) begin
				busy_m <= 1'b1; cur <= sel; len_r <= sel_len; wcnt <= '0; rcnt <= '0;
				last_ramh <= sel == C_RAMH_W || sel == C_RAMH_R;
				if (!(sel == C_RAMH_W || sel == C_RAMH_R)) g_rr <= (gsel_grp == 3'd5) ? 3'd0 : gsel_grp + 3'd1;
				w0 <= sel_wd; be0 <= sel_wbe;
				if (sel == C_RAMH_R) rh_issued <= 1'b1;
				case (sel)
					C_CD_W: cd_wp <= 1'b0;
					C_RL_W: rl_wp <= 1'b0;
					C_CT_W: ct_wp <= 1'b0;
					C_BS_W: bs_wp <= 1'b0;
					C_BI_W: bi_wp <= 1'b0;
					C_V_R:  begin
						rbase <= v_ca[9:1]; rgen <= v_gen;
						v_ca <= v_ca + {12'd0, v_clen}; v_left <= v_left - {3'd0, v_clen};
						if (v_lastc) v_fill <= 1'b0;
					end
					default: ;
				endcase
			end
			// ---- client front ends
			// RAM-H
			// a half is valid one clk after its last word was written (block RAM read latency)
			rh_mark <= rd_valid && cur == C_RAMH_R && rcnt[2:0] == 3'd7;
			if (rh_mark && !rh_kill) rh_hv[rh_mark_w][rh_mark_h] <= 1'b1;
			if (rh_done) begin rh_fill <= 1'b0; rh_issued <= 1'b0; end
			if (rh_wait && rh_hv[rh_want_w][rh_want_h]) rh_wait <= 1'b0;
			// a read that misses: wait for a running fill that brings its half, else set up a fill (now, or when the
			// fill engine is free)
			// (A2) rh_want_w / rh_want_h load at every read request (read only while rh_wait, which only a request that
			// waits for a running fill sets here; no request comes while rh_wait is high: ramh_busy holds the client
			// until the half is there, rh_wait drops in the next clk, before the client can make its next request)
			if (ramh_rq) begin rh_want_w <= rh_fill_w; rh_want_h <= ramh_addr[4]; end
			if (ramh_rq && !ramh_onchip && !rh_hit) begin
				if (rh_coming) rh_wait <= 1'b1;
				else           rh_pend <= 1'b1;
			end
			// (A2) the requested line and half, taken at every read request while no fill request waits (read only
			// while rh_pend, which is set by such a request)
			if (ramh_rq && !rh_pend) rh_preq <= ramh_addr[19:4];
			if (rh_pend && !rh_fill) begin
				// fill set-up: into the way that holds the line (one half), else into the victim (from the half on);
				// nothing if the half arrived meanwhile (read ahead by the fill that just ended)
				rh_pend <= 1'b0; rh_wait <= 1'b1; rh_want_h <= rh_preq[4]; rh_want_w <= rh_tag[1] == rh_preq[19:5];
				if (!((rh_tag[0] == rh_preq[19:5] && rh_hv[0][rh_preq[4]]) || (rh_tag[1] == rh_preq[19:5] && rh_hv[1][rh_preq[4]]))) begin
				rh_fill <= 1'b1; rh_kill <= 1'b0; rh_fill_tag <= rh_preq[19:5]; rh_fill_h0 <= rh_preq[4];
				if (rh_tag[0] == rh_preq[19:5] || rh_tag[1] == rh_preq[19:5]) begin
					rh_fill_w <= rh_tag[1] == rh_preq[19:5]; rh_want_w <= rh_tag[1] == rh_preq[19:5]; rh_fill_two <= 1'b0;
				end else begin
					rh_rr <= ~rh_rr; rh_tag[rh_rr] <= rh_preq[19:5]; rh_hv[rh_rr] <= 2'b00;
					rh_fill_w <= rh_rr; rh_want_w <= rh_rr; rh_fill_two <= !rh_preq[4];
				end
				end
			end
			rh_lo_pend <= rh_push_hi && |rw_wr[1:0];
			if (ramh_wq && !rw_onchip) begin
				// a write drops the line from the cache, and spoils a fill of it that is running (A2: captured write)
				if (rh_tag[0] == rw_addr[19:5]) rh_hv[0] <= 2'b00;
				if (rh_tag[1] == rw_addr[19:5]) rh_hv[1] <= 2'b00;
				if (rh_fill && rh_fill_tag == rw_addr[19:5]) rh_kill <= 1'b1;
			end
			// 16-bit line clients (as ddram.sv: busy for one clk after every read, for the buffer's read latency)
			// (A2) the tags load at every read request (the same value when they match), off the compare
			if (rl_rq) begin rl_tag <= raml_addr[21:5]; if (!rl_val || rl_tag != raml_addr[21:5]) begin rl_fill <= 1'b1; rl_val <= 1'b1; end end
			if (rl_wq) begin if (rl_tag == raml_addr[21:5]) rl_val <= 1'b0; rl_wp <= 1'b1; end
			if (cd_rq) begin cd_tag <= cdram_addr[18:5]; if (!cd_val || cd_tag != cdram_addr[18:5]) begin cd_fill <= 1'b1; cd_val <= 1'b1; end end
			if (cd_wq) begin if (cd_tag == cdram_addr[18:5]) cd_val <= 1'b0; cd_wp <= 1'b1; end
			if (ct_rq) begin ct_tag <= cart_addr[25:5]; if (!ct_val || ct_tag != cart_addr[25:5]) begin ct_fill <= 1'b1; ct_val <= 1'b1; end end
			if (ct_wq) begin if (ct_tag == cart_addr[25:5]) ct_val <= 1'b0; ct_wp <= 1'b1; end
			if (bs_rq) begin if (!bs_val || !bs_same) begin bs_fill <= 1'b1; bs_tag <= bsram_addr[20:1]; bs_val <= 1'b1; end end
			if (bs_wq) begin if (bs_same) bs_val <= 1'b0; bs_wp <= 1'b1; end
			if (bi_wq) bi_wp <= 1'b1;
			if (rl_done) rl_fill <= 1'b0;
			if (cd_done) cd_fill <= 1'b0;
			if (ct_done) ct_fill <= 1'b0;
			if (bs_done) bs_fill <= 1'b0;
			// VDP1 VRAM
			if (v_wq && v_val && v_inr) begin v_val <= 1'b0; v_fill <= 1'b0; end
			v_vis <= v_got;
			// (A2) a new fill: the request edge registers v_nf (and v_rqa / v_rqb, below); the set-up is in the next clk
			v_nf <= v_rq && v_new;
			if (v_nf) begin
				v_burst <= v_rqb != 9'd0;
				v_start <= v_rqb != 9'd0 ? v_rqa : {v_rqa[18:5], 4'd0};
				v_ca    <= v_rqb != 9'd0 ? v_rqa : {v_rqa[18:5], 4'd0};
				v_end   <= v_rqb != 9'd0 ? {1'b0, v_rqa} + {10'd0, v_rqb} : {{1'b0, v_rqa[18:5]} + 15'd1, 4'd0};
				v_left  <= v_rqb != 9'd0 ? v_rqb : 9'd16;
				v_val <= 1'b1; v_fill <= 1'b1; v_got <= '0; v_vis <= '0; v_gen <= v_gen + 2'd1;
			end
			if (v_rq) begin
				if (v_new) v_wait <= 1'b1;
				else       v_wait <= v_off >= v_vis;
			end else if (v_wait) begin
				v_wait <= v_nf || (v_off >= v_vis);   // the VDP1 holds the address while it waits (A2: held in the set-up clk)
			end
			// (Pocket copy) flush: nothing stays valid (last assignment wins)
			if (flush) begin
				rh_hv[0] <= 2'b00; rh_hv[1] <= 2'b00;
				rl_val <= 1'b0; cd_val <= 1'b0; ct_val <= 1'b0; bs_val <= 1'b0; v_val <= 1'b0;
			end
		end
	end
	// (A2) the VDP1 read request's address / length, taken at every request edge (used in the clk after a new fill's)
	always_ff @(posedge clk) if (v_rq) begin v_rqa <= vdp1vram_addr; v_rqb <= vdp1vram_blen; end
	// buffers (block RAM: written here, read at the clients' addresses above)
	always_ff @(posedge clk) begin
		if (rd_valid && cur == C_RAMH_R && rcnt[0]) rh_buf[{rh_fill_w, rh_fill_h0 | rcnt[3], rcnt[2:1]}] <= {rh_hi, rd_data};
		if (rd_valid && cur == C_CD_R) cd_buf[rcnt[3:0]] <= rd_data;
		if (rd_valid && cur == C_RL_R) rl_buf[rcnt[3:0]] <= rd_data;
		if (rd_valid && cur == C_CT_R) ct_buf[rcnt[3:0]] <= rd_data;
		if (rd_valid && cur == C_BS_R) bs_buf[rcnt[2:0]] <= rd_data;
		if (rd_valid && cur == C_V_R && rgen == v_gen) v_buf[rbase + {4'd0, rcnt}] <= rd_data;
	end
	// the current access's write words
	always_comb begin
		case (cur)
			C_RAMH_W: begin wd_data = rq_wd; wd_be = rq_wbe; end
			C_V_W:    begin wd_data = vq_wd; wd_be = vq_wbe; end
			default:  begin wd_data = w0;    wd_be = be0;    end
		endcase
	end

`ifdef A6_DBG
	logic [1:0] dbg_rw0, dbg_ww0;
	assign dbg_wait = |{dbg_rw0, dbg_ww0};
`endif
	psram_phy #(.LC(PS_LC), .INIT_CYC(PS_INIT)) phy (
		.clk(clk), .rst(rst),
		.cmd_valid(cmd_valid), .cmd_ready(cmd_ready), .cmd_we(sel_we), .cmd_addr(sel_addr), .cmd_len(sel_len),
		.wd_pop(wd_pop), .wd_data(wd_data), .wd_be(wd_be),
		.rd_valid(rd_valid), .rd_data(rd_data), .rd_last(rd_last), .cfg_done(ready),
`ifdef A6_DBG
		.gap2(1'b0), .dbg_rw(dbg_rw0), .dbg_ww(dbg_ww0),
`endif
		.p_a(p_a), .p_dq_out(p_dq_out), .p_dq_oe(p_dq_oe), .p_dq_in(p_dq_in), .p_clk(p_clk), .p_adv_n(p_adv_n),
		.p_cre(p_cre), .p_ce0_n(p_ce0_n), .p_ce1_n(p_ce1_n), .p_oe_n(p_oe_n), .p_we_n(p_we_n), .p_ub_n(p_ub_n),
		.p_lb_n(p_lb_n), .p_wait(p_wait)
	);
endmodule

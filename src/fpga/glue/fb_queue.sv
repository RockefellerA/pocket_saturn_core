// A6 (work/a6, diagnostic build 0.0.1-a6dbg, 2026-11-01), only with `define A6_DBG (without it the file is A5's): input
// req_nm (registered with the request as rnm): a write with req_nm = 1 never merges into an open command (BWC: the hit
// terms h0 / h1 get !rnm), so it becomes a command of its own, one word with its own byte enables; it is still an open
// write command afterwards (o[0]), so a later write with req_nm = 0 may merge into it. req_nm = 0 gives A5's queue
// exactly. (Run merge g_run: req_nm is not used.)
// fb_queue: in-order request queue in front of one frame-buffer memory (psram_phy or fb_sram, same interface).
// Requests (one per clk at most): writes {addr, data, be} and reads {addr, len, tag}. Consecutive writes to the
// next word of the same aligned 32-word block are merged into the open write burst at the tail (write
// combining), as long as that command has not been handed to the memory yet. With BM, a write to the open burst's
// LAST word (the other pixel of an 8-bit frame buffer's word, or the same pixel again) is combined into that word's
// data slot: the slot is two 9-bit lanes {be, byte} and only the lanes of the new write are rewritten (block-RAM
// byte enables), so byte enables add up and newer bytes win. Everything else becomes a new command; commands go to
// the memory strictly in order, so reads see every earlier write (no hazards).
// Read words come back in order with the tag of their command (the memory runs one command at a time, so one tag
// register does).
// Timing (114.5 MHz on the A4): the request is registered first and handled one clk later; both FIFOs are block
// RAMs read through their output register at the next head (no read-during-write bypass logic): a slot written at
// one edge is not used before the edge after next (m_valid waits a clk after a write to the head slot).
//
// BWC = 1 (D1 option (g), work/d1): block write combining instead of the run merge / byte merge above. Every command
// slot owns a 32-word data area (2^CD x 32 words = one M10K for CD = 3), indexed by the word's offset in its aligned
// 32-word block. A write merges into either of the two newest write commands not yet taken by the memory (o[0], o[1])
// when it falls into the same aligned 32-word block, in any order (ascending, descending, the anti-aliasing pixel's
// row, every other pixel of a mesh); only its own lanes are written (byte enables add up, newer bytes win) and the
// command becomes the burst [lo, hi] of the offsets written. A word of [lo, hi] never written goes out with both byte
// enables off: every word of a free data area has be = 00, because each word the memory pops is cleared again
// (written with zeros through the write port in a clk without a request write: requests come >= 2 clk apart) and
// the areas are swept to zero after reset. A read closes both open commands (no write moves ahead of a read).
// Needs a memory that pops the first word of a write >= 1 clk after taking the command (psram_phy: LC PSRAM cycles
// later; NOT fb_sram, which pops at the take): the data pointer moves to the burst at the take.
module fb_queue #(
	parameter int AW = 17,           // word address bits
	parameter int TW = 8,            // read tag bits
	parameter int CD = 3,            // log2 command FIFO depth
	parameter int DD = 6,            // log2 write data FIFO depth (words; BWC = 0)
	parameter bit BM = 1'b0,         // byte merge into the open burst's last word (BWC = 0)
	parameter bit BWC = 1'b0         // block write combining (option g)
) (
	input  logic          clk,
	input  logic          rst,
	// requests
	input  logic          req_valid,
	input  logic          req_we,
	input  logic [AW-1:0] req_addr,
	input  logic    [4:0] req_len,     // reads: words - 1 (the block must not be crossed)
	input  logic   [15:0] req_data,
	input  logic    [1:0] req_be,
	input  logic [TW-1:0] req_tag,
`ifdef A6_DBG
	input  logic          req_nm,      // (A6) no merge: this write becomes a command of its own (BWC)
`endif
	output logic          full,        // fewer than 2 command or 4 data slots left
	output logic          empty,       // nothing queued or in flight
	output logic   [CD:0] cmd_count,   // commands queued (counting the registered request)
	output logic          overflow,    // a request arrived with no room (must never happen: sized so)
	// memory side
	output logic          m_valid,
	input  logic          m_ready,
	output logic          m_we,
	output logic [AW-1:0] m_addr,
	output logic    [4:0] m_len,
	input  logic          m_wd_pop,
	output logic   [15:0] m_wd_data,
	output logic    [1:0] m_wd_be,
	input  logic          m_rd_valid,
	input  logic   [15:0] m_rd_data,
	input  logic          m_rd_last,
	// read responses
	output logic          rsp_valid,
	output logic   [15:0] rsp_data,
	output logic [TW-1:0] rsp_tag,
	output logic          rsp_last
);
	localparam int CN = 1 << CD, DN = 1 << DD;
	// a command {we, addr, len, tag} as a packed vector (Quartus 25.1 rejects struct member writes in generate blocks)
	localparam int CMW = 1 + AW + 5 + TW;

	// registered request
	logic          rv, rwe;
	logic [AW-1:0] raddr;
	logic    [4:0] rlen;
	logic   [15:0] rdata;
	logic    [1:0] rbe;
	logic [TW-1:0] rtag;
	always_ff @(posedge clk) begin
		rv <= req_valid && !rst; rwe <= req_we; raddr <= req_addr; rlen <= req_len; rdata <= req_data; rbe <= req_be; rtag <= req_tag;
	end
`ifdef A6_DBG
	logic          rnm;
	always_ff @(posedge clk) rnm <= req_nm;
`endif

	// the read in flight (the memory runs one command at a time)
	logic        rinfl;
	logic [TW-1:0] ftag;
	assign rsp_valid = m_rd_valid;
	assign rsp_data  = m_rd_data;
	assign rsp_last  = m_rd_last;
	assign rsp_tag   = ftag;

	generate if (!BWC) begin : g_run
	// command FIFO
	logic [CMW-1:0] cmem [CN];
	logic [CD:0] chead, ctail, ccnt;   // ctail: next free slot; the open command (if any) is ctail - 1
	logic        open;                 // the command at ctail - 1 is an open write burst
	logic [AW-1:0] o_addr, o_next;     // its start address, the address that would extend it
	logic [AW-1:0] o_last;             // its last word (byte merge)
	logic  [4:0] o_len;
	logic        lw_v;                 // a command slot was written at the last edge ...
	logic [CD-1:0] lw_a;               // ... this one
	logic [CMW-1:0] head_q;
	wire          hq_we   = head_q[CMW-1];
	wire [AW-1:0] hq_addr = head_q[CMW-2 -: AW];
	wire    [4:0] hq_len  = head_q[TW+4 -: 5];
	wire [TW-1:0] hq_tag  = head_q[TW-1:0];
	// write data FIFO: per word two lanes {be[i], data byte i}
	logic [1:0][8:0] dmem [DN];
	logic [DD:0] dhead, dtail, dcnt;
	logic [1:0][8:0] dq;

	wire head_is_open = open && ccnt == (CD+1)'(1);
	assign m_valid = ccnt != '0 && !(lw_v && lw_a == chead[CD-1:0]);
	assign {m_we, m_addr, m_len} = {hq_we, hq_addr, hq_len};
	assign m_wd_be   = {dq[1][8], dq[0][8]};
	assign m_wd_data = {dq[1][7:0], dq[0][7:0]};
	wire take = m_valid && m_ready;

	// merge into the open burst: next word, same 32-word block, not being handed over in this clk; byte merge: its
	// last word again (no command slot change; the visibility lag is set as for a merge, so the memory does not take
	// the burst before the rewritten word can be read: the SRAM engine takes the first word with the command)
	wire merge  = rv && rwe && open && !(take && head_is_open) && raddr == o_next && raddr[4:0] != 5'd0;
	wire bmerge = BM && rv && rwe && open && !(take && head_is_open) && raddr == o_last;
	wire cpush  = rv && !merge && !bmerge;

	assign full      = (ccnt >= (CD+1)'(CN - 2)) || (dcnt >= (DD+1)'(DN - 4));
	assign empty     = ccnt == '0 && !rinfl && dcnt == '0 && !rv;
	assign cmd_count = ccnt + (CD+1)'(rv);
	assign overflow  = rv && ((cpush && ccnt == (CD+1)'(CN)) || (rwe && !bmerge && dcnt == (DD+1)'(DN)));

	// FIFO memories: written at the tail, read (registered) at the next head
	wire [CD:0] chead_n = chead + (CD+1)'(take);
	wire [DD:0] dhead_n = dhead + (DD+1)'(m_wd_pop);
	wire [DD-1:0] dw_a  = bmerge ? dtail[DD-1:0] - 1'b1 : dtail[DD-1:0];
	wire        cw   = rv && !bmerge;
	wire [CD-1:0] cw_a = merge ? ctail[CD-1:0] - 1'b1 : ctail[CD-1:0];
	logic [CMW-1:0] cw_d;
	always_comb begin
		if (merge) cw_d = {1'b1, o_addr, o_len + 5'd1, {TW{1'b0}}};
		else       cw_d = {rwe, raddr, rwe ? 5'd0 : rlen, rtag};
	end
	always_ff @(posedge clk) begin
		if (cw) cmem[cw_a] <= cw_d;
		head_q <= cmem[chead_n[CD-1:0]];
	end
	always_ff @(posedge clk) begin
		// a new word writes both lanes, a byte merge only its own lanes of the last word
		if (rv && rwe) begin
			if (!bmerge || rbe[0]) dmem[dw_a][0] <= {rbe[0], rdata[7:0]};
			if (!bmerge || rbe[1]) dmem[dw_a][1] <= {rbe[1], rdata[15:8]};
		end
		dq <= dmem[dhead_n[DD-1:0]];
	end

	always_ff @(posedge clk) begin
		lw_v <= rv; lw_a <= cpush ? ctail[CD-1:0] : ctail[CD-1:0] - 1'b1;
		if (rst) begin
			chead <= '0; ctail <= '0; ccnt <= '0; dhead <= '0; dtail <= '0; dcnt <= '0;
			open <= 1'b0; rinfl <= 1'b0; lw_v <= 1'b0;
		end else begin
			chead <= chead_n;
			dhead <= dhead_n;
			if (cpush) ctail <= ctail + 1'b1;
			ccnt <= ccnt + (CD+1)'(cpush) - (CD+1)'(take);
			if (rv && rwe && !bmerge) dtail <= dtail + 1'b1;
			dcnt <= dcnt + (DD+1)'(rv && rwe && !bmerge) - (DD+1)'(m_wd_pop);
			// the open burst
			if (merge || cpush) o_last <= raddr;
			if (merge) begin
				o_len <= o_len + 5'd1; o_next <= o_next + 1'b1;
			end else if (cpush) begin
				open <= rwe; o_addr <= raddr; o_next <= raddr + 1'b1; o_len <= 5'd0;
			end else if (take && head_is_open) begin
				open <= 1'b0;
			end
			// the read in flight (the memory runs one command at a time)
			if (take && !hq_we) begin rinfl <= 1'b1; ftag <= hq_tag; end
			else if (m_rd_valid && m_rd_last) rinfl <= 1'b0;
		end
	end

	end else begin : g_bwc
	// ------------------------------------------------------------------------------------- block write combining
	// Timing (114.5 MHz): the request's block is compared with the open commands' blocks one clk ahead (beq, at the
	// edge that registers the request; stale when the open commands changed at that same edge: then no merge); no
	// merge into the head command while the memory is ready (m_ready, not the take: shorter path); a command is
	// stored as {we, block, lo, hi, tag} (its length hi - lo is formed at the memory side).
	localparam int BW = AW - 5;        // block number bits
	logic [CMW-1:0] cmem [CN];         // {we, block[BW], lo[5], hi[5], tag[TW]} (CMW = 1 + AW + 5 + TW)
	logic [CD:0] chead, ctail, ccnt;
	logic        lw_v;                 // a command slot was written at the last edge ...
	logic [CD-1:0] lw_a;               // ... this one
	logic [CMW-1:0] head_q;
	wire          hq_we  = head_q[CMW-1];
	wire [BW-1:0] hq_blk = head_q[CMW-2 -: BW];
	wire    [4:0] hq_lo  = head_q[TW+9 -: 5];
	wire    [4:0] hq_hi  = head_q[TW+4 -: 5];
	wire [TW-1:0] hq_tag = head_q[TW-1:0];
	wire    [4:0] hq_len = hq_hi - hq_lo;
	// open write commands: o[0] = the newest command (when it is a write not yet taken), o[1] = the one before it
	logic          ov   [2];
	logic [CD-1:0] oslot[2];
	logic   [BW-1:0] oblk [2];
	logic    [4:0] olo  [2], ohi [2];
	logic    [1:0] beq;                // the registered request's block == oblk[k] (compared at the request's edge)
	logic          beq_stale;          // ... but the open commands changed at that edge
	// data: per command slot 32 words of two lanes {be, byte}
	logic [1:0][8:0] bmem [CN * 32];
	logic [1:0][8:0] dq;
	// the write burst the memory is taking words from: slot, next offset, words left - 1
	logic          dp_fly;
	logic [CD-1:0] dp_slot;
	logic    [4:0] dp_off, dp_left;
	// clear of a popped word (pending), reset sweep
	logic          clr_v;
	logic [CD+4:0] clr_a;
	logic          swp;
	logic [CD+4:0] swp_a;

	assign m_valid = ccnt != '0 && !(lw_v && lw_a == chead[CD-1:0]);
	assign {m_we, m_addr, m_len} = {hq_we, hq_blk, hq_lo, hq_len};
	assign m_wd_be   = {dq[1][8], dq[0][8]};
	assign m_wd_data = {dq[1][7:0], dq[0][7:0]};
	wire take   = m_valid && m_ready;
	wire take_w = take && hq_we;

	// merge: a write into the block of an open command that the memory cannot take in this clk
	wire [4:0]    roff = raddr[4:0];
	wire [BW-1:0] rblk = raddr[AW-1:5];
	always_ff @(posedge clk) begin
		for (int k = 0; k < 2; k++) beq[k] <= req_addr[AW-1:5] == oblk[k];
		beq_stale <= rv;
	end
	// (A2, timing, exact) m_ready (the memory's ready: decoded from its state registers, a late input) comes last: the
	// hit is formed for m_ready = 0 (h0) and m_ready = 1 (h1) in parallel, and so are the command slot write (cw_a /
	// cw_d below); m_ready picks (the same values as before for either value of m_ready)
	logic [1:0] h0, h1, hit;
	always_comb for (int k = 0; k < 2; k++) begin
`ifdef A6_DBG
		h0[k] = rv && rwe && ov[k] && beq[k] && !beq_stale && !rnm;   // (A6) no merge for a req_nm write
`else
		h0[k] = rv && rwe && ov[k] && beq[k] && !beq_stale;
`endif
		h1[k] = h0[k] && !(oslot[k] == chead[CD-1:0]);
	end
	assign hit = m_ready ? h1 : h0;
	wire        mk    = !hit[0];                 // the open command merged into (when |hit)
	wire        merge = |hit;
	wire        cpush = rv && !merge;
	// the new range for either open command in parallel (off the hit path), then picked by the hit
	logic [4:0] k_lo [2], k_hi [2];
	always_comb for (int k = 0; k < 2; k++) begin
		k_lo[k] = (roff < olo[k]) ? roff : olo[k];
		k_hi[k] = (roff > ohi[k]) ? roff : ohi[k];
	end
	wire  [4:0] m_lo  = hit[0] ? k_lo[0] : k_lo[1];
	wire  [4:0] m_hi  = hit[0] ? k_hi[0] : k_hi[1];

	// slots in use: queued commands + the burst being popped (or its last word not yet cleared)
	wire [CD:0] cused = ccnt + (CD+1)'(dp_fly || clr_v);
	assign full      = (cused >= (CD+1)'(CN - 2)) || swp;
	assign empty     = ccnt == '0 && !rinfl && !dp_fly && !clr_v && !swp && !rv;
	assign cmd_count = ccnt + (CD+1)'(rv);

	// command FIFO: a new command at the tail, a merge rewrites its command {lo, hi}
	wire [CD:0]   chead_n = chead + (CD+1)'(take);
	wire          cw   = rv;
	// (A2) = merge ? oslot[mk] : ctail and the merged / new command word, formed per value of m_ready (h0 / h1)
	wire    [4:0] lo0 = h0[0] ? k_lo[0] : k_lo[1], hi0 = h0[0] ? k_hi[0] : k_hi[1];
	wire    [4:0] lo1 = h1[0] ? k_lo[0] : k_lo[1], hi1 = h1[0] ? k_hi[0] : k_hi[1];
	wire [CD-1:0] cw_a0 = (|h0) ? oslot[!h0[0]] : ctail[CD-1:0];
	wire [CD-1:0] cw_a1 = (|h1) ? oslot[!h1[0]] : ctail[CD-1:0];
	wire [CD-1:0] cw_a = m_ready ? cw_a1 : cw_a0;
	wire [CMW-1:0] cw_n  = {rwe, rblk, roff, rwe ? roff : 5'(roff + rlen), rtag};
	wire [CMW-1:0] cw_d0 = (|h0) ? {1'b1, rblk, lo0, hi0, {TW{1'b0}}} : cw_n;
	wire [CMW-1:0] cw_d1 = (|h1) ? {1'b1, rblk, lo1, hi1, {TW{1'b0}}} : cw_n;
	wire [CMW-1:0] cw_d = m_ready ? cw_d1 : cw_d0;
	always_ff @(posedge clk) begin
		if (cw) cmem[cw_a] <= cw_d;
		head_q <= cmem[chead_n[CD-1:0]];
	end

	// data memory: one write port shared by the request writes (only their own lanes) and the clears / sweep (both
	// lanes to zero); read port: the next word of the burst (the burst's first word at the take)
	wire          pa_req = rv && rwe;
	wire          pa_clr = !pa_req && (swp || clr_v);
	wire [CD+4:0] pa_a   = pa_req ? {cw_a, roff} : swp ? swp_a : clr_a;   // (A2: cw_a = merge ? oslot[mk] : ctail)
	wire    [1:0] pa_be  = pa_req ? rbe : 2'b11;
	wire [1:0][8:0] pa_d = pa_req ? {{1'b1, rdata[15:8]}, {1'b1, rdata[7:0]}} : '0;
	wire [CD+4:0] rd_a   = take_w ? {chead[CD-1:0], hq_lo} : {dp_slot, dp_off + 5'(m_wd_pop)};
	// overflow also flags protocol violations (bench checks): a clear lost to a back-to-back request / pop, a take while
	// a burst is still being popped, a first pop at the take (a memory that is not psram_phy)
	assign overflow  = (rv && ((cpush && cused == (CD+1)'(CN)) || (rwe && swp))) || (m_wd_pop && clr_v && pa_req) ||
	                   (take_w && (dp_fly || m_wd_pop));
	always_ff @(posedge clk) begin
		if (pa_req || pa_clr) begin
			if (pa_be[0]) bmem[pa_a][0] <= pa_d[0];
			if (pa_be[1]) bmem[pa_a][1] <= pa_d[1];
		end
		dq <= bmem[rd_a];
	end

	always_ff @(posedge clk) begin
		lw_v <= rv; lw_a <= cw_a;
		if (rst) begin
			chead <= '0; ctail <= '0; ccnt <= '0;
			ov[0] <= 1'b0; ov[1] <= 1'b0; rinfl <= 1'b0; lw_v <= 1'b0;
			dp_fly <= 1'b0; clr_v <= 1'b0; swp <= 1'b1; swp_a <= '0;
		end else begin
			chead <= chead_n;
			if (cpush) ctail <= ctail + 1'b1;
			ccnt <= ccnt + (CD+1)'(cpush) - (CD+1)'(take);
			// open commands (a take closes the head; a merge never goes into a command being taken)
			if (merge) begin
				olo[mk] <= m_lo; ohi[mk] <= m_hi;
				if (take && oslot[!mk] == chead[CD-1:0]) ov[!mk] <= 1'b0;
			end else if (cpush) begin
				if (rwe) begin
					ov[0] <= 1'b1; oslot[0] <= ctail[CD-1:0]; oblk[0] <= rblk; olo[0] <= roff; ohi[0] <= roff;
					ov[1] <= ov[0] && !(take && oslot[0] == chead[CD-1:0]);
					oslot[1] <= oslot[0]; oblk[1] <= oblk[0]; olo[1] <= olo[0]; ohi[1] <= ohi[0];
				end else begin
					ov[0] <= 1'b0; ov[1] <= 1'b0;   // a read: no later write may move ahead of it
				end
			end else if (take) begin
				for (int k = 0; k < 2; k++) if (oslot[k] == chead[CD-1:0]) ov[k] <= 1'b0;
			end
			// the burst being popped
			if (take_w) begin
				dp_fly <= 1'b1; dp_slot <= chead[CD-1:0]; dp_off <= hq_lo; dp_left <= hq_len;
			end else if (m_wd_pop) begin
				dp_off <= dp_off + 5'd1; dp_left <= dp_left - 5'd1;
				if (dp_left == 5'd0) dp_fly <= 1'b0;
			end
			// clear each popped word (in a clk without a request write: requests are >= 2 clk apart, pops too)
			if (m_wd_pop) begin clr_v <= 1'b1; clr_a <= {dp_slot, dp_off}; end
			else if (pa_clr && !swp) clr_v <= 1'b0;
			// after reset: every data word to zero (2^CD x 32 clk; the queue reports full meanwhile)
			if (swp && !pa_req) begin swp_a <= swp_a + 1'b1; if (&swp_a) swp <= 1'b0; end
			// the read in flight (the memory runs one command at a time)
			if (take && !hq_we) begin rinfl <= 1'b1; ftag <= hq_tag; end
			else if (m_rd_valid && m_rd_last) rinfl <= 1'b0;
		end
	end
	end endgenerate
endmodule

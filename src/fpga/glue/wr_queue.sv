// A3 (work/a3, timing closure, 2026-11-01): m_valid, full and empty are registers loaded one clk earlier with their
// next values (the same values in every clk; see work/a3/tools/mk_wrq_a3.py), so the arbiter's request logic and
// the busy flags into the core start at registers.
// wr_queue: posted-write queue with write combining, in front of a burst memory (psram_phy interface). Writes
// {addr, data, be}, at most one per clk. A write to the word after the open burst (the newest command, not yet
// handed to the memory) inside the same aligned 32-word block extends that burst; anything else opens a new one.
// Commands go to the memory in order. Lean version of fb_queue for write-only clients: command addresses and data
// in block RAM (read through their output registers at the next head, a slot is used from the second clk after
// it was written), burst lengths in registers (a merge only bumps the open command's length).
module wr_queue #(
	parameter int AW = 18,           // word address bits
	parameter int CD = 2,            // log2 commands
	parameter int DD = 5             // log2 data words
) (
	input  logic          clk,
	input  logic          rst,
	input  logic          req_valid,
	input  logic [AW-1:0] req_addr,
	input  logic   [15:0] req_data,
	input  logic    [1:0] req_be,
	output logic          full,        // fewer than 2 command or 4 data slots left
	output logic          empty,       // nothing queued (a write may still run in the memory)
`ifdef FRESH_VBUSY
	output logic          full_n,      // (FRESH_VBUSY) the value full takes at the next edge
`endif
	output logic          m_valid,
	input  logic          m_ready,
	output logic [AW-1:0] m_addr,
	output logic    [4:0] m_len,
	input  logic          m_wd_pop,
	output logic   [15:0] m_wd_data,
	output logic    [1:0] m_wd_be
);
	localparam int CN = 1 << CD, DN = 1 << DD;
`ifdef FRESH_WRQ_LENRAM
	// (FRESH_WRQ_LENRAM, work/fresh/glue, 2026-11-04) the command lengths live in the address RAM word ({len, addr})
	// instead of CN registers: the open command's length is a register (o_len), bumped by a merge, which then rewrites
	// the open command's RAM word ({o_len + 1, its block = o_next's, its start offset o_lo}); m_len = o_len while the
	// head is the open command, else the RAM word's field. The same m_len whenever m_valid is high (the arbiter uses
	// m_addr / m_len only then): a merge into the head slot is answered by o_len; a closed command's word was last
	// written at a merge at least one edge before the push that closed it, so its field is in head_a from the first clk
	// the head is not open (the lockstep bench finds m_len identical in every clk, m_valid high or low).
	// (A second form, the length in its own byte lane written alone at a merge, came out worse: Quartus kept that lane
	// in registers.)
	logic [AW+4:0] amem [CN];          // {len, addr}
	logic   [17:0] dmem [DN];
	logic    [4:0] o_len;              // the open command's length (words - 1)
	logic    [4:0] o_lo;               // its start offset in the block
	logic [AW+4:0] head_q;
`else
	logic [AW-1:0] amem [CN];
	logic   [17:0] dmem [DN];
	logic    [4:0] len [CN];
`endif
	logic   [CD:0] chead, ctail, ccnt;
	logic   [DD:0] dhead, dtail, dcnt;
	logic          open;
	logic [AW-1:0] o_next;
	logic          lw_v;               // a command was pushed at the last edge (its slot is not readable yet)
	logic [AW-1:0] head_a;
	logic   [17:0] dq;

	wire take = m_valid && m_ready;
	wire head_is_open = open && ccnt == (CD+1)'(1);
	wire merge = req_valid && open && !(take && head_is_open) && req_addr == o_next && req_addr[4:0] != 5'd0;
	wire push  = req_valid && !merge;

	// (A3) m_valid / full / empty registered one clk ahead (were: ccnt != 0 && !(lw_v && ccnt == 1); ccnt >= CN - 1 ||
	// dcnt >= DN - 4; ccnt == 0), from the next counter values per case of push / take / req_valid / m_wd_pop
	logic mv_r = 1'b0, full_r = 1'b0, empty_r = 1'b1;
	assign m_valid   = mv_r;
`ifdef FRESH_WRQ_LENRAM
	assign head_a    = head_q[AW-1:0];
	assign m_addr    = head_a;
	assign m_len     = head_is_open ? o_len : head_q[AW+4:AW];
`else
	assign m_addr    = head_a;
	assign m_len     = len[chead[CD-1:0]];
`endif
	assign {m_wd_be, m_wd_data} = dq;
	assign full      = full_r;
	assign empty     = empty_r;
`ifdef FRESH_VBUSY
	assign full_n    = !rst && (cfull_n || dfull_n);   // (FRESH_VBUSY) = full_r's next value (below)
`endif
	wire mv_n    = take ? (push ? ccnt >= (CD+1)'(2) : ccnt != (CD+1)'(1)) : ccnt != '0;
	wire cfull_n = (push && !take) ? ccnt >= (CD+1)'(CN - 2) : (!push && take) ? ccnt >= (CD+1)'(CN) : ccnt >= (CD+1)'(CN - 1);
	wire dfull_n = (req_valid && !m_wd_pop) ? dcnt >= (DD+1)'(DN - 5) : (!req_valid && m_wd_pop) ? dcnt >= (DD+1)'(DN - 3) : dcnt >= (DD+1)'(DN - 4);
	wire empty_n = (push && !take) ? 1'b0 : (!push && take) ? ccnt == (CD+1)'(1) : ccnt == '0;

	wire [CD:0] chead_n = chead + (CD+1)'(take);
	wire [DD:0] dhead_n = dhead + (DD+1)'(m_wd_pop);
	always_ff @(posedge clk) begin
`ifdef FRESH_WRQ_LENRAM
		if (push)       amem[ctail[CD-1:0]]        <= {5'd0, req_addr};
		else if (merge) amem[ctail[CD-1:0] - 1'b1] <= {o_len + 5'd1, o_next[AW-1:5], o_lo};
		head_q <= amem[chead_n[CD-1:0]];
`else
		if (push) amem[ctail[CD-1:0]] <= req_addr;
		head_a <= amem[chead_n[CD-1:0]];
`endif
		if (req_valid) dmem[dtail[DD-1:0]] <= {req_be, req_data};
		dq <= dmem[dhead_n[DD-1:0]];
	end
	always_ff @(posedge clk) begin
		lw_v <= push && !rst;
		mv_r    <= !rst && mv_n;
		full_r  <= !rst && (cfull_n || dfull_n);
		empty_r <= rst || empty_n;
		if (rst) begin
			chead <= '0; ctail <= '0; ccnt <= '0; dhead <= '0; dtail <= '0; dcnt <= '0; open <= 1'b0;
		end else begin
			chead <= chead_n;
			dhead <= dhead_n;
			ccnt  <= ccnt + (CD+1)'(push) - (CD+1)'(take);
			dcnt  <= dcnt + (DD+1)'(req_valid) - (DD+1)'(m_wd_pop);
			if (req_valid) dtail <= dtail + 1'b1;
`ifdef FRESH_WRQ_LENRAM
			if (merge) begin
				o_len <= o_len + 5'd1; o_next <= o_next + 1'b1;
			end else if (push) begin
				o_len <= 5'd0; o_lo <= req_addr[4:0]; ctail <= ctail + 1'b1; open <= 1'b1; o_next <= req_addr + 1'b1;
			end else if (take && head_is_open) begin
`else
			if (merge) begin
				len[ctail[CD-1:0] - 1'b1] <= len[ctail[CD-1:0] - 1'b1] + 5'd1; o_next <= o_next + 1'b1;
			end else if (push) begin
				len[ctail[CD-1:0]] <= 5'd0; ctail <= ctail + 1'b1; open <= 1'b1; o_next <= req_addr + 1'b1;
			end else if (take && head_is_open) begin
`endif
				open <= 1'b0;
			end
		end
	end
endmodule

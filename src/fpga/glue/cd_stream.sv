// Pocket CD disc source (glue/cd): the sector streamer. Sends one sector (1176 words) to CDB_HLE's SEC_* port:
// from the ring (mode 0, words base .. base + 1175), zeros (mode 1: off the disc, a gap), or an external word source
// (mode 2: ext_q for word idx once ext_ok, design A's TOC). SEC_WR / SEC_DATA are a valid / data pair taken by the
// sector engine when SEC_WAIT is low at a clock edge (CDB_HLE: SEC_WAIT = SW_FULL, a register). start (one clock)
// begins a sector, also aborting one in progress (a CD block reset in the middle of a sector).
// The sector engine needs >= 6 clocks per word (CD RAM arbiter + memory), this loop 3: never the bottleneck.
module cd_stream (
	input              clk,
	input              reset,

	input              start,
	input      [ 1: 0] mode,
	input      [13: 0] base,

	output reg [13: 0] raddr,
	input      [15: 0] rq,
	output reg [10: 0] idx,
	input      [15: 0] ext_q,
	input              ext_ok,

	output reg         sec_wr,
	output reg [15: 0] sec_data,
	input              sec_wait,
	output             busy
);
	reg [1:0] st = 2'd0, m;
	assign busy = st != 2'd0;
	always @(posedge clk) begin
		if (reset) begin
			st <= 2'd0; sec_wr <= 0;
		end else if (start) begin
			st <= 2'd1; m <= mode; raddr <= base; idx <= 11'd0; sec_wr <= 0;
		end else case (st)
		2'd1: st <= 2'd2;                                 // ring word raddr is read in this clock
		2'd2: if (m != 2'd2 || ext_ok) begin
			sec_data <= m == 2'd0 ? rq : m == 2'd2 ? ext_q : 16'h0000;
			sec_wr <= 1; st <= 2'd3;
		end
		2'd3: if (!sec_wait) begin                        // taken at this edge
			sec_wr <= 0;
			if (idx == 11'd1175) st <= 2'd0;
			else begin idx <= idx + 11'd1; raddr <= raddr + 14'd1; st <= 2'd1; end
		end
		default: st <= 2'd0;
		endcase
	end
endmodule

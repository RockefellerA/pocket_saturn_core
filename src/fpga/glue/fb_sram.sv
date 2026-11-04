// A5 (work/a5, 2026-11-01): the SRAM driven as the real part. Hardware test 2 found the A2 / A3 fb_sram (written for a
// ~10 ns part: read word sampled 26 ns after the address, WE# low for 8.7 ns) failing every pass on the Pocket's SRAM,
// which is an AS6C2016-55BIN (Analogue's openfpga "External Hardware" page: 128K x 16, asynchronous, 3.3 V, 55 ns; CE#
// is not an FPGA pin). Datasheet (AS6C2016 v1.1, -55): read tAA <= 55, tRC >= 55; write tWC >= 55, tCW >= 50,
// tWP >= 45, tDW >= 25, tWR >= 0. Assumed (rows not confirmed): tAW >= 50, tOE <= 30, tOHZ <= 30 (output disable after
// OE# high; covered up to tOE), tAS >= 0, tDH >= 0; tOH is NOT relied on.
//
// fb_sram: one VDP1 frame buffer in the SRAM (128K words = one 512 x 256 x 16 buffer), behind the same command interface
// as psram_phy. clk = clk_ram (106.75-114.55 MHz); the waveform is fixed in clk_ram counts and designed at the fastest,
// T = 8.730 ns. Every SRAM pin is an I/O-cell register (core_constraints.sdc: each pin follows its register within
// sram_tco = 10 ns of the edge, the outputs' skew <= 4 ns, + 0.5 ns board = 4.5 ns "skew" below), so a pin changes only
// at a clk_ram edge. Edges of one word: E0 (the word's first edge), E1, ...
//   READ  word, 9 clk: E0 address, UB# / LB# low, DQ released; E1 OE# low (if it was high); E8 the word is captured
//         (rd_data: 8 clk = 69.84 ns >= 10 (tco) + 0.5 + 55 (tAA) + 0.5 + the input path; OE# low 7 clk = 61.1 ns >=
//         10 + 0.5 + 30 (tOE) + 0.5 + the input path); E9 the next word's address, or the end. No pin that affects the
//         read data (address, OE#, UB#, LB#, WE#, the DQ enable) changes at the capture edge: they change at E9 or
//         later, so the captured word does not depend on tOH (core_constraints.sdc: setup 8 clk, hold one clk before).
//   WRITE word, 8 clk: E0 address, UB# / LB#, data, DQ driven; E1 WE# low; E7 WE# high; E8 the next word (address,
//         byte enables, data) or the end (DQ released, UB# / LB# high). tWP = 6 clk - 4.5 = 47.9 >= 45; tAW = 7 clk -
//         4.5 = 56.6 >= 50 (also >= 55 if tAW = tWC); tAS, tWR, tDH = 1 clk - 4.5 = 4.2 >= 0; tDW = 7 clk - 4.5;
//         tWC = 8 clk - 4.5 = 65.3 >= 55.
//   The first write word after OE# was low in the last 3 clk takes 9 clk: E0 address, UB# / LB#, OE# high; E2 WE# low;
//         E4 DQ driven (4 clk = 34.9 - 4.5 = 30.4 >= tOHZ: no contention); E8 WE# high (tDW = 4 clk - 4.5 = 30.4 >= 25,
//         tWP = 6 clk); E9 the next word, which is a plain 8 clk one.
//   A read after a write: DQ is released at the read's E0 (the write's last edge, 1 clk after WE# rose), OE# falls at
//         E1, one clk after DQ was released.
//   OE# goes high at the end of every read command; WE# is high and DQ released whenever no write word is in progress.
// A command is taken when idle or in the last clk of the command before (its first edge is that command's last one).
// Throughput at 114.55 MHz: reads 12.7 M words / s (9 clk), writes 14.3 M words / s (8 clk); at 106.75 MHz 11.9 / 13.3.
// (A2 / A3's version: 3 clk per word, 38 M words / s, for a 10 ns part.)
module fb_sram (
	input  logic        clk,
	input  logic        rst,

	input  logic        cmd_valid,
	output logic        cmd_ready,
	input  logic        cmd_we,
	input  logic [16:0] cmd_addr,
	input  logic  [4:0] cmd_len,

	output logic        wd_pop,
	input  logic [15:0] wd_data,
	input  logic  [1:0] wd_be,

	output logic        rd_valid,
	output logic [15:0] rd_data,
	output logic        rd_last,

	output logic [16:0] s_a,
	output logic [15:0] s_dq_out,
	output logic        s_dq_oe,
	input  logic [15:0] s_dq_in,
	output logic        s_oe_n,
	output logic        s_we_n,
	output logic        s_ub_n,
	output logic        s_lb_n
);
	typedef enum logic [1:0] { S_IDLE, S_RD, S_WR } st_t;
	st_t         st;
	logic  [3:0] cnt;          // clk within the word (the edge that ends clk n is E(n+1))
	logic  [3:0] wlast;        // a write word's last clk: 7, or 8 for the first write word after OE# was low
	logic        wslow;        // this write word has the turnaround timing (WE# low at E2, DQ driven at E4)
	logic  [4:0] left;         // words left after the current one
	logic  [1:0] ohz;          // clk OE# has been high (saturating at 3): a write may drive DQ at its E0 when 3 and high
	logic        end_cmd;      // this clk is the command's last (its last word's last clk); registered one clk ahead

	wire last_rd  = (st == S_RD) && (cnt == 4'd8);     // a read word's last clk
	wire last_wr  = (st == S_WR) && (cnt == wlast);    // a write word's last clk
	assign cmd_ready = (st == S_IDLE) || end_cmd;
	wire take     = cmd_valid && cmd_ready;
	wire wfast    = s_oe_n && (ohz == 2'd3);           // OE# high for >= 4 clk at the new write's E0
	assign wd_pop = (take && cmd_we) || (last_wr && (left != 5'd0));

	always_ff @(posedge clk) begin
		rd_valid <= 1'b0;
		rd_last  <= 1'b0;
		ohz <= !s_oe_n ? 2'd0 : (ohz == 2'd3) ? 2'd3 : ohz + 2'd1;
		// the next clk is the command's last: the last word's second-to-last clk now (a word is >= 8 clk, and nothing
		// is taken before a command's last clk, so no take can change this)
		end_cmd <= !rst && (left == 5'd0) && (((st == S_RD) && (cnt == 4'd7)) || ((st == S_WR) && (cnt == wlast - 4'd1)));
		if (rst) begin
			st <= S_IDLE; s_oe_n <= 1'b1; s_we_n <= 1'b1; s_dq_oe <= 1'b0; s_ub_n <= 1'b1; s_lb_n <= 1'b1;
			cnt <= '0; left <= '0; wslow <= 1'b0; wlast <= 4'd7; ohz <= 2'd0;
		end else begin
			// the word in progress
			case (st)
				S_RD: begin
					cnt <= cnt + 4'd1;
					if (cnt == 4'd0) s_oe_n <= 1'b0;                                   // E1: OE# low
					if (cnt == 4'd7) begin                                             // E8: capture
						rd_valid <= 1'b1; rd_data <= s_dq_in; rd_last <= (left == 5'd0);
					end
					if (last_rd && left != 5'd0) begin                                 // E9: the next word
						cnt <= '0; left <= left - 5'd1; s_a <= s_a + 17'd1;
					end
				end
				S_WR: begin
					cnt <= cnt + 4'd1;
					if (cnt == (wslow ? 4'd1 : 4'd0)) s_we_n <= 1'b0;                 // E1 (E2): WE# low
					if (wslow && cnt == 4'd3) s_dq_oe <= 1'b1;                         // (E4): DQ driven
					if (cnt == wlast - 4'd1) s_we_n <= 1'b1;                           // E7 (E8): WE# high
					if (last_wr && left != 5'd0) begin                                 // E8 (E9): the next word
						cnt <= '0; left <= left - 5'd1; s_a <= s_a + 17'd1; wslow <= 1'b0; wlast <= 4'd7;
						s_dq_out <= wd_data; s_ub_n <= !wd_be[1]; s_lb_n <= !wd_be[0];
					end
				end
				default: ;
			endcase
			// a new command (idle, or the last clk of the command before): this edge is its E0
			if (take) begin
				s_a <= cmd_addr; left <= cmd_len; cnt <= '0;
				if (cmd_we) begin
					st <= S_WR; s_oe_n <= 1'b1; s_dq_out <= wd_data; s_ub_n <= !wd_be[1]; s_lb_n <= !wd_be[0];
					s_dq_oe <= wfast; wslow <= !wfast; wlast <= wfast ? 4'd7 : 4'd8;
				end else begin
					st <= S_RD; s_dq_oe <= 1'b0; s_ub_n <= 1'b0; s_lb_n <= 1'b0;     // OE# low at E1
				end
			end else if (end_cmd) begin
				// the end: release the bus (WE# is high already)
				st <= S_IDLE; s_oe_n <= 1'b1; s_dq_oe <= 1'b0; s_ub_n <= 1'b1; s_lb_n <= 1'b1;
			end
		end
	end
endmodule

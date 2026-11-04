// pk_save: backup saves for the Saturn Pocket top (work/pocket, P2; glue/REPORT 6), after sotn's pocket_memcard.
// Two APF nonvolatile data slots in MiSTer's .sav byte layout (every 16-bit word {0xFF, data byte}):
//   slot SLOT_INT  (bridge 0x10000000, 64 KB)  the internal backup RAM (32 KB), PSRAM 0 words 0x140000..
//   slot SLOT_CART (bridge 0x20000000, 1 MB)   the backup cartridge (512 KB), PSRAM 0 die 1 words 0x400000..
// (MiSTer keeps both in one .sav: internal 64 KB, then the cartridge's 1 MB when the backup cartridge is selected.)
// Loading: APF writes the files before the core runs, through pk_loader (same windows).
// Saving: APF reads the slots back through the bridge (on exit). As in pocket_memcard / agg23's data_unloader, the
// word at the address of a bridge read is fetched when bridge_rd pulses and presented on rd_data for APF's next read
// (io_bridge_peripheral answers a read with the bus value it took before pulsing pmp_rd); the next word is prefetched,
// so a sequential read normally costs only the clock crossings. Reads go through psram0_arb's backup port (bsram:
// 8-word line buffer, or one word with the arbiter's LEAN option): two 16-bit reads per bridge word, returned as
// {word 2k+1 [7:0], [15:8], word 2k [7:0], [15:8]} (file byte 4k = word 2k's high byte, bridge_endian_little = 1).
// Data slot table sizes (APF saves a nonvolatile slot with the size in its table entry; 0 = not saved): while the core
// is held in reset and APF is not loading (port a of the table is then free: the CD source reads it only while the
// core runs), the size words of both entries are written once per reset: SLOT_INT 64 KB always (a save is made even
// when none was loaded, as sotn's memory card); SLOT_CART 1 MB with the backup cartridge selected, else 0, so that a
// cartridge ROM (which APF loads into the same die-1 area) is never written into the backup cartridge's file (MiSTer
// saves the cartridge part only with the backup cartridge selected).
// (P3 fix 2) ... and written again, while the core is still held, whenever the cartridge type differs from the one the
// last write used or APF writes its data slot table (bridge 0xF8002000-0xF8003FFF): APF may deliver the persisted
// Cartridge setting, or its own table (which carries the file sizes), after Data slot all complete; written only once
// right after all complete, the cartridge entry then kept 0 and the backup cartridge was never saved (P3 bench).
// Crossings: bridge read request clk_74a -> clk_ram by a toggle (3-flop synchroniser) with the word index held stable;
// the answer clk_ram -> clk_74a by a toggle (2-flop) with the data word held stable (core_constraints.sdc).
// (A1, area; the same words, answers and backup-port reads in the same clocks) No copy of the prefetched word's index:
// while the prefetch is valid the fetch engine idles, and the index it fetched is still in cur. The first 16-bit half
// of a fetch goes straight into the low half of the prefetch buffer (pf_data is not valid during any fetch: every
// request clears pf_valid before its fetch starts), from which a miss's answer also takes it. The backup-port address
// is wired from cur / half instead of registered in F_REQ: the arbiter uses it only in the clk of the read request
// (bsram_rd high, F_W1) and through its registered word select while the fetch waits (F_W1 / F_W2), and cur / half
// do not change from F_REQ to the end of F_W2.
`default_nettype none
module pk_save #(
	parameter int SLOT_INT  = 2,           // data.json index of the internal backup RAM slot
	parameter int SLOT_CART = 3            // data.json index of the backup cartridge slot
) (
	input  wire        clk_74a,
	input  wire [31:0] bridge_addr,
	input  wire        bridge_rd,
	input  wire        bridge_wr,          // (P3 fix 2) APF's data slot table writes re-arm the size writes
	output reg  [31:0] rd_data = 32'd0,    // clk_74a: bridge read data for 0x1xxxxxxx / 0x2xxxxxxx
	input  wire        table_ok,           // clk_74a: core held in reset, APF not loading
	input  wire [ 2:0] cart_type,          // clk_74a
	output reg  [ 9:0] dt_addr = 10'd0,    // data slot table port a (while dt_active)
	output reg         dt_wren = 1'b0,
	output reg  [31:0] dt_data = 32'd0,
	output wire        dt_active,

	input  wire        clk_ram,
	input  wire        rst,                // clk_ram (power-on of the memory glue)
	output wire [20:1] bsram_addr,         // psram0_arb backup port: [20] cartridge, [19:1] / [15:1] word offset
	output reg         bsram_rd = 1'b0,
	input  wire [15:0] bsram_dout,
	input  wire        bsram_busy
);
	// ---------------------------------------------------------------- clk_74a: bridge reads
	reg        rd_1 = 1'b0, req_tgl = 1'b0;
	reg [18:0] req_word = 19'd0;           // {cartridge, 32-bit word index [17:0]} (internal: 14 bits used)
	reg  [2:0] ack_s = 3'd0;
	reg [31:0] ans;                        // clk_ram register, stable when the ack toggle is seen
	reg        ack_tgl = 1'b0;
	always @(posedge clk_74a) begin
		rd_1 <= bridge_rd;
		if (bridge_rd && !rd_1 && (bridge_addr[31:28] == 4'h1 || bridge_addr[31:28] == 4'h2)) begin
			req_word <= {bridge_addr[29], bridge_addr[31:28] == 4'h2 ? bridge_addr[19:2] : {4'd0, bridge_addr[15:2]}};
			req_tgl  <= ~req_tgl;
		end
		ack_s <= {ack_s[1:0], ack_tgl};
		if (ack_s[2] != ack_s[1]) rd_data <= ans;
	end

	// ---------------------------------------------------------------- clk_74a: table sizes
	reg [4:0] tw_cnt = 5'd0;               // wait after table_ok, then write
	reg [1:0] tw_st = 2'd0;                // 0 wait, 1 internal, 2 cartridge, 3 done
	reg [2:0] tw_ct = 3'd0;                // (P3 fix 2) the cartridge type the last cartridge-size write used
	wire      tw_redo = (tw_st == 2'd3 && cart_type != tw_ct) || (bridge_wr && bridge_addr[31:13] == 19'h7C001);
	always @(posedge clk_74a) begin
		dt_wren <= 1'b0;
		if (!table_ok || tw_redo) begin
			tw_cnt <= 5'd0; tw_st <= 2'd0;
		end else case (tw_st)
			2'd0: begin tw_cnt <= tw_cnt + 5'd1; if (&tw_cnt) tw_st <= 2'd1; end
			2'd1: begin dt_addr <= 10'(2 * SLOT_INT + 1);  dt_data <= 32'h0001_0000; dt_wren <= 1'b1; tw_st <= 2'd2; end
			2'd2: begin dt_addr <= 10'(2 * SLOT_CART + 1); dt_data <= (cart_type == 3'd5) ? 32'h0010_0000 : 32'h0;
			            tw_ct <= cart_type; dt_wren <= 1'b1; tw_st <= 2'd3; end
			default: ;
		endcase
	end
	assign dt_active = table_ok && tw_st != 2'd0;

	// ---------------------------------------------------------------- clk_ram: fetch, prefetch
	reg  [2:0] req_s = 3'd0;
	reg [18:0] cur;                        // word being fetched
	reg        cur_pf;                     // ... as the prefetch
	reg        pf_valid = 1'b0;            // pf_data holds word cur (A1: no separate index register)
	reg [31:0] pf_data;                    // (A1) [15:0] also holds the first half of the fetch in progress
	reg        half;                       // 0: PSRAM word 2k, 1: 2k + 1
	reg  [2:0] st = 3'd0;
	localparam F_IDLE = 3'd0, F_REQ = 3'd1, F_W1 = 3'd2, F_W2 = 3'd3, F_DONE = 3'd4;
	wire req_new = req_s[2] != req_s[1];
	reg  req_pend = 1'b0;
	always @(posedge clk_ram) begin
		req_s <= {req_s[1:0], req_tgl};
		if (req_new) req_pend <= 1'b1;
		if (rst) begin
			st <= F_IDLE; bsram_rd <= 1'b0; pf_valid <= 1'b0; req_pend <= 1'b0;
		end else case (st)
			F_IDLE: if (req_pend || req_new) begin
				req_pend <= 1'b0;
				if (pf_valid && cur == req_word) begin
					// prefetch hit: answer, prefetch the next word
					ans <= pf_data; ack_tgl <= ~ack_tgl;
					cur <= req_word + 19'd1; cur_pf <= 1'b1; pf_valid <= 1'b0; half <= 1'b0; st <= F_REQ;
				end else begin
					cur <= req_word; cur_pf <= 1'b0; pf_valid <= 1'b0; half <= 1'b0; st <= F_REQ;
				end
			end
			F_REQ: begin
				bsram_rd <= 1'b1; st <= F_W1;
			end
			F_W1: begin bsram_rd <= 1'b0; st <= F_W2; end          // busy (a line fill) shows from the next clk
			F_W2: if (!bsram_busy) begin
				if (!half) begin
					pf_data[15:0] <= {bsram_dout[7:0], bsram_dout[15:8]}; half <= 1'b1; st <= F_REQ;
				end else if (cur_pf) begin
					pf_data[31:16] <= {bsram_dout[7:0], bsram_dout[15:8]};
					pf_valid <= 1'b1; st <= F_IDLE;
				end else begin
					ans <= {bsram_dout[7:0], bsram_dout[15:8], pf_data[15:0]};
					ack_tgl <= ~ack_tgl;
					cur <= cur + 19'd1; cur_pf <= 1'b1; half <= 1'b0; st <= F_REQ;
				end
			end
			default: st <= F_IDLE;
		endcase
	end
	assign bsram_addr = cur[18] ? {1'b1, cur[17:0], half} : {5'd0, cur[13:0], half};
endmodule
`default_nettype wire

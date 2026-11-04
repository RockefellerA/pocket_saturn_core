// Pocket CD disc source (glue/cd): the sector ring. SLOTS raw sectors (2352 bytes each, slot s at bridge byte
// offset s * 2352) that APF's "data slot read" target commands write through the bridge (clk_74a), read back on
// clk_sys as the 16-bit words of CDB_HLE's SEC_DATA format (word k of a sector = {byte 2k + 1, byte 2k}).
//
// Write side: a bridge write to BASE << 28 + byte offset (offset < 32 KB) stores the 32-bit word as it comes: the
// bridge's address / data / write registers (io_bridge_peripheral) feed the block RAM's input registers, no logic but
// the window decode. BRIDGE_LE: core_top's bridge_endian_little (1 as in the sotn PSX core: file byte 4k in
// bridge_wr_data[7:0]).
// Read side: 16-bit word raddr (raddr[0] picks the half of the 32-bit RAM word), one clock after the address.
//
// Block RAM: SLOTS * 588 32-bit words. 6 slots = 3,528 words fit 4,096 x 32 = 16 M10K in the 4096 x 2 mode with no
// depth multiplexer (max_depth 4096); 3 slots = 1,764 words fit 2,048 x 35 = 7 M10K (2048 x 5 mode).
module cd_ring #(
	parameter       SLOTS     = 6,
	parameter       BRIDGE_LE = 1,
	parameter [3:0] BASE      = 4'h4,
	parameter       MAXD      = SLOTS <= 3 ? 2048 : 4096
) (
	input              clk_74a,
	input      [31: 0] bridge_addr,
	input              bridge_wr,
	input      [31: 0] bridge_wr_data,

	input              clk,
	input      [13: 0] raddr,
	output     [15: 0] q
);
	localparam WORDS = SLOTS * 588;
	localparam AW    = $clog2(WORDS);

	(* ramstyle = "M10K, no_rw_check", max_depth = MAXD *) reg [31:0] ram[0:WORDS-1];

	wire        we = bridge_wr && bridge_addr[31:28] == BASE && bridge_addr[27:15] == 13'd0;
	wire [31:0] wd = BRIDGE_LE ? bridge_wr_data
	                           : {bridge_wr_data[7:0], bridge_wr_data[15:8], bridge_wr_data[23:16], bridge_wr_data[31:24]};
	always @(posedge clk_74a) if (we) ram[bridge_addr[AW+1:2]] <= wd;

	reg [31:0] q32;
	reg        half;
	always @(posedge clk) begin
		q32 <= ram[raddr[AW:1]];
		half <= raddr[0];
	end
	assign q = half ? q32[31:16] : q32[15:0];
endmodule

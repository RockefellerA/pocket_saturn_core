// Pocket CD disc source, design B (glue/cd/REPORT.txt): the CD block HLE's firmware (glue/cd/fw_cdb cd_src.c) is
// the source. It reads APF's data slot table, builds the TOC itself (from the .cue, or by convention), keeps a ring of
// sectors filled with APF "data slot read" commands it issues (read-ahead, seek hints from the drive model), and has
// each sector the drive reads streamed from the ring into the CD RAM page of the request through CDB_HLE's SEC_*
// port. This module is the hardware it needs: registers on CDB_HLE's EXT I/O port (glue/cd/cdb_hle_extio.diff), the
// clock crossing to core_bridge_cmd (cd_apf), the ring (cd_ring) and the streamer (cd_stream).
//
// Firmware words (CDB_HLE I/O 0x60-0x7C, EXT_A = word 0-7):
//   0x60 W ID      {data slot id [15:0]}                   R STATUS {SLOTS[27:24], 0xCD[23:16], err[6:4], disc_in[3],
//                                                                    0, dt_busy[1], cmd_busy[0]} (busy from the write on)
//   0x64 W OFFSET  byte offset in the slot's file          R DTQ    the data slot table word last read
//   0x68 W DEST    {length in bytes [31:16], ring byte offset [15:0]} (the bridge writes go to BASE << 28 + offset)
//   0x6C W START   start the data slot read (ID / OFFSET / DEST held until STATUS.cmd_busy falls)
//   0x70 W DTADDR  {table word [9:0]}: read the data slot table (entry e: id at word 2e, size at 2e + 1)
//   0x74 W DISC    {disc_in [0]}: CDB_HLE's DISC_IN (the firmware's TOC is ready)
//   0x78 W AREA    {area code [3:0]}: the disc's SMPC area code from its system ID (0: none), once per scan, before
//                  DISC; out on area with area_wr for one clock (pk_settings: Region = Auto)
// Sector requests: the firmware writes the page to IO_SEC_PAGE and, in place of an LBA, IO_SEC_LBA = {zero sector[23],
// ring word address [13:0]} (slot s: word s * 1176); CDB_HLE passes it on SEC_LBA with SEC_REQ.
// Clocks: clk_sys (registers, streamer, ring read), clk_74a (APF side of cd_apf, ring write).
module cd_src_b #(
	parameter       SLOTS     = 6,
	parameter       BRIDGE_LE = 1,
	parameter [3:0] BASE      = 4'h4
) (
	input              clk,                // clk_sys
	input              rst_n,              // RST_N (power-on; not the CD block's RES_N)

	input              ext_we,             // CDB_HLE EXT port
	input      [ 2: 0] ext_a,
	input      [31: 0] ext_wd,
	output     [31: 0] ext_rd,

	output reg         disc_in,
	output reg [ 3: 0] area = 4'h0,
	output reg         area_wr = 1'b0,
	input              sec_req,
	input      [23: 0] sec_lba,
	output             sec_wr,
	output     [15: 0] sec_data,
	input              sec_wait,

	input              clk_74a,
	output     [ 9: 0] datatable_addr,
	input      [31: 0] datatable_q,
	output             dsr_read,
	output     [15: 0] dsr_id,
	output reg [31: 0] dsr_offset,
	output     [31: 0] dsr_bridgeaddr,
	output     [31: 0] dsr_length,
	input              dsr_done,
	input      [ 2: 0] dsr_err,
	input      [31: 0] bridge_addr,
	input              bridge_wr,
	input      [31: 0] bridge_wr_data
);
	reg  [ 7:0] id;                         // (data slot ids < 256: data.json's are 14..47)
	reg  [14:0] dest, len;                  // (the ring is < 32 KB)
	reg  [ 5:0] dt_addr;                    // (APF's table: 32 entries = words 0..63)
	reg         dt_rd, cmd_start;
	wire        dt_busy, cmd_busy;
	wire [31:0] dt_q;
	wire [ 2:0] cmd_err;

	always @(posedge clk) begin
		dt_rd <= 0; cmd_start <= 0; area_wr <= 0;
		if (!rst_n) disc_in <= 0;
		else if (ext_we) case (ext_a)
			3'd0: id <= ext_wd[7:0];
			3'd1: dsr_offset <= ext_wd;
			3'd2: begin dest <= ext_wd[14:0]; len <= ext_wd[30:16]; end
			3'd3: cmd_start <= 1;
			3'd4: begin dt_addr <= ext_wd[5:0]; dt_rd <= 1; end
			3'd5: disc_in <= ext_wd[0];
			3'd6: begin area <= ext_wd[3:0]; area_wr <= 1; end
			default:;
		endcase
	end
	assign dsr_id         = {8'h00, id};
	assign dsr_bridgeaddr = {BASE, 13'h0000, dest};
	assign dsr_length     = {17'h00000, len};
	assign ext_rd = ext_a[0] ? dt_q : {4'd0, 4'(SLOTS), 8'hCD, 9'd0, cmd_err, disc_in, 1'b0, dt_busy | dt_rd, cmd_busy | cmd_start};

	cd_apf apf (
		.clk(clk), .dt_rd(dt_rd), .dt_addr({4'd0, dt_addr}), .dt_busy(dt_busy), .dt_q(dt_q),
		.cmd_start(cmd_start), .cmd_busy(cmd_busy), .cmd_err(cmd_err),
		.clk_74a(clk_74a), .datatable_addr(datatable_addr), .datatable_q(datatable_q),
		.dsr_read(dsr_read), .dsr_done(dsr_done), .dsr_err(dsr_err)
	);

	wire [13:0] raddr;
	wire [15:0] rq;
	cd_ring #(.SLOTS(SLOTS), .BRIDGE_LE(BRIDGE_LE), .BASE(BASE)) ring (
		.clk_74a(clk_74a), .bridge_addr(bridge_addr), .bridge_wr(bridge_wr), .bridge_wr_data(bridge_wr_data),
		.clk(clk), .raddr(raddr), .q(rq)
	);

	cd_stream stream (
		.clk(clk), .reset(!rst_n), .start(sec_req), .mode(sec_lba[23] ? 2'd1 : 2'd0), .base(sec_lba[13:0]),
		.raddr(raddr), .rq(rq), .idx(), .ext_q(16'h0000), .ext_ok(1'b1),
		.sec_wr(sec_wr), .sec_data(sec_data), .sec_wait(sec_wait), .busy()
	);
endmodule

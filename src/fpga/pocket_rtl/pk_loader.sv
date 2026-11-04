// pk_loader: APF data slots -> PSRAM 0 through psram0_arb's loader port (work/pocket, P2; glue/REPORT 6), in place of
// MiSTer's ioctl downloads (BIOS, cartridge ROM) and its backup-RAM load FSM (emu, Saturn_MiSTer/Saturn.sv).
//
// APF writes each non-deferred data slot as 32-bit bridge writes (clk_74a) at the slot's address (data.json), file
// byte 4k in bridge_wr_data[7:0] (bridge_endian_little = 1). Windows -> PSRAM 0 word addresses (glue/REPORT 1.2):
//   0x00000000 + 512 KB   BIOS                    -> 0x100000 + offset / 2
//   0x10000000 + 64 KB    internal backup RAM     -> 0x140000 + offset / 2   (MiSTer .sav layout, see below)
//   0x20000000 + 1 MB     cartridge backup RAM    -> 0x400000 + offset / 2   (die 1, start of the cartridge area)
//   0x30000000 + 8 MB     cartridge ROM           -> 0x400000 + offset / 2   (die 1; MiSTer IO_ADDR {1, addr})
// Each bridge word = two 16-bit PSRAM words, big-endian as the SH-2 reads them (MiSTer: IO_DATA = {byte 2k, 2k + 1}):
// word 2k = {byte 4k, byte 4k+1}, word 2k+1 = {byte 4k+2, byte 4k+3}. Backup images (MiSTer's .sav: every 16-bit
// word {0xFF, data byte}) are written as MiSTer's bsram port does: {8'hFF, byte 2k+1}.
// Crossing: a dual-clock FIFO (dcfifo) clk_74a -> clk_ram; the clk_ram side writes one word per loader-port request
// (rising edge of bios_wr, then wait while bios_busy: the arbiter takes the held address, data and byte enables at
// the PSRAM access; bios_wr drops once it has). ~15 clk_ram per word: two words per bridge write well inside APF's
// pace (~1.2 us per write measured by the sotn port). busy: words waiting or a write running (the core is held in
// reset meanwhile, pk_reset). overflow (sticky, clk_74a): a write found the FIFO full (never expected).
// (A1, area) One FIFO entry per bridge word, {word address [22:1] of the pair, word 2k+1, word 2k} (54 bits, 256
// entries = 2 M10K), written straight from the bridge registers at the bridge_wr clock (before: two 39-bit entries per
// bridge word through two 39-bit staging registers, 1 M10K); the clk_ram side writes the entry's two words in turn
// and takes address and data from the FIFO's output (q holds the last read word until the next rdreq), so no copy of
// them is kept. The two port writes keep the old request spacing (bios_wr low for 3 clk_ram between them, as the old
// S_IDLE / S_RD / S_SET path for the second entry); the PSRAM gets the same words in the same order. The loader runs
// only while the core is held in reset (it drains within ~35 clk_sys of a bridge write, long before APF's next
// command), so the core and APF see no difference (P3 checks 1-3).
// (A2, timing) underflow_checking OFF: the FIFO's read side no longer gates rdreq with its own empty compare (the
// rdptr_g -> rdempty -> read-counter path). rdreq (f_rd) is a one-clk pulse set only in S_IDLE when !f_empty; this
// module is the FIFO's only reader and writes only add words, so the FIFO is never empty when f_rd is high, and the
// gate never acted (bench model: a read while empty is reported).
// (A7, work/a7, `define A7_FIX; without it the file is A6's) A save slot that APF fills because no save file exists yet
// (data.json parameters 0xA4, bit 5 "Initialize nonvolatile data on load": "otherwise the slot's memory is overwritten
// with 0xFF's up to size_maximum") is stored as the formatted empty backup RAM instead: all 0xFF data reads as a full
// memory (0 free blocks) and the BIOS does not reformat it. Formatted empty = data bytes 0 .. H-1 "BackUpRam Format"
// repeated, every other data byte 0x00 (the pad bytes stay 0xFF: the .sav layout {0xFF, data}); H = 64 for the internal
// backup RAM (slot 2: what the BIOS's clear writes; Yabause FormatBackupRam, Mednafen's power-on image), H = 512 for the
// backup cartridge (slot 3: its 512-byte block; Mednafen CART_Backup_Init). The fill is recognised by the image's first
// data byte (file byte 1, at window offset 0) = 0xFF (a formatted backup RAM always starts with 'B'); the decision is
// taken at the write of offset 0 (used for that write) and kept for the window's later writes (APF writes a slot from
// its address upwards). Any other image goes to PSRAM 0 byte for byte as before; only the data byte of the save windows'
// words changes, at the same addresses, in the same order and clocks (pk_save's read-back is not touched).
`default_nettype none
module pk_loader (
	input  wire        clk_74a,
	input  wire [31:0] bridge_addr,
	input  wire        bridge_wr,
	input  wire [31:0] bridge_wr_data,
	output reg         overflow = 1'b0,

	input  wire        clk_ram,
	input  wire        rst,                 // clk_ram (power-on of the memory glue)
	output wire [23:1] bios_addr,           // psram0_arb loader port: raw PSRAM 0 word address {die, A[21:0]}
	output wire [15:0] bios_din,
	output reg  [ 1:0] bios_wr = 2'b00,
	input  wire        bios_busy,
	output wire        busy
);
	// ---------------------------------------------------------------- clk_74a: window decode, one FIFO write
	wire [3:0] win     = bridge_addr[31:28];
	wire       w_bios  = win == 4'h0 && bridge_addr[27:19] == 9'd0;
	wire       w_bkint = win == 4'h1 && bridge_addr[27:16] == 12'd0;
	wire       w_bkcrt = win == 4'h2 && bridge_addr[27:20] == 8'd0;
	wire       w_cart  = win == 4'h3 && bridge_addr[27:23] == 5'd0;
	wire       w_save  = w_bkint | w_bkcrt;
	wire [22:0] base   = w_bios ? 23'h100000 : w_bkint ? 23'h140000 : 23'h400000;
	wire [22:0] a0     = base | {1'b0, bridge_addr[22:2], 1'b0};   // (each window's offset bits above it are 0)
`ifdef A7_FIX
	// (A7) APF's "no save yet" fill -> the formatted empty image (header). Window offset 4k carries data bytes 2k (word 2k)
	// and 2k + 1 (word 2k + 1): "BackUpRam Format"[2k mod 16] / [2k + 1 mod 16] = the k mod 8-th even / odd letter.
	reg        fill_int = 1'b0, fill_crt = 1'b0;          // the window's image is APF's fill (decided at offset 0)
	wire       off0_int = w_bkint && bridge_addr[15:2] == 14'd0;
	wire       off0_crt = w_bkcrt && bridge_addr[19:2] == 18'd0;
	wire       ff0      = bridge_wr_data[15:8] == 8'hFF;  // file byte 1 = the first data byte
	wire       fill     = w_bkint ? (off0_int ? ff0 : fill_int) : (off0_crt ? ff0 : fill_crt);
	wire       hdr      = w_bkint ? bridge_addr[15:7] == 9'd0 : bridge_addr[19:10] == 10'd0;   // data byte 2k + 1 < 64 / < 512
	reg  [7:0] f_ev, f_od;
	always @* case (bridge_addr[4:2])
		3'd0: begin f_ev = 8'h42; f_od = 8'h61; end   // B a
		3'd1: begin f_ev = 8'h63; f_od = 8'h6B; end   // c k
		3'd2: begin f_ev = 8'h55; f_od = 8'h70; end   // U p
		3'd3: begin f_ev = 8'h52; f_od = 8'h61; end   // R a
		3'd4: begin f_ev = 8'h6D; f_od = 8'h20; end   // m ' '
		3'd5: begin f_ev = 8'h46; f_od = 8'h6F; end   // F o
		3'd6: begin f_ev = 8'h72; f_od = 8'h6D; end   // r m
		default: begin f_ev = 8'h61; f_od = 8'h74; end   // a t
	endcase
	wire [7:0] s0 = !fill ? bridge_wr_data[15:8]  : hdr ? f_ev : 8'h00;
	wire [7:0] s1 = !fill ? bridge_wr_data[31:24] : hdr ? f_od : 8'h00;
	always @(posedge clk_74a) if (bridge_wr) begin
		if (off0_int) fill_int <= ff0;
		if (off0_crt) fill_crt <= ff0;
	end
	wire [15:0] d0     = w_save ? {8'hFF, s0} : {bridge_wr_data[7:0],   bridge_wr_data[15:8]};
	wire [15:0] d1     = w_save ? {8'hFF, s1} : {bridge_wr_data[23:16], bridge_wr_data[31:24]};
`else
	wire [15:0] d0     = w_save ? {8'hFF, bridge_wr_data[15:8]}  : {bridge_wr_data[7:0],   bridge_wr_data[15:8]};
	wire [15:0] d1     = w_save ? {8'hFF, bridge_wr_data[31:24]} : {bridge_wr_data[23:16], bridge_wr_data[31:24]};
`endif
	wire       f_wr    = bridge_wr && (w_bios || w_save || w_cart);
	wire       f_full;
	always @(posedge clk_74a) if (f_wr && f_full) overflow <= 1'b1;

	wire        f_empty;
	reg         f_rd = 1'b0;
	wire [53:0] f_q;
	dcfifo #(
		.intended_device_family("Cyclone V"), .lpm_numwords(256), .lpm_showahead("OFF"), .lpm_type("dcfifo"),
		.lpm_width(54), .lpm_widthu(8), .overflow_checking("ON"), .rdsync_delaypipe(4), .underflow_checking("OFF"),
		.use_eab("ON"), .wrsync_delaypipe(4)
	) fifo (
		.data({a0[22:1], d1, d0}), .rdclk(clk_ram), .rdreq(f_rd), .wrclk(clk_74a), .wrreq(f_wr),
		.q(f_q), .rdempty(f_empty), .wrfull(f_full),
		.aclr(1'b0), .eccstatus(), .rdfull(), .rdusedw(), .wrempty(), .wrusedw()
	);

	// ---------------------------------------------------------------- clk_ram: one loader-port write per word
	localparam S_IDLE = 3'd0, S_RD = 3'd1, S_SET = 3'd2, S_REQ = 3'd3, S_WAIT = 3'd4, S_G1 = 3'd5, S_G2 = 3'd6;
	reg [2:0] st = S_IDLE;
	reg       hi = 1'b0;                                       // 0: word 2k of the entry, 1: word 2k + 1
	always @(posedge clk_ram) begin
		f_rd <= 1'b0;
		if (rst) begin
			st <= S_IDLE; bios_wr <= 2'b00; hi <= 1'b0;
		end else case (st)
			S_IDLE: if (!f_empty) begin f_rd <= 1'b1; st <= S_RD; end
			S_RD:   st <= S_SET;                                   // q is valid one clk after rdreq
			S_SET:  begin bios_wr <= 2'b11; st <= S_REQ; end
			S_REQ:  st <= S_WAIT;                                  // the arbiter saw the edge; busy shows from now
			// (P3 fix 1) bios_wr stays up until the arbiter has taken the word: psram0_arb takes a loader write's byte
			// enables (bios_wr) at the PSRAM access, like its address and data (held); dropped one clock after S_SET they
			// were 00 there and nothing was written (P3 bench: BIOS region of PSRAM 0 all zeros)
			S_WAIT: if (!bios_busy) begin                          // taken (address, data, enables free again)
				bios_wr <= 2'b00; hi <= ~hi;
				st <= hi ? S_IDLE : S_G1;                          // word 2k + 1 next: the same gap as before
			end
			S_G1:   st <= S_G2;
			S_G2:   st <= S_SET;
			default: st <= S_IDLE;
		endcase
	end
	assign bios_addr = {f_q[53:32], hi};
	assign bios_din  = hi ? f_q[31:16] : f_q[15:0];
	assign busy = !f_empty || st != S_IDLE;
endmodule
`default_nettype wire

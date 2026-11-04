// CD block, high-level emulation: one module in place of the SH-1 (SH7034 + CD block firmware ROM), the SH-1
// side of YGR019 and the drive link (HPS2CDD and the HPS drive emulation).
//
// - Host side: YGR019's A-bus registers with its wait timing (HIRQ, HIRQ mask, CR1-4 / results, data port with a
//   6-word FIFO).
// - A PicoRV32 (RV32I) runs the CD block emulation (fw/cdb: Mednafen's cdb.c, ported): command processing, the
//   drive (seek and read timing, subcode Q from the TOC), filters, buffer partitions, the file system and the
//   CD-DA buffer.
// - Hardware does the per-word work: the sector engine writes a requested sector into a CD RAM page, the data
//   transfer engine moves words between CD RAM pages (or CPU RAM: TOC, file info, subcode) and the host FIFO, the
//   CD-DA player reads samples from CD RAM pages at 44.1 kHz.
//
// CD RAM (512 KB, the same port as the SH-1 had): 205 pages of 2352 bytes (the firmware maps its 200 sector
// buffers, the page being read and the CD-DA queue's pages onto them) and the TOC, which the disc source writes
// at byte 0x7F000. Words are big-endian: word k of a page = {byte 2k, byte 2k+1}.
//
// Disc source: SEC_REQ (one clock) with SEC_LBA asks for a sector (LBA = FAD - 150; out of the disc: zeros);
// the source answers with 1176 SEC_WR words (byte 2k in [7:0], byte 2k+1 in [15:8]), none while SEC_WAIT is set.
// DISC_IN: a disc (and its TOC) is present.
module CDB_HLE #(
	parameter FW_FILE   = "rtl/Saturn/CD/cdb_hle_fw.hex",
	parameter RAM_WORDS = 10240
`ifdef CD_EXTIO
	,
	// (CD_EXTIO, the Pocket) the firmware RAM in two banks (CDB_HLE_RAM2): RAM_BANK0 words initialised from FW_FILE, then
	// RAM_WORDS - RAM_BANK0 more from FW_FILE1, so that the RAM can grow by less than Quartus's 16-M10K step (it maps
	// this byte-enabled RAM in groups of 4096 words); RAM_BANK0 >= RAM_WORDS: one bank, as without CD_EXTIO
	parameter RAM_BANK0 = RAM_WORDS,
	parameter FW_FILE1  = ""
`endif
) (
	input              CLK,
	input              RST_N,
	input              RES_N,          // CD block reset (SMPC)

	input              CE_R,           // A-bus clock enables
	input              CE_F,
	input              SHCE_R,         // 20 MHz (the SH-1's clock): A-bus wait timing, as in YGR019
	input              TCE,            // 11.2896 MHz (44100 x 256): the firmware's time base
	input              ACE,            // 44.1 kHz: CD-DA samples

	input      [14: 1] AA,
	input      [15: 0] ADI,
	output     [15: 0] ADO,
	input              ACS2_N,
	input              ARD_N,
	input              AWRL_N,
	input              AWRU_N,
	output             AWAIT_N,
	output             ARQT_N,

	input              DISC_IN,
	output reg         SEC_REQ,
	output reg [23: 0] SEC_LBA,
	input              SEC_WR,
	input      [15: 0] SEC_DATA,
	output             SEC_WAIT,

	output reg [18: 1] CD_RAM_A,
	output reg [15: 0] CD_RAM_D,
	output reg [ 1: 0] CD_RAM_WE,
	output reg         CD_RAM_RD,
	output reg         CD_RAM_CS,
	input      [15: 0] CD_RAM_Q,
	input              CD_RAM_RDY,

	output reg [15: 0] CD_SL,
	output reg [15: 0] CD_SR,

`ifdef SMPC_FW
	// the SMPC's MCU runs on this CPU (rtl/Saturn/SMPC/SMPC_FW.sv): I/O words 0x80-0xFF are SMPC_FW's
	output     [ 4: 0] SMPC_A,
	output             SMPC_WE,
	output     [31: 0] SMPC_WD,
	input      [31: 0] SMPC_RD,
`endif
`ifdef CD_EXTIO
	// the EXT I/O port, I/O words 0x60-0x7C (the Pocket's disc source: glue/rtl/cd_src_b.sv, fw/cdb cd_src.c): a firmware
	// write = EXT_WE for one clock with EXT_A (word 0-7) and EXT_WD; a firmware read takes EXT_RD (at EXT_A) at that
	// clock's end (I/O accesses take one clock, as the other I/O words)
	output     [ 2: 0] EXT_A,
	output             EXT_WE,
	output     [31: 0] EXT_WD,
	input      [31: 0] EXT_RD,
`endif

	input              FAST
);
	wire RESET = ~RST_N | ~RES_N;
`ifdef SMPC_FW
	// The CPU runs the SMPC too: only RST_N resets it. RES_N (CDRES_N, which the SMPC firmware drives) resets the CD
	// block's registers and engines as before, and the firmware restarts its CD part (fw/cdb: cd_restart).
	wire CPU_RESET = ~RST_N;
`else
	wire CPU_RESET = RESET;
`endif
	localparam RAM_AW = $clog2(RAM_WORDS);

	// page * 1176: a page's first word in CD RAM
	function automatic [18:1] page_word(input [7:0] page);
		page_word = {page, 10'b0} + {3'b0, page, 7'b0} + {6'b0, page, 4'b0} + {7'b0, page, 3'b0};
	endfunction

	// ------------------------------------------------------------------------------------------ declarations
	bit [15:0] CR[4], HIRQ, HMASK;
	bit  [3:0] RR_V;                                    // RR[i] written since reset (else it reads 0)
	wire [15:0] RR_Q;                                   // RR[{AA[5], AA[2]}] (MLAB, rr_ram)
	bit        CMD_PEND, RES_READ;                       // host wrote CR4 / read CR4

	bit [15:0] FIFO_Q;                                   // data port FIFO (MLAB, read at FIFO_RP)
	bit [15:0] FIFO_D;
	bit        FIFO_WE;
	bit  [2:0] FIFO_WP, FIFO_RP, FIFO_N;
	wire       FIFO_EMPTY = FIFO_N == 3'd0;
	wire       FIFO_FULL  = FIFO_N == 3'd6;
	bit        HOST_POP, HOST_PUSH, ENG_POP, ENG_PUSH;
	bit [15:0] HOST_WDATA, ENG_WDATA;

	bit        FW_HIRQ_SET;                              // firmware strobes, one clock (HIRQ bits: mem_wdata then)
	bit        FW_CLR_PEND, FW_CLR_READ;
	bit        SEC_START, DT_CLEAR, DT_START, DT_STOP, AUD_PUSH, AUD_FLUSH, DTL_WE;

	bit [31:0] TIMER;
	bit        SEC_BUSY;
	bit  [7:0] SEC_PAGE;
	bit        SEC_NOSYNC;                               // data sector: leave the sync bytes (words 0-5) alone

	bit        DT_ACT, DT_WR, DT_END, DT_LIMIT;
	bit        DT_START_WR, DT_START_RAW;
	bit [15:0] DT_RAW_ADDR, DT_RAW_CNT;                  // raw: CPU RAM byte address, word count
	bit  [1:0] GET_SECLEN, PUT_SECLEN;
	bit  [7:0] DTL_N, DTL_WA, DTL_WADDR;
	bit [17:0] DT_TOTAL;

	bit  [9:0] AUD_COUNT;
	bit  [7:0] AUD_DONE;

	bit        CW_REQ, CW_ACK;

	// CD RAM clients: sector engine, CD-DA player, data transfer, CPU window
	bit        SE_REQ, AU_REQ, DT_REQ, CW_RQ;
	bit        SE_ACK, AU_ACK, DT_ACK, CW_RACK;
	bit [18:1] SE_A, AU_A;
	bit [15:0] DT_D;
	bit  [1:0] DT_WE;
	bit [15:0] AR_Q;

	// ------------------------------------------------------------------------------------------ host interface
	wire SCU_REG_SEL = (AA[14:12] == 3'b000) & ~ACS2_N;
	bit [15:0] SCU_REG_DO;
	bit        ABUS_WAIT;
	always @(posedge CLK or negedge RST_N) begin
		bit        AWR_N_OLD, ARD_N_OLD;
		bit        ABUS_DATA_PORT, ABUS_DP_WR;
		bit [ 2:0] ABUS_WAIT_CNT;
		bit [15:0] HIRQ_CLR;

		if (!RST_N) begin
			CR <= '{4{'0}}; HIRQ <= '0; HMASK <= '0; CMD_PEND <= 0; RES_READ <= 0;
			SCU_REG_DO <= '0; ABUS_WAIT <= 0; ABUS_WAIT_CNT <= '0; ABUS_DATA_PORT <= 0; ABUS_DP_WR <= 0;
			AWR_N_OLD <= 1; ARD_N_OLD <= 1;
			HOST_POP <= 0; HOST_PUSH <= 0; HOST_WDATA <= '0;
		end else if (!RES_N) begin
			CR <= '{4{'0}}; HIRQ <= '0; HMASK <= '0; CMD_PEND <= 0; RES_READ <= 0;
			SCU_REG_DO <= '0; ABUS_WAIT <= 0; ABUS_WAIT_CNT <= '0;
			HOST_POP <= 0; HOST_PUSH <= 0;
		end else begin
			HOST_POP <= 0; HOST_PUSH <= 0;
			HIRQ_CLR = '0;
			if (CE_R) begin
				AWR_N_OLD <= AWRL_N & AWRU_N;
				ARD_N_OLD <= ARD_N;
			end
			if (SHCE_R && ABUS_WAIT_CNT) ABUS_WAIT_CNT <= ABUS_WAIT_CNT - 3'd1;

			if (SCU_REG_SEL) begin
				if ((!AWRL_N || !AWRU_N) && AWR_N_OLD && CE_F) begin
					case ({AA[5:2],2'b00})
						6'h08: HIRQ_CLR = ~ADI;
						6'h0C: HMASK <= ADI;
						6'h18: CR[0] <= ADI;
						6'h1C: CR[1] <= ADI;
						6'h20: CR[2] <= ADI;
						6'h24: begin CR[3] <= ADI; CMD_PEND <= 1; end
						default:;
					endcase
					ABUS_WAIT <= ({AA[5:2],2'b00} == 6'h00);
					ABUS_DATA_PORT <= ({AA[5:2],2'b00} == 6'h00);
					ABUS_DP_WR <= 1;
					ABUS_WAIT_CNT <= FAST ? 3'd0 : 3'd3;
				end else if (!ARD_N && ARD_N_OLD && CE_F) begin
					case ({AA[5:2],2'b00})
						6'h00: ;
						6'h08: SCU_REG_DO <= HIRQ;
						6'h0C: SCU_REG_DO <= HMASK;
						6'h18: SCU_REG_DO <= RR_V[0] ? RR_Q : 16'h0000;
						6'h1C: SCU_REG_DO <= RR_V[1] ? RR_Q : 16'h0000;
						6'h20: SCU_REG_DO <= RR_V[2] ? RR_Q : 16'h0000;
						6'h24: begin SCU_REG_DO <= RR_V[3] ? RR_Q : 16'h0000; RES_READ <= 1; end
						default: SCU_REG_DO <= '0;
					endcase
					ABUS_WAIT <= 1;
					ABUS_DATA_PORT <= ({AA[5:2],2'b00} == 6'h00);
					ABUS_DP_WR <= 0;
					ABUS_WAIT_CNT <= ({AA[5:2],2'b00} == 6'h00) ? (FAST ? 3'd2 : 3'd5) : (FAST ? 3'd1 : 3'd4);
				end
			end

			// the data port: a read takes the next FIFO word, waiting for one while the transfer has more; with no
			// read transfer it reads 0 (writes the same way round)
			if (CE_F && ABUS_WAIT && !ABUS_WAIT_CNT) begin
				if (!ABUS_DATA_PORT) ABUS_WAIT <= 0;
				else if (!ABUS_DP_WR) begin
					if (DT_ACT && !DT_WR && !FIFO_EMPTY) begin
						SCU_REG_DO <= FIFO_Q; HOST_POP <= 1; ABUS_WAIT <= 0;
					end else if (!(DT_ACT && !DT_WR) || DT_END) begin
						SCU_REG_DO <= (DT_ACT && !DT_WR) ? FIFO_Q : 16'h0000; ABUS_WAIT <= 0;
					end
				end else begin
					if (DT_ACT && DT_WR && !FIFO_FULL && !DT_LIMIT) begin
						HOST_WDATA <= ADI; HOST_PUSH <= 1; ABUS_WAIT <= 0;
					end else if (!(DT_ACT && DT_WR) || DT_LIMIT) ABUS_WAIT <= 0;
				end
			end

			HIRQ <= (HIRQ & ~HIRQ_CLR) | (FW_HIRQ_SET ? mem_wdata[15:0] : 16'h0000);
			if (FW_CLR_PEND) CMD_PEND <= 0;
			if (FW_CLR_READ) RES_READ <= 0;
		end
	end

	assign FIFO_WE = !(RESET || DT_CLEAR) && (HOST_PUSH || ENG_PUSH);
	assign FIFO_D = HOST_PUSH ? HOST_WDATA : ENG_WDATA;
	CDB_HLE_FIFO_RAM fifo_ram (.CLK(CLK), .WADDR(FIFO_WP), .WDATA(FIFO_D), .WE(FIFO_WE), .RADDR(FIFO_RP), .Q(FIFO_Q));

	assign ADO = SCU_REG_DO;
	assign AWAIT_N = ~(ABUS_WAIT & SCU_REG_SEL);
	assign ARQT_N = 1;                 // as YGR019: the CD block interrupt to the SCU is not connected

	always @(posedge CLK) begin
		if (RESET || DT_CLEAR) begin
			FIFO_WP <= '0; FIFO_RP <= '0; FIFO_N <= '0;
		end else begin
			if (HOST_PUSH || ENG_PUSH) begin
				FIFO_WP <= FIFO_WP == 3'd5 ? 3'd0 : FIFO_WP + 3'd1;
			end
			if (HOST_POP || ENG_POP) FIFO_RP <= FIFO_RP == 3'd5 ? 3'd0 : FIFO_RP + 3'd1;
			FIFO_N <= FIFO_N + {2'b00, HOST_PUSH | ENG_PUSH} - {2'b00, HOST_POP | ENG_POP};
		end
	end

	// ------------------------------------------------------------------------------------------ CPU and its RAM
	wire        mem_valid, mem_instr;
	bit         mem_ready;
	wire [31:0] mem_addr, mem_wdata;
	wire [ 3:0] mem_wstrb;
	bit  [31:0] mem_rdata;

`ifdef CDB_FEMTORV
	// The FemtoRV32 "quark" (RV32I, rtl/Saturn/CD/femtorv) in place of the PicoRV32, behind the same memory interface
	// (CDB_HLE_FEMTORV, at the end of this file): the same firmware image, executed instruction for instruction as the
	// PicoRV32 does; only the clocks per instruction differ (a little fewer).
	CDB_HLE_FEMTORV cpu (.clk(CLK), .resetn(~CPU_RESET), .mem_valid(mem_valid), .mem_instr(mem_instr), .mem_ready(mem_ready),
	     .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb), .mem_rdata(mem_rdata));
`else
	picorv32 #(.LATCHED_MEM_RDATA(1), .ENABLE_COUNTERS(0), .ENABLE_COUNTERS64(0), .ENABLE_REGS_DUALPORT(1), .TWO_STAGE_SHIFT(1),
	           .BARREL_SHIFTER(0), .COMPRESSED_ISA(0), .CATCH_MISALIGN(0), .CATCH_ILLINSN(0), .ENABLE_IRQ(0),
	           .PROGADDR_RESET(32'h0000_0000), .STACKADDR(32'hFFFF_FFFF))
	cpu (.clk(CLK), .resetn(~CPU_RESET), .trap(), .mem_valid(mem_valid), .mem_instr(mem_instr), .mem_ready(mem_ready),
	     .mem_addr(mem_addr), .mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb), .mem_rdata(mem_rdata),
	     .mem_la_read(), .mem_la_write(), .mem_la_addr(), .mem_la_wdata(), .mem_la_wstrb(),
	     .pcpi_valid(), .pcpi_insn(), .pcpi_rs1(), .pcpi_rs2(), .pcpi_wr(1'b0), .pcpi_rd(32'h0), .pcpi_wait(1'b0),
	     .pcpi_ready(1'b0), .irq(32'h0), .eoi(), .trace_valid(), .trace_data());
`endif

	wire sel_ram = mem_addr[31:28] == 4'h0;
	wire sel_cdr = mem_addr[31:28] == 4'h1;              // CD RAM: CPU word k = CD RAM word k (bits 15:0)

	// CPU RAM: the CPU writes; the read port is the CPU's except in the clocks the data transfer engine takes it
	// (DT_RREQ, raw mode: TOC, file info, subcode)
	bit [31:0] ram_q;
	bit [RAM_AW-1:0] ram_ab;
	bit        DT_RREQ;
`ifdef CD_EXTIO
	CDB_HLE_RAM2 #(.WORDS(RAM_WORDS), .AW(RAM_AW), .INIT(FW_FILE), .BANK0(RAM_BANK0), .INIT1(FW_FILE1)) ram (
`else
	CDB_HLE_RAM #(.WORDS(RAM_WORDS), .AW(RAM_AW), .INIT(FW_FILE)) ram (
`endif
		.CLK(CLK),
		.WADDR(mem_addr[RAM_AW+1:2]), .BE(mem_wstrb), .WDATA(mem_wdata),
		.WE(mem_valid && sel_ram && !mem_ready && mem_wstrb != 4'b0000),
		.RADDR(DT_RREQ ? ram_ab : mem_addr[RAM_AW+1:2]), .Q(ram_q)
	);

	always @(posedge CLK) if (RESET) TIMER <= '0; else if (TCE) TIMER <= TIMER + 32'd1;

	// ------------------------------------------------------------------------------------------ I/O registers
	// The HIRQ-set, transfer-list and CD-DA-queue writes take effect the clock after the I/O write, with the data from
	// mem_wdata: the CPU loads mem_wdata only when it starts a write, and it cannot start one in that clock.
	// 00 R flags {disc_in[31], dt_end[5], dt_wr_idle[4], dt_act[3], sec_busy[2], res_read[1], cmd_pend[0]};
	//    W 1 clears cmd_pend[0] / res_read[1]
	// 04 W HIRQ bits to set     0C R timer      10-1C R CR1-4      20-2C W results 1-4 (the firmware never reads HIRQ,
	//    the HIRQ mask or the results back, so they are not readable here: the read mux stays small)
	// 30 W LBA: read that sector into the page of 34    34 W {data (no sync bytes)[8], page[7:0]}    (38 / 3C: gone, the firmware reads sector bytes 12-19 from the page)
	// 40 W DT control {clear[4], raw[3], write[2], stop[1], start[0]}   44 W raw {count[31:16], byte address[15:0]}
	// 48 W sector lengths {put[3:2], get[1:0]}    4C R words transferred    50 W DT list entry {form2, mode1, page}
	// 54 W CD-DA {push[31], flush[30], entry[20:0]}, R {done entries[23:16], samples queued[9:0]}
	wire DT_WR_IDLE = !DT_REQ && (FIFO_EMPTY || DT_LIMIT);
	bit  RAM_RD_WAIT;
	always @(posedge CLK) begin
		mem_ready <= 0;
		FW_HIRQ_SET <= 0; FW_CLR_PEND <= 0; FW_CLR_READ <= 0;
		SEC_START <= 0; DT_START <= 0; DT_STOP <= 0; DT_CLEAR <= 0; DTL_WE <= 0;
		AUD_PUSH <= 0; AUD_FLUSH <= 0;
		RAM_RD_WAIT <= 0;
`ifdef SMPC_FW
		if (CPU_RESET) begin
			CW_REQ <= 0;
		end else if (mem_valid && !mem_ready) begin
`else
		if (RESET) begin
			CW_REQ <= 0; RR_V <= '0;
			GET_SECLEN <= '0; PUT_SECLEN <= '0; DTL_WA <= '0; DT_START_RAW <= 0; DT_START_WR <= 0;
			SEC_PAGE <= '0; SEC_LBA <= '0;
		end else if (mem_valid && !mem_ready) begin
`endif
			if (sel_ram) begin
				// the read data comes the clock after the address
				if (mem_wstrb != 4'b0000) mem_ready <= 1;
				else if (RAM_RD_WAIT) mem_ready <= 1;
				else if (!DT_RREQ) RAM_RD_WAIT <= 1;
				mem_rdata <= ram_q;
			end else if (sel_cdr) begin
`ifdef SMPC_FW
				// held in reset (the firmware does not access CD RAM then): answer, so that the CPU never waits for it
				if (RESET) begin mem_ready <= 1; mem_rdata <= '0; end else
`endif
				if (!CW_REQ) CW_REQ <= 1;
				else if (CW_ACK) begin CW_REQ <= 0; mem_ready <= 1; mem_rdata <= {16'h0000, AR_Q}; end
			end else begin
				mem_ready <= 1;
`ifdef SMPC_FW
				if (mem_addr[7]) mem_rdata <= SMPC_RD; else
`endif
				case (mem_addr[7:2])
					6'h00: mem_rdata <= {DISC_IN, 25'h0, DT_END, DT_WR_IDLE, DT_ACT, SEC_BUSY, RES_READ, CMD_PEND};
					6'h03: mem_rdata <= TIMER;
					6'h04: mem_rdata <= {16'h0, CR[0]};
					6'h05: mem_rdata <= {16'h0, CR[1]};
					6'h06: mem_rdata <= {16'h0, CR[2]};
					6'h07: mem_rdata <= {16'h0, CR[3]};
					6'h13: mem_rdata <= {14'h0, DT_TOTAL};
					6'h15: mem_rdata <= {8'h0, AUD_DONE, 6'h0, AUD_COUNT};
`ifdef CD_EXTIO
					6'h18, 6'h19, 6'h1A, 6'h1B, 6'h1C, 6'h1D, 6'h1E, 6'h1F: mem_rdata <= EXT_RD;   // 60-7C: the EXT port
`endif
					default: mem_rdata <= '0;
				endcase
				if (mem_wstrb != 4'b0000) case (mem_addr[7:2])
					6'h00: begin FW_CLR_PEND <= mem_wdata[0]; FW_CLR_READ <= mem_wdata[1]; end
					6'h01: FW_HIRQ_SET <= 1;
					6'h08, 6'h09, 6'h0A, 6'h0B: RR_V[mem_addr[3:2]] <= 1;   // the word goes into rr_ram
					6'h0C: begin SEC_LBA <= mem_wdata[23:0]; SEC_START <= 1; end
					6'h0D: begin SEC_PAGE <= mem_wdata[7:0]; SEC_NOSYNC <= mem_wdata[8]; end
					6'h10: begin
						DT_CLEAR <= mem_wdata[4];
						if (mem_wdata[4]) DTL_WA <= '0;
						DT_START <= mem_wdata[0];
						DT_STOP <= mem_wdata[1];
						DT_START_WR <= mem_wdata[2];
						DT_START_RAW <= mem_wdata[3];
					end
					6'h11: begin DT_RAW_ADDR <= mem_wdata[15:0]; DT_RAW_CNT <= mem_wdata[31:16]; end
					6'h12: begin GET_SECLEN <= mem_wdata[1:0]; PUT_SECLEN <= mem_wdata[3:2]; end
					6'h14: begin DTL_WE <= 1; DTL_WADDR <= DTL_WA; DTL_WA <= DTL_WA + 8'd1; end
					6'h15: begin AUD_PUSH <= mem_wdata[31]; AUD_FLUSH <= mem_wdata[30]; end
					default:;
				endcase
			end
		end
`ifdef SMPC_FW
		// the CD registers: reset by RES_N too (CPU writes to them while it is low are lost, as before)
		if (RESET) begin
			RR_V <= '0;
			GET_SECLEN <= '0; PUT_SECLEN <= '0; DTL_WA <= '0; DT_START_RAW <= 0; DT_START_WR <= 0;
			SEC_PAGE <= '0; SEC_LBA <= '0;
		end
`endif
	end
`ifdef SMPC_FW
	assign SMPC_A  = mem_addr[6:2];
	assign SMPC_WE = mem_valid && !mem_ready && !sel_ram && !sel_cdr && mem_wstrb != 4'b0000 && mem_addr[7] && !CPU_RESET;
	assign SMPC_WD = mem_wdata;
`endif
`ifdef CD_EXTIO
	// the EXT port: I/O words 0x60-0x7C (written as the SMPC_FW words are: one clock, also while RES_N holds the CD block)
	assign EXT_A  = mem_addr[4:2];
	assign EXT_WE = mem_valid && !mem_ready && !sel_ram && !sel_cdr && mem_wstrb != 4'b0000 && mem_addr[7:5] == 3'b011 && !CPU_RESET;
	assign EXT_WD = mem_wdata;
`endif

	// RR as an MLAB: written on the same edge as the registers were (the firmware's I/O write), read by the host
	// at {AA[5], AA[2]} (0x18 / 1C / 20 / 24 -> 0-3), before that edge's write like the registers
	wire RR_WE = !RESET && mem_valid && !mem_ready && !sel_ram && !sel_cdr && mem_wstrb != 4'b0000 && mem_addr[7:4] == 4'h2;
	CDB_HLE_REG_RAM rr_ram (.CLK(CLK), .WADDR(mem_addr[3:2]), .WDATA(mem_wdata[15:0]), .WE(RR_WE), .RADDR({AA[5], AA[2]}), .Q(RR_Q));

	// ------------------------------------------------------------------------------------------ CD RAM arbiter
	// priority: sector engine (the source must not wait long), CD-DA player, data transfer, CPU window
	always @(posedge CLK) begin
		bit [1:0] st, cur;
		SE_ACK <= 0; AU_ACK <= 0; DT_ACK <= 0; CW_RACK <= 0;
		if (RESET) begin
			st <= 2'd0; CD_RAM_RD <= 0; CD_RAM_WE <= '0; CD_RAM_CS <= 0;
		end else case (st)
			2'd0: begin                                // idle: the strobes stay low for a clock between accesses
				if (SE_REQ && !SE_ACK) begin
					cur <= 2'd0; CD_RAM_A <= SE_A; CD_RAM_D <= SW_DATA; CD_RAM_WE <= 2'b11; CD_RAM_CS <= 1; st <= 2'd1;
				end else if (AU_REQ && !AU_ACK) begin
					cur <= 2'd1; CD_RAM_A <= AU_A; CD_RAM_RD <= 1; CD_RAM_CS <= 1; st <= 2'd1;
				end else if (DT_REQ && !DT_ACK) begin
					cur <= 2'd2; CD_RAM_A <= DT_A; CD_RAM_D <= DT_D; CD_RAM_WE <= DT_WE; CD_RAM_RD <= DT_WE == 2'b00;
					CD_RAM_CS <= 1; st <= 2'd1;
				end else if (CW_RQ && !CW_RACK) begin
					cur <= 2'd3; CD_RAM_A <= mem_addr[19:2]; CD_RAM_D <= mem_wdata[15:0]; CD_RAM_WE <= mem_wstrb[1:0];
					CD_RAM_RD <= mem_wstrb[1:0] == 2'b00;
					CD_RAM_CS <= 1; st <= 2'd1;
				end
			end
			2'd1: st <= 2'd2;                          // the memory's busy flag shows up at the next edge
			2'd2: if (CD_RAM_RDY) begin
				AR_Q <= CD_RAM_Q;
				case (cur) 2'd0: SE_ACK <= 1; 2'd1: AU_ACK <= 1; 2'd2: DT_ACK <= 1; default: CW_RACK <= 1; endcase
				CD_RAM_RD <= 0; CD_RAM_WE <= '0; CD_RAM_CS <= 0; st <= 2'd0;
			end
			default: st <= 2'd0;
		endcase
	end

	// CPU window: CPU word k (byte address 4k) is CD RAM word k, big-endian: wstrb[1] writes the high byte. The
	// arbiter takes the address, data and byte enables straight from the CPU bus (the CPU holds them while it waits
	// for mem_ready), and the read data is AR_Q (the arbiter's next completion is 3 clocks after this one at the
	// earliest, so AR_Q still holds it when mem_ready is raised).
	always @(posedge CLK) begin
		CW_ACK <= 0;
		if (RESET) CW_RQ <= 0;
		else if (CW_REQ && !CW_RQ && !CW_ACK) begin
			CW_RQ <= 1;
		end else if (CW_RQ && CW_RACK) begin
			CW_RQ <= 0; CW_ACK <= 1;
		end
	end

	// ------------------------------------------------------------------------------------------ sector engine
	// page * 1176 + offset in a DSP block (the page_word adds in logic cost about 30 LUTs each)
	(* multstyle = "dsp" *) wire [18:1] SE_PW = SEC_PAGE * 11'd1176 + {7'b0, SW_WIDX};
	bit        SW_FULL;
	bit [15:0] SW_DATA;
	bit [10:0] SW_WIDX;                                 // words written (or skipped) of this sector
	assign SEC_WAIT = SW_FULL;
	always @(posedge CLK) begin
		SEC_REQ <= 0;
		if (RESET) begin
			SEC_BUSY <= 0; SW_FULL <= 0; SW_WIDX <= '0; SE_REQ <= 0;
		end else if (SEC_START) begin
			SEC_BUSY <= 1; SEC_REQ <= 1; SW_WIDX <= '0; SW_FULL <= 0;
		end else if (SEC_BUSY) begin
			if (SEC_WR && !SW_FULL) begin
				SW_DATA <= {SEC_DATA[7:0], SEC_DATA[15:8]};
				SW_FULL <= 1;
			end
			if (SW_FULL && !SE_REQ && SEC_NOSYNC && SW_WIDX < 11'd6) begin
				SW_FULL <= 0; SW_WIDX <= SW_WIDX + 11'd1;
			end else if (SW_FULL && !SE_REQ) begin
				SE_A <= SE_PW; SE_REQ <= 1;
			end else if (SE_REQ && SE_ACK) begin
				SE_REQ <= 0; SW_FULL <= 0; SW_WIDX <= SW_WIDX + 11'd1;
				if (SW_WIDX == 11'd1175) SEC_BUSY <= 0;
			end
		end
	end

	// ------------------------------------------------------------------------------------------ data transfer
	// The words of a sector buffer sent for the sector length setting (Mednafen's DT_SetIBOffsCount)
	function automatic [21:0] dt_span(input wr, input [1:0] len, input mode1, input form2);   // {offset, count}
		if (wr) case (len)
			2'd0: dt_span = {11'd12, 11'd1024};
			2'd1: dt_span = {11'd8,  11'd1168};
			2'd2: dt_span = {11'd6,  11'd1170};
			default: dt_span = {11'd0, 11'd1176};
		endcase
		else case (len)
			2'd0: dt_span = mode1 ? {11'd8, 11'd1024} : form2 ? {11'd12, 11'd1162} : {11'd12, 11'd1024};
			2'd1: dt_span = {11'd8,  11'd1168};
			2'd2: dt_span = {11'd6,  11'd1170};
			default: dt_span = {11'd0, 11'd1176};
		endcase
	endfunction

	bit [9:0] DTL[256];                                  // transfer list: {form2, mode1, page}
	bit [9:0] DTL_Q;
	always @(posedge CLK) begin
		if (DTL_WE) DTL[DTL_WADDR] <= mem_wdata[9:0];         // the CPU still holds the I/O write's data
		DTL_Q <= DTL[DT_IDX];
	end

	bit [18:1] DT_A;
	wire [21:0] DT_SP = dt_span(DT_WR, DT_WR ? PUT_SECLEN : GET_SECLEN, DTL_Q[8], DTL_Q[9]);
	(* multstyle = "dsp" *) wire [18:1] DT_PW = DTL_Q[7:0] * 11'd1176 + {7'b0, DT_SP[21:11]};
	bit [10:0] DT_LEFT;
	bit [15:0] DT_HW;                                    // raw: CPU RAM halfword index
	bit  [7:0] DT_IDX;
	bit  [2:0] DT_ST;
	always @(posedge CLK) begin
		ENG_PUSH <= 0; ENG_POP <= 0;
		DT_RREQ <= 0;
		if (RESET || DT_STOP) begin
			DT_ACT <= 0; DT_ST <= 3'd0; DT_REQ <= 0; DT_END <= 0; DT_LIMIT <= 0;
			if (RESET) DT_TOTAL <= '0;
		end else if (DT_START) begin
			DT_ACT <= 1; DT_WR <= DT_START_WR; DT_TOTAL <= '0; DT_IDX <= '0;
			DTL_N <= DTL_WA; DT_END <= 0; DT_LIMIT <= 0;
			DT_HW <= DT_RAW_ADDR >> 1; DT_LEFT <= DT_RAW_CNT[10:0];
			DT_ST <= DT_START_RAW ? 3'd3 : 3'd1;
		end else if (DT_ACT) case (DT_ST)
			3'd1: begin                                // next list entry (DTL_Q has it at the next clock)
				if (DT_IDX == DTL_N) begin DT_END <= 1; DT_LIMIT <= 1; DT_ST <= 3'd0; end
				else DT_ST <= 3'd2;
			end
			3'd2: begin
				bit [21:0] sp;
				sp = dt_span(DT_WR, DT_WR ? PUT_SECLEN : GET_SECLEN, DTL_Q[8], DTL_Q[9]);
				DT_A <= DT_PW;
				DT_LEFT <= sp[10:0];
				DT_IDX <= DT_IDX + 8'd1;
				DT_ST <= DT_WR ? 3'd5 : 3'd4;
			end
			3'd3: begin                                // raw read (CPU RAM): keep 5 words in the FIFO
				if (!DT_LEFT) begin DT_END <= 1; DT_ST <= 3'd0; end
				else if (FIFO_N + {2'b00, ENG_PUSH} < 3'd5) begin ram_ab <= DT_HW[RAM_AW:1]; DT_RREQ <= 1; DT_ST <= 3'd6; end
			end
			3'd6: DT_ST <= 3'd7;                       // the RAM read happens in the DT_RREQ clock
			3'd7: begin
				ENG_WDATA <= DT_HW[0] ? {ram_q[23:16], ram_q[31:24]} : {ram_q[7:0], ram_q[15:8]};
				ENG_PUSH <= 1; DT_TOTAL <= DT_TOTAL + 18'd1;
				DT_HW <= DT_HW + 16'd1; DT_LEFT <= DT_LEFT - 11'd1; DT_ST <= 3'd3;
			end
			3'd4: begin                                // list read: keep 5 words in the FIFO
				if (!DT_LEFT) DT_ST <= 3'd1;
				else if (!DT_REQ && FIFO_N + {2'b00, ENG_PUSH} < 3'd5) begin
					DT_WE <= 2'b00; DT_REQ <= 1;
				end else if (DT_REQ && DT_ACK) begin
					DT_REQ <= 0; ENG_WDATA <= AR_Q; ENG_PUSH <= 1; DT_TOTAL <= DT_TOTAL + 18'd1;
					DT_A <= DT_A + 18'd1; DT_LEFT <= DT_LEFT - 11'd1;
				end
			end
			3'd5: begin                                // list write: FIFO words to the page
				if (!DT_LEFT) begin if (!DT_REQ) DT_ST <= 3'd1; end
				else if (!DT_REQ && !FIFO_EMPTY && !ENG_POP) begin
					DT_D <= FIFO_Q; DT_WE <= 2'b11; DT_REQ <= 1; ENG_POP <= 1;
					DT_TOTAL <= DT_TOTAL + 18'd1;
				end else if (DT_REQ && DT_ACK) begin
					DT_REQ <= 0; DT_A <= DT_A + 18'd1; DT_LEFT <= DT_LEFT - 11'd1;
				end
			end
			default:;
		endcase
	end

	// ------------------------------------------------------------------------------------------ CD-DA player
	// A queue of 4 entries {zero, shift[1:0], samples[9:0], page[7:0]}; each ACE sends the next sample (0 while the
	// queue is empty). The next sample is read from CD RAM ahead of its ACE.
	bit [20:0] AQ[4];
	bit  [1:0] AQ_RP, AQ_WP;
	bit  [2:0] AQ_N;
	bit  [9:0] AQ_POS;
	bit        AS_VALID;
	bit [15:0] AS_L, AS_R;
	wire [20:0] AQ_E = AQ[AQ_RP];                       // the queue head (the only read of AQ)
	(* multstyle = "dsp" *) wire [18:1] AU_PW = AQ_E[7:0] * 11'd1176 + {7'b0, AQ_POS, 1'b0};   // even
	bit  [1:0] AS_PH;
	always @(posedge CLK) begin
		bit [20:0] e;
		bit        push, last;
		e = AQ_E;
		push = AUD_PUSH && AQ_N != 3'd4;
		last = ACE && AS_VALID && AQ_POS == e[17:8] - 10'd1;
		if (RESET || AUD_FLUSH) begin
			AQ_RP <= '0; AQ_WP <= '0; AQ_N <= '0; AQ_POS <= '0; AUD_COUNT <= '0; AS_VALID <= 0; AS_PH <= '0;
			AU_REQ <= 0;
			if (RESET) begin AUD_DONE <= '0; CD_SL <= '0; CD_SR <= '0; end
		end else begin
			if (push) begin AQ[AQ_WP] <= mem_wdata[20:0]; AQ_WP <= AQ_WP + 2'd1; end
			if (!AS_VALID && AQ_N != 3'd0) begin
				if (e[20]) begin AS_L <= '0; AS_R <= '0; AS_VALID <= 1; end
				else case (AS_PH)
					2'd0: begin AU_A <= AU_PW; AU_REQ <= 1; AS_PH <= 2'd1; end
					2'd1: if (AU_ACK) begin AU_REQ <= 0; AS_L <= $signed({AR_Q[7:0], AR_Q[15:8]}) >>> e[19:18]; AS_PH <= 2'd2; end
					2'd2: begin AU_A <= {AU_PW[18:2], 1'b1}; AU_REQ <= 1; AS_PH <= 2'd3; end
					2'd3: if (AU_ACK) begin AU_REQ <= 0; AS_R <= $signed({AR_Q[7:0], AR_Q[15:8]}) >>> e[19:18]; AS_PH <= 2'd0; AS_VALID <= 1; end
				endcase
			end
			if (ACE) begin
				if (AS_VALID) begin
					CD_SL <= AS_L; CD_SR <= AS_R; AS_VALID <= 0;
					if (last) begin AQ_POS <= '0; AQ_RP <= AQ_RP + 2'd1; AUD_DONE <= AUD_DONE + 8'd1; end
					else AQ_POS <= AQ_POS + 10'd1;
				end else if (AQ_N == 3'd0) begin
					CD_SL <= '0; CD_SR <= '0;
				end
			end
			AQ_N <= AQ_N + {2'b00, push} - {2'b00, last};
			AUD_COUNT <= AUD_COUNT + (push ? mem_wdata[17:8] : 10'd0) - {9'b0, ACE && AS_VALID};
		end
	end
endmodule

// The CPU RAM: simple dual port with byte enables and the firmware image as its initial contents (the Quartus
// template for an inferred M10K RAM with byte enables).
module CDB_HLE_RAM #(parameter WORDS = 10240, parameter AW = 14, parameter INIT = "") (
	input              CLK,
	input     [AW-1:0] WADDR,
	input      [ 3: 0] BE,
	input      [31: 0] WDATA,
	input              WE,
	input     [AW-1:0] RADDR,
	output reg [31: 0] Q
);
	logic [3:0][7:0] ram[0:WORDS-1];
	initial $readmemh(INIT, ram);
	always_ff @(posedge CLK) begin
		if (WE) begin
			if (BE[0]) ram[WADDR][0] <= WDATA[ 7: 0];
			if (BE[1]) ram[WADDR][1] <= WDATA[15: 8];
			if (BE[2]) ram[WADDR][2] <= WDATA[23:16];
			if (BE[3]) ram[WADDR][3] <= WDATA[31:24];
		end
		Q <= ram[RADDR];
	end
endmodule

`ifdef CD_EXTIO
// (CD_EXTIO, the Pocket) the CPU RAM in two banks: BANK0 words (INIT), then WORDS - BANK0 more (INIT1) in a second RAM,
// whose size need not be a multiple of Quartus's 4096-word groups (the Pocket: 20480 + 2048 words = 80 + 8 M10K, where
// one RAM of 22528 words would take 96). Bank 1's address is the word address - BANK0 (the low bits only when BANK0 is a
// multiple of bank 1's power-of-two size, as here: no subtractor). The read data is one clock late as in CDB_HLE_RAM;
// the bank of the read is registered with it.
module CDB_HLE_RAM2 #(parameter WORDS = 10240, parameter AW = 14, parameter INIT = "", parameter BANK0 = WORDS,
                      parameter INIT1 = "") (
	input              CLK,
	input     [AW-1:0] WADDR,
	input      [ 3: 0] BE,
	input      [31: 0] WDATA,
	input              WE,
	input     [AW-1:0] RADDR,
	output     [31: 0] Q
);
	generate if (BANK0 >= WORDS) begin : one
		CDB_HLE_RAM #(.WORDS(WORDS), .AW(AW), .INIT(INIT)) ram (.CLK(CLK), .WADDR(WADDR), .BE(BE), .WDATA(WDATA), .WE(WE),
			.RADDR(RADDR), .Q(Q));
	end else begin : two
		localparam W1 = WORDS - BANK0, A1 = $clog2(W1);
		logic [3:0][7:0] ram0[0:BANK0-1];
		logic [3:0][7:0] ram1[0:W1-1];
		initial begin $readmemh(INIT, ram0); $readmemh(INIT1, ram1); end
		wire w1 = WADDR >= AW'(BANK0), r1 = RADDR >= AW'(BANK0);
		wire [AW-1:0] wa1 = WADDR - AW'(BANK0), ra1 = RADDR - AW'(BANK0);
		logic [31:0] q0, q1;
		logic        sel;
		always_ff @(posedge CLK) begin
			if (WE && !w1) begin
				if (BE[0]) ram0[WADDR][0] <= WDATA[ 7: 0];
				if (BE[1]) ram0[WADDR][1] <= WDATA[15: 8];
				if (BE[2]) ram0[WADDR][2] <= WDATA[23:16];
				if (BE[3]) ram0[WADDR][3] <= WDATA[31:24];
			end
			q0 <= ram0[RADDR];
		end
		always_ff @(posedge CLK) begin
			if (WE && w1) begin
				if (BE[0]) ram1[wa1[A1-1:0]][0] <= WDATA[ 7: 0];
				if (BE[1]) ram1[wa1[A1-1:0]][1] <= WDATA[15: 8];
				if (BE[2]) ram1[wa1[A1-1:0]][2] <= WDATA[23:16];
				if (BE[3]) ram1[wa1[A1-1:0]][3] <= WDATA[31:24];
			end
			q1 <= ram1[ra1[A1-1:0]];
		end
		always_ff @(posedge CLK) sel <= r1;
		assign Q = sel ? q1 : q0;
	end endgenerate
endmodule

`endif
// The data port FIFO: an MLAB with an asynchronous read (Quartus does not infer one without the attribute; the
// 96 registers and their write decode and read mux cost about 100 ALMs).
module CDB_HLE_FIFO_RAM (
	input CLK, input [2:0] WADDR, input [15:0] WDATA, input WE, input [2:0] RADDR, output [15:0] Q);
	(* ramstyle = "MLAB, no_rw_check" *) logic [15:0] ram[0:7];
	always_ff @(posedge CLK) if (WE) ram[WADDR] <= WDATA;
	assign Q = ram[RADDR];
endmodule

// A 4 x 16 host interface register set as an MLAB with an asynchronous read.
module CDB_HLE_REG_RAM (
	input CLK, input [1:0] WADDR, input [15:0] WDATA, input WE, input [1:0] RADDR, output [15:0] Q);
	(* ramstyle = "MLAB, no_rw_check" *) logic [15:0] ram[0:3];
	always_ff @(posedge CLK) if (WE) ram[WADDR] <= WDATA;
	assign Q = ram[RADDR];
endmodule
`ifdef CDB_FEMTORV

// CDB_FEMTORV: the FemtoRV32 quark (rtl/Saturn/CD/femtorv, BSD-3-Clause) behind the PicoRV32 memory interface that
// CDB_HLE uses. The quark strobes a read (mem_rstrb) or a write (mem_wmask) for one clock with its address and write
// data, then waits while mem_rbusy / mem_wbusy is set, and takes the read data (an instruction, or a load into the
// register file) in the clock busy drops. Here a strobe starts a PicoRV32-style access: mem_valid with the word
// address, byte strobes and write data latched, held until mem_ready, which ends the quark's wait in that clock. So,
// as with the PicoRV32 (and as CDB_HLE relies on):
//   - the address, byte strobes and write data stay put during the access, the write data until the next write;
//   - mem_valid is low for at least a clock between accesses (the quark strobes in the clock after mem_ready at the
//     earliest) and drops at once in reset;
//   - the read data is taken in the mem_ready clock only (as with LATCHED_MEM_RDATA).
// mem_instr (not used by CDB_HLE) marks instruction fetches: the quark fetches, then makes the fetched instruction's
// data access if it is a load or a store, then fetches the next one.
module CDB_HLE_FEMTORV (
	input             clk,
	input             resetn,
	output            mem_valid,
	output            mem_instr,
	input             mem_ready,
	output     [31:0] mem_addr,
	output     [31:0] mem_wdata,
	output     [ 3:0] mem_wstrb,
	input      [31:0] mem_rdata
);
	wire [31:0] q_addr, q_wdata;
	wire [ 3:0] q_wmask;
	wire        q_rstrb;
	bit         pend, fetch, data_next;
	bit  [31:0] addr, wdata;
	bit  [ 3:0] wstrb;

	FemtoRV32 #(.RESET_ADDR(32'h0000_0000), .ADDR_WIDTH(32)) femto (
		.clk(clk), .reset(resetn), .mem_addr(q_addr), .mem_wdata(q_wdata), .mem_wmask(q_wmask), .mem_rdata(mem_rdata),
		.mem_rstrb(q_rstrb), .mem_rbusy(pend & ~mem_ready), .mem_wbusy(pend & ~mem_ready));

	always @(posedge clk) begin
		if (!resetn) begin
			pend <= 0; data_next <= 0;
		end else if (q_rstrb || q_wmask != 4'b0000) begin
			pend <= 1; fetch <= ~data_next; addr <= q_addr; wstrb <= q_wmask;
			if (q_wmask != 4'b0000) wdata <= q_wdata;
		end else if (pend && mem_ready) begin
			pend <= 0;
			data_next <= fetch && (mem_rdata[6:2] == 5'b00000 || mem_rdata[6:2] == 5'b01000);   // a load or a store
		end
	end
	assign mem_valid = pend;
	assign mem_instr = pend & fetch;
	assign mem_addr  = {addr[31:2], 2'b00};
	assign mem_wdata = wdata;
	assign mem_wstrb = wstrb;
endmodule   // CDB_HLE_FEMTORV
`endif

`ifdef CUT_MSH_CACHE_TW
module SH7604_CACHE #(parameter bit CUT_AARD=0, bit CUT_TW=0) (	//CUT_AARD: U3 CUT_SSH_CACHE_AARD (the slave), see CACHE_ADDR_AREA_DATA; CUT_TW: U4 (the master), see CCR
`else
`ifdef CUT_SSH_CACHE_AARD
module SH7604_CACHE #(parameter bit CUT_AARD=0) (	//U3 CUT_SSH_CACHE_AARD (the slave only): see CACHE_ADDR_AREA_DATA
`else
module SH7604_CACHE (
`endif
`endif
	input             CLK,
	input             RST_N,
	input             CE_R,
	input             CE_F,
	input             EN,
	
	input             RES_N,
	
	input      [31:0] CBUS_A,
	input      [31:0] CBUS_A_NEXT,	//the value CBUS_A takes at the next clock edge (SH_core BUS_A_NEXT)
	input      [31:0] CBUS_DI,
	output     [31:0] CBUS_DO,
	input             CBUS_WR,
	input       [3:0] CBUS_BA,
	input             CBUS_REQ,
	input             CBUS_ID,
	input             CBUS_TAS,
	output            CBUS_BUSY,
	
	output     [31:0] IBUS_A,
	input      [31:0] IBUS_DI,
	output     [31:0] IBUS_DO,
	output      [3:0] IBUS_BA,
	output            IBUS_WE,
	output            IBUS_REQ,
	output            IBUS_PREREQ,
	output            IBUS_BURST,
	output            IBUS_LOCK,
	input             IBUS_WAIT
);

	import SH7604_PKG::*;
	
	// synopsys translate_off
	`define SIM
	// synopsys translate_on

	CCR_t CCR;
	
	bit  [31:0] IBADDR;
	bit  [31:0] IBDATA;
	bit   [3:0] IBBA;
	bit         IBWE;
	bit         IBREQ;
	bit         IBBURST;
	bit         IBLOCK;
	
	wire CCR_SEL = (CBUS_A == 32'hFFFFFE92);
	
	wire CACHE_AREA      = (CBUS_A[31:29] == 3'b000);
	wire NOCACHE_AREA    = (CBUS_A[31:29] == 3'b001);
	wire PURGE_AREA      = (CBUS_A[31:29] == 3'b010);
	wire CACHE_ADDR_AREA = (CBUS_A[31:29] == 3'b011);
	wire CACHE_DATA_AREA = (CBUS_A[31:29] == 3'b110 || CBUS_A[31:29] == 3'b100);
	wire IO_AREA         = (CBUS_A[31:29] == 3'b111) && !CCR_SEL;
	
	
	bit   [3:0] WAY_HIT;
	bit   [3:0] WAY_TAG;
	
	bit  [31:0] CACHE_DATA;
	bit  [28:2] CACHE_WR_ADDR;
	bit   [3:0] CACHE_WR_BA;
	bit   [3:0] CACHE_WR_WAY;
	bit         CACHE_UPDATE;
	bit         CACHE_WRITE;
	bit         CACHE_READ;
	bit         CACHE_LINE_PURGE;
	bit         CACHE_DATA_WRITE;
	bit         CACHE_ADDR_WRITE;
	bit         CACHE_PURGE;
	bit   [5:0] LRU_DATA;
	
	function bit [3:0] WayFromLRU(input bit [5:0] lru, input bit two_way);
		bit [3:0] res;
	
		if (two_way) begin
			res = lru[0] ? 4'b0100 : 4'b1000;
		end else begin
			casez (lru)
				6'b111???: res = 4'b0001;
				6'b0??11?: res = 4'b0010;
				6'b?0?0?1: res = 4'b0100;
				6'b??0?00: res = 4'b1000;
				default:   res = 4'b0000;
			endcase
		end
		return res;
	endfunction
	
	function bit [5:0] LRUSelect(input bit [3:0] way, input bit [5:0] lru);
		bit [5:0] res;

		res = way[3] ? {lru[5],lru[4],1'b1,  lru[2],1'b1,  1'b1  } :
		      way[2] ? {lru[5],1'b1  ,lru[3],1'b1  ,lru[1],1'b0  } :
		      way[1] ? {1'b1  ,lru[4],lru[3],1'b0  ,1'b0  ,lru[0]} :
				way[0] ? {1'b0  ,1'b0  ,1'b0  ,lru[2],lru[1],lru[0]} :
				         {lru[5],lru[4],lru[3],lru[2],lru[1],lru[0]};
		return res;
	endfunction
	
	function bit [1:0] WayToAddr(input bit [3:0] way);
		bit [1:0] res;

		res = way[0] ? 2'b00 :
		      way[1] ? 2'b01 :
		      way[2] ? 2'b10 :
		      way[3] ? 2'b11 : 
				         2'b00;
		return res;
	endfunction
	
	function bit [3:0] AddrToWay(input bit [1:0] a);
		bit [3:0] res;
	
		case (a) 
			2'b00: res = 4'b0001;
			2'b01: res = 4'b0010;
			2'b10: res = 4'b0100;
			2'b11: res = 4'b1000;
		endcase
		return res;
	endfunction
	

	wire  [1:0] CRAM_WRWAY = CACHE_DATA_WRITE ? CACHE_WR_ADDR[11:10] : WayToAddr(CACHE_WR_WAY);
	wire  [9:0] CRAM_WRADDR = {CRAM_WRWAY,CACHE_WR_ADDR[9:2]};
	wire [31:0] CRAM_D = CACHE_UPDATE ? IBUS_DI : CBUS_DI;
	wire  [3:0] CRAM_WE = {4{CACHE_UPDATE}} | (CACHE_WR_BA & {4{CACHE_WRITE | CACHE_DATA_WRITE}});
	
	wire  [1:0] CRAM_RDWAY = CACHE_DATA_AREA ? CBUS_A[11:10] : CACHE_ADDR_AREA ? CCR.W : WayToAddr(WAY_HIT);
	wire  [9:0] CRAM_RDADDR = {CRAM_RDWAY,CBUS_A[9:2]};
	
	bit  [31:0] CRAM_Q;
	CACHE_RAM ram0(.wrclock(CLK), .wraddress(CRAM_WRADDR), .data(CRAM_D[ 7: 0]), .wren(CRAM_WE[0] & EN & CE_R), .rdclock(CLK), .rdaddress(CRAM_RDADDR), .q(CRAM_Q[ 7: 0]));
	CACHE_RAM ram1(.wrclock(CLK), .wraddress(CRAM_WRADDR), .data(CRAM_D[15: 8]), .wren(CRAM_WE[1] & EN & CE_R), .rdclock(CLK), .rdaddress(CRAM_RDADDR), .q(CRAM_Q[15: 8]));
	CACHE_RAM ram2(.wrclock(CLK), .wraddress(CRAM_WRADDR), .data(CRAM_D[23:16]), .wren(CRAM_WE[2] & EN & CE_R), .rdclock(CLK), .rdaddress(CRAM_RDADDR), .q(CRAM_Q[23:16]));
	CACHE_RAM ram3(.wrclock(CLK), .wraddress(CRAM_WRADDR), .data(CRAM_D[31:24]), .wren(CRAM_WE[3] & EN & CE_R), .rdclock(CLK), .rdaddress(CRAM_RDADDR), .q(CRAM_Q[31:24]));
	
	
	// the tags are only written on CACHE_UPDATE or CACHE_ADDR_WRITE (CTAG_WE), both with CACHE_WR_ADDR[28:10]
	wire [18:0] CTAG_D = CACHE_WR_ADDR[28:10];
	wire  [3:0] CTAG_WE = ({4{CACHE_UPDATE}} & CACHE_WR_WAY) | ({4{CACHE_ADDR_WRITE}} & AddrToWay(CCR.W));
	// Tags and the lookup copy of the valid/LRU words (vlru_b below) in M10K blocks. (Step G had MLABs: a 64-deep MLAB
	// is two 32-deep ones plus an output mux, 20 ALMs and the mux for each of the five.) An M10K registers its read
	// address, so it is given CBUS_A_NEXT, the core's address one clock early: during every clock its output is the
	// word at CBUS_A, as the MLABs' asynchronous read gave. Writes land on a clock edge, and an M10K read registered at
	// that same edge returns the old word (OLD_DATA), so in the clock after a write to the line being looked up the
	// written word is used instead: the tag written is CACHE_WR_ADDR[28:10], which (like the line, CACHE_WR_ADDR[9:4])
	// only changes on EN & CE_F edges, never on the EN & CE_R edges that write, so it is still the written value.
	bit  [18:0] CTAG_M[4];
	CACHE_TAG_M10K tag0(.clock(CLK), .wraddress(CACHE_WR_ADDR[9:4]), .data(CTAG_D), .wren(CTAG_WE[0] & EN & CE_R), .rdaddress(CBUS_A_NEXT[9:4]), .q(CTAG_M[0]));
	CACHE_TAG_M10K tag1(.clock(CLK), .wraddress(CACHE_WR_ADDR[9:4]), .data(CTAG_D), .wren(CTAG_WE[1] & EN & CE_R), .rdaddress(CBUS_A_NEXT[9:4]), .q(CTAG_M[1]));
	CACHE_TAG_M10K tag2(.clock(CLK), .wraddress(CACHE_WR_ADDR[9:4]), .data(CTAG_D), .wren(CTAG_WE[2] & EN & CE_R), .rdaddress(CBUS_A_NEXT[9:4]), .q(CTAG_M[2]));
	CACHE_TAG_M10K tag3(.clock(CLK), .wraddress(CACHE_WR_ADDR[9:4]), .data(CTAG_D), .wren(CTAG_WE[3] & EN & CE_R), .rdaddress(CBUS_A_NEXT[9:4]), .q(CTAG_M[3]));
	bit   [3:0] CTAG_WE_Q;				//tag ways written on the last clock edge
	always @(posedge CLK) CTAG_WE_Q <= CTAG_WE & {4{EN & CE_R}};
	wire        WR_LINE_LOOKUP = CACHE_WR_ADDR[9:4] == CBUS_A[9:4];	//the line written is the line looked up
	wire  [3:0] CTAG_FWD = CTAG_WE_Q & {4{WR_LINE_LOOKUP}};
	bit  [18:0] CTAG_Q[4];
	always_comb for (int i = 0; i < 4; i++) CTAG_Q[i] = CTAG_FWD[i] ? CTAG_D : CTAG_M[i];
	
	// Valid bits and LRU: one MLAB word per line, {GEN[6:0], V3, V2, V1, V0, LRU[5:0]}, in two copies: vlru_a is read at
	// the line being written (read-modify-write), vlru_b at the line being looked up. A purge (CCR.CP) cannot clear
	// MLABs, so each word carries the purge generation it was last written in: a line whose stored generation is not the
	// current one (PURGE_GEN) is purged, i.e. reads as invalid with LRU 0, until a write to the line stores it with the
	// current generation (the write then stores the line with every other way invalid and LRU 0 as its starting point).
	// This replaces step E's 64 PURGED flip-flops with the same state, line by line: PURGED[i] == (GEN[i] != PURGE_GEN).
	// - What sets every PURGED bit advances PURGE_GEN by one: a purge (CCR.CP on a clock that is not EN & CE_R) and every
	//   clock with RST_N low (PURGED's reset). While RST_N is low every line also reads as purged (PURGED's asynchronous
	//   reset showed that before the first clock edge).
	// - A stored generation must never come round to PURGE_GEN again (7 bits: 128 advances). A scrubber walks the lines,
	//   one per clock that has no normal write (every clock that is not RST_N & EN & CE_R), and rewrites a purged line
	//   with generation PURGE_GEN - 1 (still purged; its other bits are then don't-care). PURGE_GEN only advances on such
	//   clocks too, at most once per clock, so between two visits of a line (64 such clocks) it advances at most 64
	//   times: a stored generation is never more than 65 behind, for any CE / EN pattern, purge rate or reset length.
	//   The scrubber shares vlru_a's port: on the clocks it runs, vlru_a's read data is not used otherwise.
	// - Power-up: PURGE_GEN 0 and MLAB words of 0 (CACHE_VLRU is initialized) give the state PURGED's power-up value 0 gave.
	wire        CVALID_D = (CACHE_UPDATE ? 1'b1 : CACHE_ADDR_WRITE ? CACHE_WR_ADDR[2] : 1'b0) & ~CACHE_LINE_PURGE;
	wire  [3:0] CVALID_WE = ({4{CACHE_UPDATE | CACHE_LINE_PURGE}} & CACHE_WR_WAY) | ({4{CACHE_ADDR_WRITE}} & AddrToWay(CCR.W));

	bit   [6:0] PURGE_GEN = 7'd0;
	bit   [6:0] PURGE_GEN_M1 = 7'd127;	//PURGE_GEN - 1
	bit   [5:0] SCRUB = 6'd0;			//scrubber line
	wire        VLRU_NORMAL = RST_N & EN & CE_R;	//clocks that can have a normal write; the scrubber runs on all others
	wire        PURGE = ~RST_N | (~(EN & CE_R) & CCR.CP);
	wire  [5:0] LRU_WRADDR = VLRU_NORMAL ? CACHE_WR_ADDR[9:4] : SCRUB;
	wire  [5:0] VLRU_A_RA;			//(A3) vlru_a's read address, one clock ahead (below, after the state machine's registers)
	bit  [16:0] VLRU_A_Q,VLRU_B_Q;
	wire        PURGED_A = ~RST_N | VLRU_A_Q[16:10] != PURGE_GEN;
	wire        PURGED_B = ~RST_N | VLRU_B_Q[16:10] != PURGE_GEN;
	wire  [3:0] VALID_A = VLRU_A_Q[9:6] & {4{~PURGED_A}};
	wire  [5:0] LRU_A_Q = VLRU_A_Q[5:0] & {6{~PURGED_A}};
	wire  [5:0] LRU_D = CACHE_ADDR_WRITE ? CBUS_DI[9:4] : LRUSelect(CACHE_WR_WAY, LRU_A_Q);
	wire        LRU_WE = CACHE_UPDATE | CACHE_WRITE | CACHE_READ | CACHE_ADDR_WRITE;
	wire  [3:0] VALID_D = (CVALID_WE & {4{CVALID_D}}) | (~CVALID_WE & VALID_A);
	wire [16:0] VLRU_D = {VLRU_NORMAL ? PURGE_GEN : PURGE_GEN_M1, VALID_D, LRU_WE ? LRU_D : LRU_A_Q};
	bit         VLRU_NWE_Q;			//normal valid/LRU write on the last clock edge, at CACHE_WR_ADDR[9:4]
	//(A3) the scrubber does not rewrite the line a normal write wrote on the last edge (vlru_a's M10K read of that edge
	//returned the word before the write; the written word is current, so the MLAB's scrubber did not write it either)
	wire        VLRU_SKIP = VLRU_NWE_Q & RST_N & (CACHE_WR_ADDR[9:4] == SCRUB);
	wire        VLRU_WE = VLRU_NORMAL ? |CVALID_WE | LRU_WE : PURGED_A & ~VLRU_SKIP;

	//(A3) vlru_a in M10K, read one clock ahead (VLRU_A_RA; see work/a3/tools/mk_cache_vlru.py for why it is exact)
	CACHE_VLRU_M10K vlru_a(.clock(CLK), .wraddress(LRU_WRADDR), .data(VLRU_D), .wren(VLRU_WE), .rdaddress(VLRU_A_RA), .q(VLRU_A_Q));
	// vlru_b in M10K (see the tags above): forwarded after a normal write to the line looked up; a scrubber write needs
	// no forwarding, since it replaces a purged word by another purged one (the old word's generation is 1-65 behind
	// PURGE_GEN before the edge, so it is not PURGE_GEN after it either, whether or not a purge comes with that edge).
	bit  [16:0] VLRU_BM_Q;
	CACHE_VLRU_M10K vlru_b(.clock(CLK), .wraddress(LRU_WRADDR), .data(VLRU_D), .wren(VLRU_WE), .rdaddress(CBUS_A_NEXT[9:4]), .q(VLRU_BM_Q));
	bit  [16:0] VLRU_D_Q;			//its data
	always @(posedge CLK) begin
		VLRU_NWE_Q <= VLRU_WE & VLRU_NORMAL;
		VLRU_D_Q <= VLRU_D;
	end
	assign VLRU_B_Q = VLRU_NWE_Q && WR_LINE_LOOKUP ? VLRU_D_Q : VLRU_BM_Q;

	always @(posedge CLK) begin
		if (!VLRU_NORMAL) SCRUB <= SCRUB + 6'd1;
		if (PURGE) begin
			PURGE_GEN <= PURGE_GEN + 7'd1;
			PURGE_GEN_M1 <= PURGE_GEN;
		end
	end

	wire  [3:0] CVALID_Q = VLRU_B_Q[9:6] & {4{~PURGED_B}};
	assign LRU_DATA = VLRU_B_Q[5:0] & {6{~PURGED_B}};

	always_comb begin
		bit [31: 0] CACHE_ADDR_AREA_DATA;

		//CTAG_Q[i] == CBUS_A[28:10], with the forwarded case sharing one comparator
		for (int i = 0; i < 4; i++) WAY_TAG[i] = CTAG_FWD[i] ? CTAG_D == CBUS_A[28:10] : CTAG_M[i] == CBUS_A[28:10];

		WAY_HIT = WAY_TAG & CVALID_Q;

`ifdef CUT_SSH_CACHE_AARD
		// U3 CUT_AARD: no address-array reads: a read of 60000000-7FFFFFFF returns the data-array word CRAM_Q (way
		// CCR.W, index A[9:2]) like a data-array read, instead of {tag, LRU, valid}; address-array writes as before. The
		// slave never read the address array in any covered frame (work/usage logs).
		if (CACHE_ADDR_AREA && !CUT_AARD) begin
`else
		if (CACHE_ADDR_AREA) begin
`endif
			case (CCR.W)
				2'b00: CACHE_ADDR_AREA_DATA = {3'b000, CTAG_Q[0], LRU_DATA, 1'b0, CVALID_Q[0], 2'b00};
				2'b01: CACHE_ADDR_AREA_DATA = {3'b000, CTAG_Q[1], LRU_DATA, 1'b0, CVALID_Q[1], 2'b00};
				2'b10: CACHE_ADDR_AREA_DATA = {3'b000, CTAG_Q[2], LRU_DATA, 1'b0, CVALID_Q[2], 2'b00};
				2'b11: CACHE_ADDR_AREA_DATA = {3'b000, CTAG_Q[3], LRU_DATA, 1'b0, CVALID_Q[3], 2'b00};
			endcase
			case (CBUS_BA)
				4'b1111: CACHE_DATA = CACHE_ADDR_AREA_DATA;
				default: CACHE_DATA = {2{CACHE_ADDR_AREA_DATA[15:0]}};
			endcase
		end
		else
			CACHE_DATA = CRAM_Q;
	end


	wire HIT = WAY_HIT[0] | WAY_HIT[1] | WAY_HIT[2] | WAY_HIT[3];
	
	bit         IBDATA_RDY;
	bit         IBUS_WRITE;
	bit         IBUS_WRITE_PEND;
	bit         IBUS_READ;
	bit         IBUS_READ_PEND;
	bit         IBUS_READARRAY;
	//(A3) vlru_a's read address for the next clock. A CE_F clock is followed by a normal clock (EN = 1), whose
	//read-modify-write line is the CACHE_WR_ADDR[9:4] the state machine loads on this CE_F edge: CBUS_A when its CPU
	//branch loads it (the same conditions as below), else IBADDR (the line-fill branch; when neither loads, the flags
	//are cleared and no valid/LRU write follows). A CE_R clock is followed by a scrub clock at SCRUB (+1 if this clock
	//scrubs as well).
	wire        VLRU_LA_RD1 = ((CACHE_AREA && (!CCR.CE || CBUS_TAS)) || NOCACHE_AREA || IO_AREA) && !IBUS_READ;
	wire        VLRU_LA_RD2 = CACHE_AREA && CCR.CE && !CBUS_TAS && !IBUS_READARRAY;
	wire        VLRU_LA_CPU = CBUS_REQ && (CBUS_WR ? ((CACHE_AREA && HIT && CCR.CE && !IBREQ) || PURGE_AREA || CACHE_DATA_AREA || CACHE_ADDR_AREA)
	                                               : (!VLRU_LA_RD1 && (VLRU_LA_RD2 ? HIT : PURGE_AREA)));
	assign VLRU_A_RA = CE_F ? (VLRU_LA_CPU ? CBUS_A[9:4] : IBADDR[9:4]) : (VLRU_NORMAL ? SCRUB : SCRUB + 6'd1);
	always @(posedge CLK or negedge RST_N) begin
		bit [ 1: 0] ARRAY_POS;
		
		if (!RST_N) begin
			IBADDR <= '0;
			IBDATA <= '0;
			IBBA <= '0;
			IBWE <= '0;
			IBREQ <= 0;
			IBBURST <= 0;
			IBLOCK <= 0;
			ARRAY_POS <= '0;
			CACHE_WR_ADDR <= '0;
			CACHE_WR_BA <= '0;
			CACHE_WR_WAY <= 0;
			CACHE_UPDATE <= 0;
			CACHE_WRITE <= 0;
			CACHE_READ <= 0;
			CACHE_LINE_PURGE <= 0;
			CACHE_DATA_WRITE <= 0;
			CACHE_ADDR_WRITE <= 0;
			
			IBDATA_RDY <= 0;
			IBUS_WRITE <= 0;
			IBUS_WRITE_PEND <= 0;
			IBUS_READ <= 0;
			IBUS_READARRAY <= 0;
			IBUS_READ_PEND <= 0;
		end
		else if (EN && CE_R) begin
			if (!RES_N) begin
				IBUS_WRITE_PEND <= 0;
			end
		end
		else if (EN && CE_F) begin
			CACHE_UPDATE <= 0;
			CACHE_WRITE <= 0;
			CACHE_READ <= 0;
			CACHE_LINE_PURGE <= 0;
			CACHE_DATA_WRITE <= 0;
			CACHE_ADDR_WRITE <= 0;
			
			IBDATA_RDY <= 0;
			if (!IBUS_WAIT) begin
				if (IBUS_WRITE) begin
					IBREQ <= 0;
					IBUS_WRITE <= 0;
				end
				else if (IBUS_READ) begin
					IBREQ <= 0;
					IBDATA_RDY <= 1;
					IBUS_READ <= 0;
				end
				else if (IBUS_READARRAY) begin
					IBADDR <= {IBADDR[31:4],IBADDR[3:2] + 2'd1,2'b00};
					if (IBADDR[3:2] == ARRAY_POS) begin
						IBREQ <= 0;
						IBDATA_RDY <= 1;
						IBUS_READARRAY <= 0;
					end
					if (IBADDR[3:2] == ARRAY_POS - 2'd1) begin
						IBLOCK <= 0;
					end
					CACHE_WR_ADDR <= IBADDR[28:2];
					CACHE_WR_BA <= 4'b1111;
					CACHE_UPDATE <= CBUS_ID ? ~CCR.ID : ~CCR.OD;
				end
			end
			
			if (CBUS_REQ) begin
				if (CBUS_WR) begin
					if ((CACHE_AREA || NOCACHE_AREA || IO_AREA)) begin
						if (!IBREQ) begin
							IBADDR <= CBUS_A;
							IBDATA <= CBUS_DI;
							IBBA <= CBUS_BA;
							IBWE <= 1;
							IBREQ <= 1;
							IBBURST <= 0;
							IBLOCK <= 0;
							IBUS_WRITE <= 1;
							IBUS_WRITE_PEND <= 0;
						end else if (!IBUS_WRITE_PEND) begin
							IBUS_WRITE_PEND <= 1;
						end
					end
					
					if (CACHE_AREA && HIT && CCR.CE && (!IBREQ)) begin
						CACHE_WR_ADDR <= CBUS_A[28:2];
						CACHE_WR_BA <= CBUS_BA;
						CACHE_WR_WAY <= WAY_HIT;
						CACHE_WRITE <= 1;
					end
					else if (PURGE_AREA) begin
						CACHE_WR_ADDR <= CBUS_A[28:2];
//						CACHE_WR_BA <= 4'b1111;
						CACHE_WR_WAY <= WAY_TAG;
						CACHE_LINE_PURGE <= 1;
					end
					else if (CACHE_DATA_AREA) begin
						CACHE_WR_ADDR <= CBUS_A[28:2];
						CACHE_WR_BA <= CBUS_BA;
						CACHE_DATA_WRITE <= 1;
					end
					else if (CACHE_ADDR_AREA) begin
						CACHE_WR_ADDR <= CBUS_A[28:2];
//						CACHE_WR_BA <= 4'b1111;
						CACHE_ADDR_WRITE <= 1;
					end
				end
				else begin
					if (((CACHE_AREA && (!CCR.CE || CBUS_TAS)) || NOCACHE_AREA || IO_AREA) && !IBUS_READ) begin
						if (!IBREQ) begin
							IBADDR <= CBUS_A;
							IBBA <= CBUS_BA;
							IBWE <= 0;
							IBREQ <= 1;
							IBBURST <= 0;
							IBLOCK <= CBUS_TAS;
							IBUS_READ <= 1;
							IBUS_READ_PEND <= 0;
						end else if (!IBUS_READ_PEND) begin
							IBUS_READ_PEND <= 1;
						end
					end
					else if (CACHE_AREA && CCR.CE && !CBUS_TAS && !IBUS_READARRAY) begin
						if (HIT) begin
							CACHE_WR_ADDR <= CBUS_A[28:2];
							CACHE_WR_WAY <= WAY_HIT;
							CACHE_READ <= 1;
						end
						else begin
							if (!IBREQ) begin
								IBADDR <= {CBUS_A[31:4],CBUS_A[3:2] + 2'd1,2'b00};
								IBBA <= 4'b1111;
								IBWE <= 0;
								IBREQ <= 1;
								IBBURST <= 1;
								IBLOCK <= 0;
								ARRAY_POS <= CBUS_A[3:2];
								CACHE_WR_WAY <= WayFromLRU(LRU_DATA, CCR.TW);
								IBUS_READARRAY <= 1;
								IBUS_READ_PEND <= 0;
							end else if (!IBUS_READ_PEND) begin
								IBUS_READ_PEND <= 1;
							end
						end
					end
					else if (PURGE_AREA) begin
						CACHE_WR_ADDR <= CBUS_A[28:2];
//						CACHE_WR_BA <= 4'b1111;
						CACHE_WR_WAY <= WAY_TAG;
						CACHE_LINE_PURGE <= 1;
					end
				end
			end
			
		end
	end
	
	
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			CCR <= '0;
			// synopsys translate_off
			CCR <= 8'h00;
			// synopsys translate_on
		end
		else if (!RES_N) begin
			CCR <= CCR_INIT;
		end
		else if (CE_R) begin
			if (CCR_SEL && CBUS_WR && CBUS_REQ) begin
`ifdef CUT_MSH_CACHE_TW
				// U4 CUT_TW (CUT_MSH_CACHE_TW, the master only; 0 = as before): TW is written as 0 (reads 0), so the cache is
				// always four-way (a line fill never takes its way from the two-way rule, WayFromLRU). The master never wrote
				// TW = 1 (BIOS boot, BIOS menus, every game; work/usage logs; NiGHTS sets it on the slave, which keeps it).
				CCR <= CBUS_DI[7:0] & CCR_WMASK & {4'hF, ~CUT_TW, 3'h7};
`else
				CCR <= CBUS_DI[7:0] & CCR_WMASK;
`endif
			end
			if (CCR.CP) CCR.CP <= 0;
		end
	end
	
	assign CBUS_DO = CCR_SEL ? {4{CCR & CCR_RMASK}} : 
	                 IBDATA_RDY ? IBUS_DI : 
						  CACHE_DATA;
	assign CBUS_BUSY = CBUS_REQ && (IBUS_READ || IBUS_READARRAY || IBUS_READ_PEND || IBUS_WRITE_PEND);
						  
	assign IBUS_A = IBADDR;
	assign IBUS_DO = IBDATA;
	assign IBUS_BA = IBBA;
	assign IBUS_WE = IBWE;
	assign IBUS_REQ = IBREQ;
	assign IBUS_PREREQ = CBUS_REQ && ((!CBUS_WR && ((CACHE_AREA && (!CCR.CE /*|| CBUS_TAS*/)) || (NOCACHE_AREA && !CBUS_TAS))) || (!CBUS_WR && CACHE_AREA && CCR.CE && !HIT)) && !IBREQ;
	assign IBUS_BURST = IBBURST; 
	assign IBUS_LOCK = IBLOCK;

endmodule

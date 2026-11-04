module SH_core
#(parameter bit VER=1)//0-SH1,1-SH2
 (
	input             CLK,
	input             RST_N,
	input             CE,
	input             EN,
	
	input             RES_N,
	input             NMI_N,
	
	output     [31:0] BUS_A,
	input      [31:0] BUS_DI,
	output     [31:0] BUS_DO,
	output            BUS_WR,
	output      [3:0] BUS_BA,
	output            BUS_REQ,
	output            BUS_ID,	//instruction=1,data=0
	output            BUS_TAS,
	input             BUS_WAIT,
	output     [31:0] BUS_A_NEXT,	//the value BUS_A takes at the next clock edge (the cache's tag RAM address, VER=1)
	
	output      [1:0] MAC_SEL,
	output      [3:0] MAC_OP,
	output            MAC_S,
	output            MAC_WE,
	
	input       [3:0] INT_LVL,
	input       [7:0] INT_VEC,
	input             INT_REQ,
	input             INT_REQ_NEXT,	//value INT_REQ will have in the next clock (decoder ROM address, VER=1)
	output      [3:0] INT_MASK,
	output            INT_ACK,
	output            INT_ACP,
	
	output            VECT_REQ,
	input             VECT_WAIT,
	
	output            SLEEP
`ifdef DEBUG
	                  ,
	output     [31:0] DBG_BUS_A,
	output			   ILI,
	
	input       [4:0] DBG_REGN,
	output     [31:0] DBG_REGQ,
	input             DBG_RUN,
	output            DBG_BREAK
`endif
);
	
	import SH2_PKG::*;

	//CPU registers
	bit [31: 0] PC;
	bit [31: 0] GBR;
	bit [31: 0] VBR;
	SR_t        SR;
	
	PipelineState_t PIPE;
	bit         IF_STALL;
	bit         ID_STALL;
	bit         EX_STALL;
	bit [31: 0] RD_SAVE;
	bit [ 2: 0] STATE;
	DecInstr_t  ID_DECI;
	bit         SLP;
	bit [31: 0] ALU_RES;
	bit         ALU_T;
	SR_t        SR_NEW;
	bit         BR_T;
	bit         RES_EXP;
	bit         INT_REQ_LATCH;
	bit [ 3: 0] INT_LVL_LATCH;
	bit         ILI_EXP,ILSI;
	
	bit         MA_ACTIVE;
	bit         IF_ACTIVE;
	bit         VECT_ACTIVE;
	bit         INST_SPLIT;
	bit         MAWB_STALL;
	bit         IFID_STALL;
	// synopsys translate_off
	bit         LOAD_SPLIT;
	// synopsys translate_on
	
	
	//Register file
	bit [ 4: 0] REGS_RAN;
	bit [ 4: 0] REGS_RBN;
	bit [31: 0] REGS_RAQ;
	bit [31: 0] REGS_RBQ;
	bit [31: 0] REGS_R0Q;
	
	bit [ 4: 0] REGS_WAN;
	bit [31: 0] REGS_WAD;
	bit         REGS_WAE;
	bit [ 4: 0] REGS_WBN;
	bit [31: 0] REGS_WBD;
	bit         REGS_WBE;
	
`ifdef DEBUG
	assign REGS_RAN = EN ? ID_DECI.RA.N : DBG_REGN;
`else
	assign REGS_RAN = ID_DECI.RA.N;
`endif
	assign REGS_RBN = ID_DECI.RB.N;
	
	SH2_regfile regfile (CLK, RST_N, CE, EN, REGS_WAN, REGS_WAD, REGS_WAE, REGS_WBN, REGS_WBD, REGS_WBE, 
								REGS_RAN, REGS_RAQ, REGS_RBN, REGS_RBQ, REGS_R0Q);

	
	//**********************************************************
	//PC
	//**********************************************************
	wire PC_STALL = (MA_ACTIVE & BUS_WAIT) | (IF_ACTIVE & BUS_WAIT) | (VECT_ACTIVE & VECT_WAIT) | INST_SPLIT | IFID_STALL;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			PC <= '0;
		end
		else if (!RES_N) begin
			PC <= '0;
		end
		else if (EN && CE) begin
			if (PIPE.EX.DI.PCW && !EX_STALL) begin
				PC <= ALU_RES;
			end else if (!PC_STALL && !ID_DECI.SLP && !SLP) begin
				PC <= PC + 2;
			end
		end
	end

	wire LOAD_ISSUE = (PIPE.EX.DI.MEM.R | (PIPE.EX.DI.MAC.R & ~PIPE.EX.DI.MEM.W)) & ((PIPE.EX.DI.RA.W & PIPE.EX.DI.RA.N == ID_DECI.RA.N & ID_DECI.RA.R) |
	                                                                                 (PIPE.EX.DI.RA.W & PIPE.EX.DI.RA.N == ID_DECI.RB.N & ID_DECI.RB.R) |
	                                                                                 (PIPE.EX.DI.RA.W & PIPE.EX.DI.RA.N ==         5'd0 & ID_DECI.R0R ));
	wire INST_ISSUE = ((IFID_STALL & ~PC[1]) | ~PIPE.ID.PC[1]) & (PIPE.EX.DI.MEM.R | PIPE.EX.DI.MEM.W | PIPE.EX.DI.MAC.R | PIPE.EX.DI.MAC.W) & ~ID_DECI.IID;
	
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			MA_ACTIVE <= 0;
			IF_ACTIVE <= 0;
			VECT_ACTIVE <= 0;
			INST_SPLIT <= 0;
			MAWB_STALL <= 0;
			// synopsys translate_off
			LOAD_SPLIT <= 0;
			// synopsys translate_on
		end
		else if (!RES_N) begin
			MA_ACTIVE <= 0;
			IF_ACTIVE <= 0;
			INST_SPLIT <= 0;
			MAWB_STALL <= 0;
		end
		else if (EN && CE) begin
			// synopsys translate_off
			if (LOAD_ISSUE && !INST_SPLIT && (!MA_ACTIVE || !BUS_WAIT) && (STATE == 3'd0) && !EX_STALL) begin
				LOAD_SPLIT <= 1;
			end else if (INST_SPLIT && (!MA_ACTIVE || !BUS_WAIT)) begin
				LOAD_SPLIT <= 0;
			end
			// synopsys translate_on
			
			if ((PIPE.EX.DI.MEM.R || PIPE.EX.DI.MEM.W || PIPE.EX.DI.MAC.R || PIPE.EX.DI.MAC.W) && !INST_SPLIT && (!IF_ACTIVE || !BUS_WAIT) && !(VECT_ACTIVE && VECT_WAIT)) begin
				MA_ACTIVE <= 1;
			end else if (!BUS_WAIT && MA_ACTIVE) begin
				MA_ACTIVE <= 0;
			end
			
			if ((PC[1] && (!MA_ACTIVE || !BUS_WAIT) && !IFID_STALL && !EX_STALL) || (PIPE.EX.BC && (!MA_ACTIVE || !BUS_WAIT))) begin
				IF_ACTIVE <= 1;
			end else if (!BUS_WAIT && IF_ACTIVE && !PC_STALL) begin
				IF_ACTIVE <= 0;
			end
			
			if (PIPE.EX.DI.VECR && !INST_SPLIT && (!IF_ACTIVE || !BUS_WAIT) && (!MA_ACTIVE || !BUS_WAIT)) begin
				VECT_ACTIVE <= 1;
			end else if (!VECT_WAIT && VECT_ACTIVE) begin
				VECT_ACTIVE <= 0;
			end
			
			if ((INST_ISSUE && !INST_SPLIT && (!MA_ACTIVE || !BUS_WAIT) && (!IFID_STALL || STATE == ID_DECI.LST)) || 
				 (LOAD_ISSUE && !INST_SPLIT && (!MA_ACTIVE || !BUS_WAIT) && (STATE == 3'd0) && !EX_STALL)) begin
				INST_SPLIT <= 1;
			end else if (INST_SPLIT && (!MA_ACTIVE || !BUS_WAIT)) begin
				INST_SPLIT <= 0;
			end
			
			if (INST_SPLIT && (!MA_ACTIVE || !BUS_WAIT)) begin
				MAWB_STALL <= 1;
			end else if (MAWB_STALL && (!IF_ACTIVE || !BUS_WAIT)) begin
				MAWB_STALL <= 0;
			end
		end
	end
	
	wire BUS_STALL = (MA_ACTIVE & BUS_WAIT) | (IF_ACTIVE & BUS_WAIT) | (VECT_ACTIVE & VECT_WAIT);
	
	
	//**********************************************************
	// IF stage
	//**********************************************************
	assign IF_STALL = BUS_STALL | INST_SPLIT | IFID_STALL;
	
	IFtoID_t   SAVE_ID;
	always @(posedge CLK or negedge RST_N) begin
		bit [15: 0] SAVE_IR;
		bit [15: 0] NEW_IR;
		
		if (!RST_N) begin
			PIPE.ID.IR <= 16'h0000;
			PIPE.ID.PC <= '0;
			SAVE_IR <= '0;
		end
		else if (!RES_N) begin
			PIPE.ID.IR <= 16'h0000;
			PIPE.ID.PC <= '0;
			SAVE_IR <= '0;
		end
		else if (EN && CE) begin
			if (!PC[1] || PIPE.MA.BC) begin
				NEW_IR = PC[1] ? BUS_DI[15:0] : BUS_DI[31:16];
			end
			else begin
				NEW_IR = SAVE_IR;
			end
			
			if (ID_DECI.SLP || SLP) begin
				NEW_IR = 16'h0009;
			end
				
			if (!IF_STALL) begin
				if (!PC[1] || PIPE.MA.BC) begin
					SAVE_IR <= BUS_DI[15:0];
				end
				
				if (ID_DECI.LST == 3'd0) begin
					PIPE.ID.IR <= NEW_IR;
					PIPE.ID.PC <= PC;
				end
				else begin
					SAVE_ID.IR <= NEW_IR;
					SAVE_ID.PC <= PC;
				end
			end
			
			if (!ID_STALL) begin
				if ((ID_DECI.LST != 3'd0) && (STATE == ID_DECI.LST)) begin
					PIPE.ID <= SAVE_ID;
				end
			end
		end
	end

	//**********************************************************
	//ID stage
	//**********************************************************
	assign ID_STALL = BUS_STALL | INST_SPLIT;
	
	wire INT_BLOCKED = PIPE.EX.DI.IBI;
	wire ID_DELAY_SLOT = ~PIPE.EX.DI.BR.BI & (PIPE.EX.DI.BR.BT == CB | PIPE.EX.DI.BR.BT == UCB);
	
	wire INT_EXP = ((INT_REQ && !INT_BLOCKED && !ID_DELAY_SLOT && !IFID_STALL) || INT_REQ_LATCH);
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			RES_EXP <= 1;
			INT_REQ_LATCH <= 0;
			INT_LVL_LATCH <= '0;
			ILI_EXP <= 0;
		end
		else if (!RES_N) begin
			RES_EXP <= 1;
			INT_REQ_LATCH <= 0;
			INT_LVL_LATCH <= '0;
			ILI_EXP <= 0;
		end
		else if (EN && CE) begin
			if (!ID_STALL) begin
				if (STATE == 3'd5 && RES_EXP) begin
					RES_EXP <= 0;
				end
				
				if (INT_REQ && !INT_BLOCKED && !ID_DELAY_SLOT && !IFID_STALL && !INT_REQ_LATCH) begin
					INT_REQ_LATCH <= 1;
					INT_LVL_LATCH <= INT_LVL;
				end else if (STATE == 3'd7 && INT_REQ_LATCH) begin
					INT_REQ_LATCH <= 0;
				end
				
				if (ID_DECI.ILI && !RES_EXP && !INT_EXP && !ILI_EXP) begin
					ILI_EXP <= 1;
					ILSI <= ID_DELAY_SLOT;
				end else if (STATE == 3'd6 && ILI_EXP) begin
					ILI_EXP <= 0;
				end
			end
		end
	end
	
	wire [15:0] DEC_IR = RES_EXP || INT_EXP ? 16'h0000 : 
								ID_DELAY_SLOT && !PIPE.EX.DI.BR.BD ? 16'h0009 :
								IFID_STALL ? PIPE.EX.IR : PIPE.ID.IR;
								
	assign BR_T = PIPE.EX.DI.CTRL.W && PIPE.EX.DI.CTRL.S == SR_ ? SR_NEW.T : SR.T;

generate if (VER == 1) begin : decrom
	// Instruction decoder as a ROM (SH-2 only; the SH-1 keeps the combinational Decode()). 1K x 80 M10K, shdec_rom.hex,
	// generated from Decode() by s3/sh2/dec/gen_rom.py. The ROM's address register loads in the clock before each CE
	// clock (~CE: CE_R and CE_F alternate), from the registers Decode() reads, which only change on CE edges (or reset);
	// INT_REQ is taken one clock early (INT_REQ_NEXT). So during every CE clock the ROM row equals Decode()'s result,
	// except two bits that depend on the combinational T (BT/BF at state 0: PCW = LST = BC), patched below.
	// Address: STATE 0: key of PIPE.ID.IR = {IR[15:12], sub[5:0]}, or a forced row (0000 when an interrupt is taken,
	// 0009 for a killed slot, the RES/INT sequence entry); STATE > 0: {seq[4],1,seq[3],1,seq[2:0],STATE}, seq from the
	// previous row (rows of one instruction share it) or from the exception flags.
	typedef struct packed {
		bit [2:0] RSB; bit RSC; bit PCM; bit BPWBA; bit BPLDA; bit BPMAB; bit [2:0] IMMT;
		bit SA; bit SB; bit [2:0] OP; bit [3:0] CD; bit [2:0] CMP;
		bit [1:0] ADDS; bit [1:0] WDS; bit [1:0] SZ; bit MR; bit MW; bit DF;
		bit RASEL; bit [1:0] RAC; bit RAR; bit RAW; bit [1:0] RBSEL; bit [1:0] RBC; bit RBR; bit RBW; bit R0R; bit PCW;
		bit CW; bit [1:0] CS; bit [2:0] SRS; bit [1:0] MACS; bit MACR; bit MACW; bit [3:0] MACOP;
		bit BI; bit [1:0] BT; bit BD; bit BCV; bit BSR; bit TAS; bit SLP; bit IBI; bit IID; bit [2:0] LST; bit VECR; bit ILI;
		bit [4:0] SEQ; bit CB0;
	} DecRow_t;

	DecRow_t R;
	bit [9:0] DA;
	always_comb begin
		bit [3:0] top, n, m, lo;
		bit       isLo, isHi, is04, isBr;
		bit [1:0] m2;
		bit [3:0] sub52;
		bit [9:0] key;
		bit [4:0] seq;

		top = PIPE.ID.IR[15:12]; n = PIPE.ID.IR[11:8]; m = PIPE.ID.IR[7:4]; lo = PIPE.ID.IR[3:0];
		isLo = (top == 4'h0) | (top == 4'h2) | (top == 4'h3) | (top == 4'h4) | (top == 4'h6);
		isHi = (top == 4'h8) | (top == 4'hC);
		is04 = (top == 4'h0) | (top == 4'h4);
		isBr = (top == 4'h8) | (top == 4'hA) | (top == 4'hB) | (top == 4'hC);
		m2 = (m[3] | m[2] | (m[1] & m[0])) ? 2'd3 : m[1:0];
		if (top == 4'h0 && (lo == 4'h8 || lo == 4'hB || (lo == 4'h9 && m2 != 2'd2)) && n != 4'h0) m2 = 2'd3;
		if (top == 4'h0 && lo == 4'h3 && ID_DELAY_SLOT) m2 = 2'd3;
		if (lo == 4'hB && ID_DELAY_SLOT && !m2[0]) m2 = 2'd3;
		sub52 = isHi ? n : isLo ? lo : 4'h0;
		key = {top, sub52, is04 ? m2 : {1'b0, isBr & ID_DELAY_SLOT}};

		seq = RES_EXP ? 5'd1 : INT_REQ_LATCH ? 5'd2 : ILI_EXP ? (ILSI ? 5'd4 : 5'd3) : R.SEQ;
		if (STATE != 3'd0 || RES_EXP || INT_REQ_LATCH)
			DA = {seq[4], 1'b1, seq[3], 1'b1, seq[2:0], STATE};
		else if (INT_REQ_NEXT && !INT_BLOCKED && !ID_DELAY_SLOT)
			DA = 10'h000;			//0000: interrupt taken
		else if (ID_DELAY_SLOT && !PIPE.EX.DI.BR.BD)
			DA = 10'h024;			//0009: killed slot
		else
			DA = key;
	end

	(* romstyle = "M10K" *) bit [79:0] DEC_ROM[1024];
	initial begin
		$readmemh("shdec_rom.hex", DEC_ROM);
	end
	always_ff @(posedge CLK) begin
		if (!CE) R <= DEC_ROM[DA];
	end

	wire       DR_BC = (BR_T == ~DEC_IR[9]);
	wire [4:0] DR_RAN = R.RASEL ? {1'b0, DEC_IR[11:8]} : {R.RAC[1], {4{R.RAC[0]}}};
	wire [4:0] DR_RBN = R.RBSEL[0] ? {1'b0, DEC_IR[7:4]} : R.RBSEL[1] ? {1'b0, DEC_IR[11:8]} : {R.RBC[1], {4{R.RBC[0]}}};
	assign ID_DECI = DecInstr_t'({3'b000, R.RSB, R.RSC, R.PCM, R.BPWBA, R.BPLDA, R.BPMAB, R.IMMT,
	                              R.SA, R.SB, R.OP, R.CD, R.CMP, R.ADDS, R.WDS, R.SZ, R.MR, R.MW, R.DF,
	                              DR_RAN, R.RAR, R.RAW, DR_RBN, R.RBR, R.RBW, R.R0R, R.PCW | (R.CB0 & DR_BC),
	                              R.CW, R.CS, R.SRS, R.MACS, R.MACR, R.MACW, R.MACOP,
	                              R.BI, R.BT, R.BD, R.BCV, R.BSR, R.TAS, R.SLP, R.IBI, R.IID, R.LST | {2'b00, R.CB0 & DR_BC}, R.VECR, R.ILI});
end else begin : decfn
	assign ID_DECI = Decode(DEC_IR, STATE, BR_T, ID_DELAY_SLOT, RES_EXP, INT_REQ_LATCH, ILI_EXP, ILSI, VER);
end endgenerate
	
	wire [ 2: 0] NEXT_STATE = STATE == ID_DECI.LST ? 3'd0 : STATE + 3'd1;
	always @(posedge CLK or negedge RST_N) begin
		bit BR_COND;
		
		if (!RST_N) begin
			PIPE.EX.IR <= '0;
			PIPE.EX.PC <= '0;
			PIPE.EX.DI <= DECI_RESET;
			PIPE.EX.RA <= '0;
			PIPE.EX.RB <= '0;
			PIPE.EX.R0 <= '0;
			PIPE.EX.BC <= 0;
			STATE <= '0;
			IFID_STALL <= 0;
			SLP <= 1;
		end
		else if (!RES_N) begin
			PIPE.EX.IR <= '0;
			PIPE.EX.PC <= '0;
			PIPE.EX.DI <= DECI_RESET;
			PIPE.EX.RA <= '0;
			PIPE.EX.RB <= '0;
			PIPE.EX.R0 <= '0;
			PIPE.EX.BC <= 0;
			STATE <= '0;
			IFID_STALL <= 0;
			SLP <= 0;
		end
		else if (EN && CE) begin
			BR_COND = ID_DECI.BR.BI & ((BR_T == ID_DECI.BR.BCV) | (ID_DECI.BR.BT == UCB));
			
			if (!ID_STALL) begin
				PIPE.EX.IR <= DEC_IR;
				PIPE.EX.PC <= PIPE.ID.PC;
				PIPE.EX.DI <= ID_DECI;
				PIPE.EX.RA <= REGS_RAQ;
				PIPE.EX.RB <= REGS_RBQ;
				PIPE.EX.R0 <= REGS_R0Q;
				PIPE.EX.BC <= BR_COND;
				STATE <= NEXT_STATE;
				IFID_STALL <= |NEXT_STATE;
				
				if (ID_DECI.SLP) SLP <= 1;
				if (SLP && INT_REQ) SLP <= 0;
			end
		end
	end
	
	//**********************************************************
	//EX stage
	//**********************************************************
	//Bypassing datapath
	wire BP_A_EXEX = ((PIPE.EX.DI.RA.N == PIPE.MA.DI.RA.N) & PIPE.EX.DI.RA.R & PIPE.MA.DI.RA.W & !((PIPE.MA.DI.MEM.R & !PIPE.MA.DI.MAC.W) | (PIPE.MA.DI.MAC.R & !PIPE.MA.DI.MEM.W))) |
						  ((PIPE.EX.DI.RA.N == PIPE.MA.DI.RB.N) & PIPE.EX.DI.RA.R & PIPE.MA.DI.RB.W & (PIPE.MA.DI.RA.N != PIPE.MA.DI.RB.N | !PIPE.MA.DI.RA.W));
	wire BP_B_EXEX = ((PIPE.EX.DI.RB.N == PIPE.MA.DI.RA.N) & PIPE.EX.DI.RB.R & PIPE.MA.DI.RA.W & !((PIPE.MA.DI.MEM.R & !PIPE.MA.DI.MAC.W) | (PIPE.MA.DI.MAC.R & !PIPE.MA.DI.MEM.W))) |
						  ((PIPE.EX.DI.RB.N == PIPE.MA.DI.RB.N) & PIPE.EX.DI.RB.R & PIPE.MA.DI.RB.W & (PIPE.MA.DI.RA.N != PIPE.MA.DI.RB.N | !PIPE.MA.DI.RA.W));
	wire BP_C_EXEX = ((5'd0            == PIPE.MA.DI.RA.N) & PIPE.EX.DI.R0R  & PIPE.MA.DI.RA.W & !((PIPE.MA.DI.MEM.R & !PIPE.MA.DI.MAC.W) | (PIPE.MA.DI.MAC.R & !PIPE.MA.DI.MEM.W))) |
						  ((5'd0            == PIPE.MA.DI.RB.N) & PIPE.EX.DI.R0R  & PIPE.MA.DI.RB.W & (PIPE.MA.DI.RA.N != 5'd0            | !PIPE.MA.DI.RA.W));
	
	wire BP_A_MAEX = ((PIPE.EX.DI.RA.N == PIPE.WB.DI.RA.N) & PIPE.EX.DI.RA.R & PIPE.WB.DI.RA.W & !((PIPE.WB.DI.MEM.R & !PIPE.WB.DI.MAC.W) | (PIPE.WB.DI.MAC.R & !PIPE.WB.DI.MEM.W))) |
						  ((PIPE.EX.DI.RA.N == PIPE.WB.DI.RB.N) & PIPE.EX.DI.RA.R & PIPE.WB.DI.RB.W);
	wire BP_B_MAEX = ((PIPE.EX.DI.RB.N == PIPE.WB.DI.RA.N) & PIPE.EX.DI.RB.R & PIPE.WB.DI.RA.W & !((PIPE.WB.DI.MEM.R & !PIPE.WB.DI.MAC.W) | (PIPE.WB.DI.MAC.R & !PIPE.WB.DI.MEM.W))) |
						  ((PIPE.EX.DI.RB.N == PIPE.WB.DI.RB.N) & PIPE.EX.DI.RB.R & PIPE.WB.DI.RB.W);
	wire BP_C_MAEX = ((5'd0            == PIPE.WB.DI.RA.N) & PIPE.EX.DI.R0R  & PIPE.WB.DI.RA.W & !((PIPE.WB.DI.MEM.R & !PIPE.WB.DI.MAC.W) | (PIPE.WB.DI.MAC.R & !PIPE.WB.DI.MEM.W))) |
						  ((5'd0            == PIPE.WB.DI.RB.N) & PIPE.EX.DI.R0R  & PIPE.WB.DI.RB.W);
	
	wire BP_A_WBEXA = (PIPE.EX.DI.RA.N == PIPE.WB2.DI.RA.N) & PIPE.EX.DI.RA.R & PIPE.WB2.DI.RA.W;
	wire BP_A_WBEXB = (PIPE.EX.DI.RA.N == PIPE.WB2.DI.RB.N) & PIPE.EX.DI.RA.R & PIPE.WB2.DI.RB.W;  
	wire BP_B_WBEXA = (PIPE.EX.DI.RB.N == PIPE.WB2.DI.RA.N) & PIPE.EX.DI.RB.R & PIPE.WB2.DI.RA.W;
	wire BP_B_WBEXB = (PIPE.EX.DI.RB.N == PIPE.WB2.DI.RB.N) & PIPE.EX.DI.RB.R & PIPE.WB2.DI.RB.W;
	wire BP_C_WBEXA = (5'd0            == PIPE.WB2.DI.RA.N) & PIPE.EX.DI.R0R  & PIPE.WB2.DI.RA.W;
	wire BP_C_WBEXB = (5'd0            == PIPE.WB2.DI.RB.N) & PIPE.EX.DI.R0R  & PIPE.WB2.DI.RB.W;
	
	wire BP_A_MALD = (PIPE.EX.DI.RA.N == PIPE.MA.DI.RA.N)  & PIPE.EX.DI.RA.R & PIPE.MA.DI.RA.W & ((PIPE.MA.DI.MEM.R & !PIPE.MA.DI.MAC.W) | (PIPE.MA.DI.MAC.R & !PIPE.MA.DI.MEM.W));
	wire BP_B_MALD = (PIPE.EX.DI.RB.N == PIPE.MA.DI.RA.N)  & PIPE.EX.DI.RB.R & PIPE.MA.DI.RA.W & ((PIPE.MA.DI.MEM.R & !PIPE.MA.DI.MAC.W) | (PIPE.MA.DI.MAC.R & !PIPE.MA.DI.MEM.W));
	wire BP_C_MALD = (5'd0            == PIPE.MA.DI.RA.N)  & PIPE.EX.DI.R0R  & PIPE.MA.DI.RA.W & ((PIPE.MA.DI.MEM.R & !PIPE.MA.DI.MAC.W) | (PIPE.MA.DI.MAC.R & !PIPE.MA.DI.MEM.W));
						  
	wire BP_A_WBLD = (PIPE.EX.DI.RA.N == PIPE.WB.DI.RA.N)  & PIPE.EX.DI.RA.R & PIPE.WB.DI.RA.W & ((PIPE.WB.DI.MEM.R & !PIPE.WB.DI.MAC.W) | (PIPE.WB.DI.MAC.R & !PIPE.WB.DI.MEM.W));
	wire BP_B_WBLD = (PIPE.EX.DI.RB.N == PIPE.WB.DI.RA.N)  & PIPE.EX.DI.RB.R & PIPE.WB.DI.RA.W & ((PIPE.WB.DI.MEM.R & !PIPE.WB.DI.MAC.W) | (PIPE.WB.DI.MAC.R & !PIPE.WB.DI.MEM.W));
	wire BP_C_WBLD = (5'd0            == PIPE.WB.DI.RA.N)  & PIPE.EX.DI.R0R  & PIPE.WB.DI.RA.W & ((PIPE.WB.DI.MEM.R & !PIPE.WB.DI.MAC.W) | (PIPE.WB.DI.MAC.R & !PIPE.WB.DI.MEM.W));
		
	bit [31: 0] REG_A;
	bit [31: 0] REG_B;
	bit [31: 0] REG_C;
	always_comb begin
		bit [11: 0] ir_imm;
		bit [ 7: 0] vec;
		bit [31: 0] temp, IMM_VAL, SCR_VAL;
		bit [31: 0] BP_A, BP_B, BP_C;
		
		ir_imm = PIPE.EX.IR[11:0];
		vec = RES_EXP       ? {6'b000000,~NMI_N,1'b0} : 
		      INT_REQ_LATCH ? INT_VEC : 
				ILI_EXP       ? 8'h04 | {6'b000000,ILSI,1'b0} : 
				                PIPE.EX.IR[7:0];
		
		case (PIPE.EX.DI.IMMT)
			ZIMM4:  temp = {{28{1'b0}},      ir_imm[ 3:0]};
			SIMM8:  temp = {{24{ir_imm[ 7]}},ir_imm[ 7:0]};
			ZIMM8:  temp = {{24{1'b0}},      ir_imm[ 7:0]};
			SIMM12: temp = {{20{ir_imm[11]}},ir_imm[11:0]};
			ZERO:   temp = 32'h00000000;
			ONE:    temp = 32'h00000001;
			VECT:   temp = {{24{1'b0}},      vec};
			default: temp = 32'h00000000;
		endcase
		
		if (PIPE.EX.DI.BR.BI) begin
			IMM_VAL = {temp[30:0],1'b0};
		end else begin
			case (PIPE.EX.DI.MEM.SZ)
				2'b00:   IMM_VAL = temp;
				2'b01:   IMM_VAL = {temp[30:0],1'b0};
				default: IMM_VAL = {temp[29:0],2'b00};
			endcase
		end
		
		case (PIPE.EX.DI.CTRL.S)
			SR_:  SCR_VAL = SR & 32'h000003F3;
			GBR_: SCR_VAL = GBR;
			VBR_: SCR_VAL = VBR;
			default: SCR_VAL = 32'h00000000;
		endcase
		
		if (BP_A_EXEX) begin
			BP_A = PIPE.MA.RES;
		end
		else if (BP_A_MALD) begin
			BP_A = RD_SAVE;
		end
		else if (BP_A_WBLD || PIPE.EX.DI.DP.BPLDA) begin
			BP_A = PIPE.WB.RD;
		end
		else if (BP_A_MAEX) begin
			BP_A = PIPE.WB.RES;
		end
		else if (BP_A_WBEXA || PIPE.EX.DI.DP.BPWBA) begin
			BP_A = PIPE.WB2.RESA;
		end
		else if (BP_A_WBEXB) begin
			BP_A = PIPE.WB2.RESB;
		end
		else begin
			BP_A = PIPE.EX.RA;
		end
	
		REG_A = BP_A;
		
		if (BP_B_EXEX || PIPE.EX.DI.DP.BPMAB) begin
			BP_B = PIPE.MA.RES;
		end
		else if (BP_B_MALD) begin
			BP_B = RD_SAVE;
		end
		else if (BP_B_WBLD) begin
			BP_B = PIPE.WB.RD;
		end
		else if (BP_B_MAEX) begin
			BP_B = PIPE.WB.RES;
		end
		else if (BP_B_WBEXA) begin
			BP_B = PIPE.WB2.RESA;
		end
		else if (BP_B_WBEXB) begin
			BP_B = PIPE.WB2.RESB;
		end
		else begin
			BP_B = PIPE.EX.RB;
		end
		
		case (PIPE.EX.DI.DP.RSB)
			GRX: REG_B = BP_B;
			BPC: REG_B = {PC[31:2],PC[1:0] & {2{~PIPE.EX.DI.DP.PCM}}};
			TPC: REG_B = SAVE_ID.PC;
			IPC: REG_B = PIPE.EX.PC;
			SCR: REG_B = SCR_VAL;
			default: REG_B = 32'h0;
		endcase
		
		if (BP_C_EXEX) begin
			BP_C = PIPE.MA.RES;
		end
		else if (BP_C_MALD) begin
			BP_C = RD_SAVE;
		end
		else if (BP_C_WBLD) begin
			BP_C = PIPE.WB.RD;
		end
		else if (BP_C_MAEX) begin
			BP_C = PIPE.WB.RES;
		end
		else if (BP_C_WBEXA) begin
			BP_C = PIPE.WB2.RESA;
		end
		else if (BP_C_WBEXB) begin
			BP_C = PIPE.WB2.RESB;
		end
		else begin
			BP_C = PIPE.EX.R0;
		end
		
		case (PIPE.EX.DI.DP.RSC)
			1'b0: REG_C = BP_C;
			1'b1: REG_C = IMM_VAL;
		endcase
	end
	
	bit [31:0] ALU_A;
	bit [31:0] ALU_B;
	always_comb begin
		
		bit [31:0] ADDER_RES;
		bit        ADDER_C;
		bit        ADDER_V;
		bit [31:0] LOG_RES;
		bit        LOG_Z;
		bit [31:0] EXT_RES;
		bit [31:0] SHIFT_RES;
		bit        SHIFT_C;
		
		bit [31:0] adder_a;
		bit [ 3:0] adder_code;
		bit [ 2:0] adder_cmp;
		bit        ge_hs, eq, str_eq;
		bit [31:0] log_b;
		
		case (PIPE.EX.DI.ALU.SA)
			0: ALU_A = REG_A;
			1: ALU_A = REG_C;
		endcase

		case (PIPE.EX.DI.ALU.SB)
			0: ALU_B = REG_B;
			1: ALU_B = REG_C;
		endcase
		
		adder_a = PIPE.EX.DI.ALU.OP == DIV ? {ALU_A[30:0],SR.T} : ALU_A;
		adder_code = PIPE.EX.DI.ALU.OP == DIV ? {3'b000,(SR.M ~^ SR.Q)} : PIPE.EX.DI.ALU.CD;
		adder_cmp = PIPE.EX.DI.ALU.CMP;
		{ADDER_C,ADDER_RES} = Adder(adder_a,ALU_B,SR.T,adder_code);
		ADDER_V = ~((ALU_A[31] ^ ALU_B[31]) ^ adder_code[0]) & (ALU_A[31] ^ ADDER_RES[31]);
		ge_hs = (~ALU_A[31] & ~ALU_B[31] & ~ADDER_RES[31]) | (ALU_A[31] & ALU_B[31] & ~ADDER_RES[31]) | ((adder_cmp[0] ^ ALU_A[31]) & (~adder_cmp[0] ^ ALU_B[31]));
		eq = ~|ADDER_RES[31:0];
		
		// NOP (ALU_RES = ALU_B) goes through the logic unit with the 'pass b' code (Log code 110: b ^ 0); TAS's 0x80
		// operand only for LOG. ALU.OP is ADD, LOG, EXT, SHIFT, DIV or NOP (decoder rows, DECI_RESET), so ALU_RES is
		// selected by OP[1:0] alone: 00 ADD/DIV, 01 LOG/NOP, 10 EXT, 11 SHIFT.
		log_b = PIPE.EX.DI.TAS && !PIPE.EX.DI.ALU.OP[2] ? 32'h00000080 : ALU_B;
		LOG_RES = Log(ALU_A,log_b,PIPE.EX.DI.ALU.OP[2] ? 4'b0110 : PIPE.EX.DI.ALU.CD);
		LOG_Z = ~|LOG_RES;
		str_eq = ~|LOG_RES[31:24] | ~|LOG_RES[23:16] | ~|LOG_RES[15:8] | ~|LOG_RES[7:0];
		
		EXT_RES = Ext(ALU_A,ALU_B,PIPE.EX.DI.ALU.CD);
		
		{SHIFT_C,SHIFT_RES} = Shifter(ALU_A,SR.T,PIPE.EX.DI.ALU.CD);
		
		case (PIPE.EX.DI.ALU.OP[1:0])
			2'b00: ALU_RES = ADDER_RES;	//ADD, DIV
			2'b01: ALU_RES = LOG_RES;		//LOG, NOP
			2'b10: ALU_RES = EXT_RES;
			2'b11: ALU_RES = SHIFT_RES;
		endcase
								
		ALU_T = 0;
		case (PIPE.EX.DI.ALU.OP)
			ADD: case (PIPE.EX.DI.ALU.CD[3:2])
					2'b01: case (PIPE.EX.DI.ALU.CMP[2:1])
						2'b00: ALU_T = eq;
						2'b01: ALU_T = ge_hs;
						2'b11: ALU_T = ge_hs & ~eq;
						default:;
					endcase
					2'b10: ALU_T = ADDER_C;
					2'b11: ALU_T = ADDER_V;
					default:;
				endcase
			LOG: ALU_T = PIPE.EX.DI.ALU.CD[3] ? str_eq : LOG_Z;
			SHIFT: ALU_T = SHIFT_C;
			DIV: ALU_T = ADDER_C;
			default:;
		endcase
	end
	
	bit [31: 0] MA_ADDR;
	always_comb begin
		MA_ADDR = ALU_RES;
		case (PIPE.EX.DI.MEM.ADDS)
			ALUA:    MA_ADDR = REG_A;
			ALUB:    MA_ADDR = REG_B;
			ALURES:  MA_ADDR = ALU_RES;
			default:;
		endcase
	end
	
	bit [31: 0] MA_WD;
	always_comb begin
		MA_WD = ALU_RES;
		case (PIPE.EX.DI.MEM.WDS)
			ALUA: MA_WD = REG_A;
			ALUB: MA_WD = REG_B;
			ALURES: MA_WD = ALU_RES;
			default:;
		endcase
	end
	
	assign EX_STALL = BUS_STALL | INST_SPLIT;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			PIPE.MA.IR <= '0;
			PIPE.MA.DI <= DECI_RESET;
			PIPE.MA.BC <= 0;
			PIPE.MA.RES <= '0;
			PIPE.MA.ADDR <= '0;
			PIPE.MA.WD <= '0;
		end
		else if (!RES_N) begin
			PIPE.MA.IR <= '0;
			PIPE.MA.DI <= DECI_RESET;
			PIPE.MA.PC <= '0;
			PIPE.MA.BC <= 0;
			PIPE.MA.RES <= '0;
			PIPE.MA.ADDR <= '0;
			PIPE.MA.WD <= '0;
		end
		else if (EN && CE) begin
			if (!EX_STALL) begin
				PIPE.MA.IR <= PIPE.EX.IR;
				PIPE.MA.DI <= PIPE.EX.DI;
				PIPE.MA.PC <= PIPE.EX.PC;
				PIPE.MA.BC <= PIPE.EX.BC;
				PIPE.MA.RES <= PIPE.EX.DI.BR.BI ? REG_B : ALU_RES;
				PIPE.MA.ADDR <= MA_ADDR;
				PIPE.MA.WD <= MA_WD;
			end
		end
	end
	
	always_comb begin
		SR_NEW = SR & 32'h000003F3;
		case (PIPE.EX.DI.CTRL.SRS)
			LOAD: SR_NEW = ALU_RES;
			ALU:case (PIPE.EX.DI.ALU.OP)
					ADD: SR_NEW.T = ALU_T;
					LOG: SR_NEW.T = ALU_T;
					SHIFT: SR_NEW.T = ALU_T;
					DIV: begin
						SR_NEW.Q = REG_A[31] ^ SR.M ^ ALU_T;
						SR_NEW.T = (REG_A[31] ^ SR.M ^ ALU_T) ~^ SR.M;
					end
					NOP: SR_NEW.T = ALU_RES[0];
					default:;
				endcase
			DIV0S: begin
				SR_NEW.Q = REG_A[31];
				SR_NEW.M = REG_B[31];
				SR_NEW.T = REG_A[31] ^ REG_B[31];
			end
			DIV0U: begin
				SR_NEW.Q = 0;
				SR_NEW.M = 0;
				SR_NEW.T = 0;
			end
			IMSK: SR_NEW.I = INT_LVL_LATCH;
			default:;
		endcase
	end
	
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			SR <= SR_RESET;
			GBR <= '0;
			VBR <= '0;
		end
		else if (!RES_N) begin
			SR <= SR_RESET;
			GBR <= '0;
			VBR <= '0;
		end
		else if (EN && CE) begin
			if (!EX_STALL) begin
				if (PIPE.EX.DI.CTRL.W) begin
					case (PIPE.EX.DI.CTRL.S)
						SR_:  SR <= SR_NEW & 32'h000003F3;
						GBR_: GBR <= ALU_RES;
						VBR_: VBR <= ALU_RES;
						default:;
					endcase
				end
			end
		end
	end
	
	
	//**********************************************************
	//MA stage
	//**********************************************************
	bit [31: 0] MA_RDATA;
	always_comb begin
		bit [ 1: 0] mask;
		bit [31: 0] temp;

		case (PIPE.MA.DI.MEM.SZ)
			2'b00:   mask = 2'b11;
			2'b01:   mask = 2'b10;
			default: mask = 2'b00;
		endcase
		
		temp = ByteShiftRigth(BUS_DI, (~PIPE.MA.ADDR[1:0] & mask));
		
		case (PIPE.MA.DI.MEM.SZ)
			2'b00:   MA_RDATA = {{24{temp[ 7]}},temp[ 7:0]};
			2'b01:   MA_RDATA = {{16{temp[15]}},temp[15:0]};
			default: MA_RDATA = temp;
		endcase
	end
	
	wire MA_STALL = BUS_STALL | MAWB_STALL;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			PIPE.WB.IR <= '0;
			PIPE.WB.DI <= DECI_RESET;
			PIPE.WB.RES <= '0;
			PIPE.WB.RD <= '0;
		end
		else if (!RES_N) begin
			PIPE.WB.IR <= '0;
			PIPE.WB.DI <= DECI_RESET;
			PIPE.WB.RES <= '0;
			PIPE.WB.RD <= '0;
		end
		else if (EN && CE) begin
			if (!MA_STALL && !INST_SPLIT) begin
				PIPE.WB.IR <= PIPE.MA.IR;
				PIPE.WB.DI <= PIPE.MA.DI;
				PIPE.WB.PC <= PIPE.MA.PC;
				PIPE.WB.RES <= PIPE.MA.RES;
				PIPE.WB.RD <= MA_RDATA;
				RD_SAVE <= MA_RDATA;
			end
			else if (!MA_STALL && INST_SPLIT) begin
				RD_SAVE <= MA_RDATA;
			end
			else if (!(IF_ACTIVE & BUS_WAIT) && MAWB_STALL) begin
				PIPE.WB.IR <= PIPE.MA.IR;
				PIPE.WB.DI <= PIPE.MA.DI;
				PIPE.WB.PC <= PIPE.MA.PC;
				PIPE.WB.RES <= PIPE.MA.RES;
				PIPE.WB.RD <= RD_SAVE;
			end
		end
	end
	
	bit [31: 0] MA_WDATA;
	bit [ 3: 0] MA_BA;
	always_comb begin
		bit [31: 0] temp;

		temp = PIPE.MA.WD;
		
		case (PIPE.MA.DI.MEM.SZ)
			2'b00:   MA_WDATA = {temp[7:0],temp[7:0],temp[7:0],temp[7:0]};
			2'b01:   MA_WDATA = {temp[15:0],temp[15:0]};
			default: MA_WDATA = temp;
		endcase
		
		case (PIPE.MA.DI.MEM.SZ)
			2'b00:   MA_BA = 4'b0001 << ~PIPE.MA.ADDR[1:0];
			2'b01:   MA_BA = 4'b0011 << {~PIPE.MA.ADDR[1],1'b0};
			default: MA_BA = 4'b1111;
		endcase
	end
	
	//**********************************************************
	//WB stage
	//**********************************************************
	wire WB_STALL = BUS_STALL | MAWB_STALL;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			PIPE.WB2.IR <= '0;
			PIPE.WB2.DI <= DECI_RESET;
			PIPE.WB2.RESA <= '0;
			PIPE.WB2.RESB <= '0;
		end
		else if (!RES_N) begin
			PIPE.WB2.IR <= '0;
			PIPE.WB2.DI <= DECI_RESET;
			PIPE.WB2.RESA <= '0;
			PIPE.WB2.RESB <= '0;
		end
		else if (EN && CE) begin
			if (!WB_STALL && !INST_SPLIT) begin
				PIPE.WB2.IR <= PIPE.WB.IR;
				PIPE.WB2.DI <= PIPE.WB.DI;
				PIPE.WB2.RESA <= (PIPE.WB.DI.MEM.R && !PIPE.WB.DI.MAC.W) || (PIPE.WB.DI.MAC.R && !PIPE.WB.DI.MEM.W) ? PIPE.WB.RD : PIPE.WB.RES;
				PIPE.WB2.RESB <= PIPE.WB.RES;
			end
			else if (!(IF_ACTIVE & BUS_WAIT) && MAWB_STALL) begin
				PIPE.WB2.IR <= PIPE.WB.IR;
				PIPE.WB2.DI <= PIPE.WB.DI;
				PIPE.WB2.RESA <= (PIPE.WB.DI.MEM.R && !PIPE.WB.DI.MAC.W) || (PIPE.WB.DI.MAC.R && !PIPE.WB.DI.MEM.W) ? PIPE.WB.RD : PIPE.WB.RES;
				PIPE.WB2.RESB <= PIPE.WB.RES;
			end
		end
	end
	
	assign REGS_WAN = PIPE.WB.DI.RA.N;
	assign REGS_WAD = (PIPE.WB.DI.MEM.R && !PIPE.WB.DI.MAC.W) || (PIPE.WB.DI.MAC.R && !PIPE.WB.DI.MEM.W) ? PIPE.WB.RD : PIPE.WB.RES;
	assign REGS_WAE = PIPE.WB.DI.RA.W & !WB_STALL;
	
	assign REGS_WBN = PIPE.WB.DI.RB.N;
	assign REGS_WBD = PIPE.WB.RES;
	assign REGS_WBE = PIPE.WB.DI.RB.W & (!PIPE.WB.DI.RA.W | PIPE.WB.DI.RA.N != PIPE.WB.DI.RB.N) & !WB_STALL;
	
	//Ports
	assign BUS_A = MA_ACTIVE ? PIPE.MA.ADDR : (PC & 32'hFFFFFFFC);
	// BUS_A one clock early: the values PC, MA_ACTIVE and PIPE.MA.ADDR take at the next clock edge, from the same
	// conditions as their always blocks (RST_N low: all held at 0).
	wire        MA_ACTIVE_NEXT = !RES_N ? 1'b0 :
	                             !(EN && CE) ? MA_ACTIVE :
	                             (PIPE.EX.DI.MEM.R || PIPE.EX.DI.MEM.W || PIPE.EX.DI.MAC.R || PIPE.EX.DI.MAC.W) && !INST_SPLIT &&
	                             (!IF_ACTIVE || !BUS_WAIT) && !(VECT_ACTIVE && VECT_WAIT) ? 1'b1 :
	                             !BUS_WAIT && MA_ACTIVE ? 1'b0 : MA_ACTIVE;
	wire [31:0] PC_NEXT = !RES_N ? 32'h00000000 :
	                      !(EN && CE) ? PC :
	                      PIPE.EX.DI.PCW && !EX_STALL ? ALU_RES :
	                      !PC_STALL && !ID_DECI.SLP && !SLP ? PC + 32'd2 : PC;
	wire [31:0] MA_ADDR_NEXT = !RES_N ? 32'h00000000 : EN && CE && !EX_STALL ? MA_ADDR : PIPE.MA.ADDR;
	assign BUS_A_NEXT = !RST_N ? 32'h00000000 : MA_ACTIVE_NEXT ? MA_ADDR_NEXT : (PC_NEXT & 32'hFFFFFFFC);
	assign BUS_DO = MA_WDATA;
	assign BUS_WR = PIPE.MA.DI.MEM.W & MA_ACTIVE;
	assign BUS_BA = MA_BA | {4{IF_ACTIVE & ~INST_SPLIT & ~IFID_STALL}};
	assign BUS_REQ = ((PIPE.MA.DI.MEM.R | PIPE.MA.DI.MEM.W) & MA_ACTIVE & ~MAWB_STALL) | (IF_ACTIVE & ~INST_SPLIT & ~IFID_STALL);
	assign BUS_ID = ~(PIPE.MA.DI.MEM.DF & MA_ACTIVE & ~MAWB_STALL);
	assign BUS_TAS = PIPE.MA.DI.TAS & MA_ACTIVE & ~MAWB_STALL;
	
	assign MAC_SEL = PIPE.MA.DI.MAC.S & {2{(MA_ACTIVE & ~MAWB_STALL)}};
	assign MAC_OP = PIPE.MA.DI.MAC.OP & {4{(MA_ACTIVE & ~MAWB_STALL)}};
	assign MAC_S = SR.S;
	assign MAC_WE = |PIPE.MA.DI.MAC.S & PIPE.MA.DI.MAC.W & MA_ACTIVE & ~MA_STALL;
	
	assign INT_MASK = SR.I;
	assign INT_ACP = INT_REQ & ~INT_REQ_LATCH & ~INT_BLOCKED & ~ID_DELAY_SLOT & ~IFID_STALL & ~ID_STALL;
	assign INT_ACK = PIPE.MA.DI.VECR & ~MA_STALL;
	assign VECT_REQ = VECT_ACTIVE;
	
	assign SLEEP = SLP;
	
	//Debug
`ifdef DEBUG
	assign DBG_BUS_A = MA_ACTIVE ? PIPE.MA.ADDR : PC;
	assign ILI = ID_DECI.ILI & ~ID_STALL & ~IFID_STALL;
	assign DBG_REGQ = DBG_REGN <= 5'h10 ? REGS_RAQ :
	                  DBG_REGN == 5'h11 ? SR :
							DBG_REGN == 5'h12 ? GBR :
							DBG_REGN == 5'h13 ? VBR :
							DBG_REGN == 5'h14 ? PIPE.WB.PC : '0;
							
	bit [31: 0] BP_ADDR;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			DBG_BREAK <= 0;
		end
		else begin
			BP_ADDR <= '0;
			if (BP_ADDR == PIPE.WB.PC && CE) begin
//				DBG_BREAK <= 1;
			end
			else if (!DBG_BREAK && DBG_RUN) begin
				DBG_BREAK <= 0;
			end
		end
	end
`endif

endmodule

// SH2_SHARED_CORE: one SH-2 core (SH_core's logic, VER=1) shared by both SH-2s of the Saturn, the master (MSH) and
// the slave (SSH). This file is only built with SH2_SHARED_CORE (rtl/Saturn/Saturn.sv instantiates it; SH7604.sv then
// has no SH_core of its own but this core's ports, CORE_CI / CORE_CO).
//
// What it is: SH_core C-slowed for two threads. It is EXACTLY two SH_core (VER=1) instances, thread 0 with CE = PH and
// thread 1 with CE = ~PH, where PH alternates every clock (Saturn.sv: PH = SYS_CE_R): every output of each thread equals
// that SH_core's output in every clock, for every input sequence (sim/r7_core, sim/r7_top). Thread 0 is the master and
// executes in the SYS_CE_R clocks as today's MSH core does. Thread 1 is the slave and executes in the SYS_CE_F clocks:
// Saturn.sv gives the slave's SH7604 CE_R = SYS_CE_F and CE_F = SYS_CE_R, so the whole slave runs one clk_sys (half a
// CPU clock) later than today's, out of phase with the rest of the system. That phase shift is the one behaviour change
// of SH2_SHARED_CORE (u/r7/REPORT.txt lists what it changes at the slave's boundaries); it is what lets the two cores
// share one copy of the logic: each CPU's core computes its next state in its CE_R clock from inputs that arrive in that
// clock (the cache's busy and read word, INT_REQ), so both cannot use one core in the SAME clock (rw_study/REPORT.txt A).
//
// How (a mechanical transformation of SH_core.sv; the combinational code is SH_core's, unchanged):
// - every state register X becomes a 2-deep chain: X (the executing thread's state, read by the shared next-state
//   logic) and X_1 (the other thread's state). Every clock X_1 <= the executing thread's next state (X when it holds)
//   and X <= X_1. SH_core's synchronous reset (RES_N, applied in every clock, not only in CE clocks) is applied to X_1
//   with the executing thread's RES_N and on the way X_1 -> X with the other thread's, so each thread's RES_N acts in
//   each of its clocks as in SH_core.
// - registers SH_core does not reset on RST_N (SAVE_ID, ILSI, PIPE.MA.PC, PIPE.WB.PC, RD_SAVE) keep rotating while
//   RST_N is low (separate blocks), so the thread <-> chain position mapping never slips (PH keeps toggling).
// - the decoder ROM (SH_core's decrom) is read every clock, for the thread that executes in the next clock: its
//   address comes from that thread's registers (X_1) and its INT_REQ_NEXT; that thread's last row's SEQ is the row
//   read one clock ago (SEQ_D).
// - the two register files stay (each one's single MLAB write port is busy in both clocks of its thread: port A in
//   the thread's CE clock, the latched port B in the next one); their read outputs are selected by PH.
// - the port logic exists twice: once from X (the executing thread, with its own inputs), once from X_1 (the other
//   thread, whose outputs also depend combinationally on its own BUS_WAIT / VECT_WAIT / INT_REQ), and both are routed
//   to the two port sets by PH.
// - timing: the EX operands (REG_A / REG_B / ALU_A / ALU_B: SH_core's bypass network and operand selects, functions
//   of the pipeline state only) are computed one clock early from X_1 and registered (EXOP), so the paths operands ->
//   ALU -> T -> branch decode -> IF / ID, real one-clock paths here, start at a register (see the EX stage). The VECT
//   immediate's vector number, which comes from inputs (NMI_N, INT_VEC), is still added in the EX clock.
// DEBUG (SH7604's DBG_REGN / DBG_REGQ / DBG_RUN / DBG_BREAK, per thread): DBG_BREAK is 0 as in SH_core (which never
// sets it); DBG_REGQ is SH_core's for the registers SR / GBR / VBR / WB PC (DBG_REGN 17-20) in every clock, and for
// R0-R15 / PR (DBG_REGN 0-16) while EN = 0 (SH_core then reads the register file at DBG_REGN; the debugger's pause)
// and in the thread's own CE clocks; while EN = 1, SH_core's register-file read follows its decoder's address, which
// in its non-CE clocks is that of a stale decoder row: there the shared core shows the register at the executing
// thread's address instead.
//
// Ports (each thread's SH_core ports, packed; SH7604.sv packs and unpacks them):
//   CIn [49:0]  = {RES_N, NMI_N, BUS_DI[31:0], BUS_WAIT, INT_LVL[3:0], INT_VEC[7:0], INT_REQ, INT_REQ_NEXT, VECT_WAIT}
//   COn [119:0] = {BUS_A[31:0], BUS_DO[31:0], BUS_WR, BUS_BA[3:0], BUS_REQ, BUS_ID, BUS_TAS, BUS_A_NEXT[31:0],
//                  MAC_SEL[1:0], MAC_OP[3:0], MAC_S, MAC_WE, INT_MASK[3:0], INT_ACK, INT_ACP, VECT_REQ, SLEEP}
`ifdef SH2_SHARED_CORE
module SH_core_cs
 (
	input             CLK,
	input             RST_N,
	input             PH,		//1: thread 0 (MSH) executes in this clock, 0: thread 1 (SSH); toggles every clock
	input             EN,
	input      [49:0] CI0,
	input      [49:0] CI1,
	output    [119:0] CO0,
	output    [119:0] CO1
`ifdef DEBUG
	                  ,
	input       [4:0] DBG_REGN0,
	output     [31:0] DBG_REGQ0,
	input             DBG_RUN0,
	output            DBG_BREAK0,
	input       [4:0] DBG_REGN1,
	output     [31:0] DBG_REGQ1,
	input             DBG_RUN1,
	output            DBG_BREAK1
`endif
);

	import SH2_PKG::*;

	//thread inputs
	wire        RES_N0 = CI0[49], NMI_N0 = CI0[48], BUS_WAIT0 = CI0[15], INT_REQ0 = CI0[2], INT_REQ_NEXT0 = CI0[1], VECT_WAIT0 = CI0[0];
	wire [31:0] BUS_DI0 = CI0[47:16];
	wire  [3:0] INT_LVL0 = CI0[14:11];
	wire  [7:0] INT_VEC0 = CI0[10:3];
	wire        RES_N1 = CI1[49], NMI_N1 = CI1[48], BUS_WAIT1 = CI1[15], INT_REQ1 = CI1[2], INT_REQ_NEXT1 = CI1[1], VECT_WAIT1 = CI1[0];
	wire [31:0] BUS_DI1 = CI1[47:16];
	wire  [3:0] INT_LVL1 = CI1[14:11];
	wire  [7:0] INT_VEC1 = CI1[10:3];

	//the executing thread's inputs (SH_core's names)
	wire        RES_N     = PH ? RES_N0 : RES_N1;
	wire        NMI_N     = PH ? NMI_N0 : NMI_N1;
	wire [31:0] BUS_DI    = PH ? BUS_DI0 : BUS_DI1;
	wire        BUS_WAIT  = PH ? BUS_WAIT0 : BUS_WAIT1;
	wire  [3:0] INT_LVL   = PH ? INT_LVL0 : INT_LVL1;
	wire  [7:0] INT_VEC   = PH ? INT_VEC0 : INT_VEC1;
	wire        INT_REQ   = PH ? INT_REQ0 : INT_REQ1;
	wire        VECT_WAIT = PH ? VECT_WAIT0 : VECT_WAIT1;
	//the other thread's inputs
	wire        o_RES_N        = PH ? RES_N1 : RES_N0;
	wire        o_BUS_WAIT     = PH ? BUS_WAIT1 : BUS_WAIT0;
	wire        o_INT_REQ      = PH ? INT_REQ1 : INT_REQ0;
	wire        o_INT_REQ_NEXT = PH ? INT_REQ_NEXT1 : INT_REQ_NEXT0;
	wire        o_VECT_WAIT    = PH ? VECT_WAIT1 : VECT_WAIT0;

	//CPU registers (X: executing thread, X_1: the other thread)
	bit [31: 0] PC, PC_1;
	bit [31: 0] GBR, GBR_1;
	bit [31: 0] VBR, VBR_1;
	SR_t        SR, SR_1;

	PipelineState_t PIPE, PIPE_1;
	bit         IF_STALL;
	bit         ID_STALL;
	bit         EX_STALL;
	bit [31: 0] RD_SAVE, RD_SAVE_1;
	bit [ 2: 0] STATE, STATE_1;
	DecInstr_t  ID_DECI;
	bit         SLP, SLP_1;
	bit [31: 0] ALU_RES;
	bit         ALU_T;
	SR_t        SR_NEW;
	bit         BR_T;
	bit         RES_EXP, RES_EXP_1;
	bit         INT_REQ_LATCH, INT_REQ_LATCH_1;
	bit [ 3: 0] INT_LVL_LATCH, INT_LVL_LATCH_1;
	bit         ILI_EXP, ILI_EXP_1, ILSI, ILSI_1;

	bit         MA_ACTIVE, MA_ACTIVE_1;
	bit         IF_ACTIVE, IF_ACTIVE_1;
	bit         VECT_ACTIVE, VECT_ACTIVE_1;
	bit         INST_SPLIT, INST_SPLIT_1;
	bit         MAWB_STALL, MAWB_STALL_1;
	bit         IFID_STALL, IFID_STALL_1;


	//Register files (one per thread)
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

	assign REGS_RAN = ID_DECI.RA.N;
	assign REGS_RBN = ID_DECI.RB.N;

	// SH_core's REGS_RAN with DEBUG: EN ? ID_DECI.RA.N : DBG_REGN, per thread (each register file has its own port A
	// read address; while EN = 1 only the executing thread's read is used)
`ifdef DEBUG
	wire  [4:0] RAN0 = EN ? REGS_RAN : DBG_REGN0;
	wire  [4:0] RAN1 = EN ? REGS_RAN : DBG_REGN1;
`else
	wire  [4:0] RAN0 = REGS_RAN;
	wire  [4:0] RAN1 = REGS_RAN;
`endif
	bit [31: 0] RAQ0, RBQ0, R0Q0, RAQ1, RBQ1, R0Q1;
	SH2_regfile regfile0 (CLK, RST_N,  PH, EN, REGS_WAN, REGS_WAD, REGS_WAE, REGS_WBN, REGS_WBD, REGS_WBE,
								RAN0, RAQ0, REGS_RBN, RBQ0, R0Q0);
	SH2_regfile regfile1 (CLK, RST_N, ~PH, EN, REGS_WAN, REGS_WAD, REGS_WAE, REGS_WBN, REGS_WBD, REGS_WBE,
								RAN1, RAQ1, REGS_RBN, RBQ1, R0Q1);
	assign REGS_RAQ = PH ? RAQ0 : RAQ1;
	assign REGS_RBQ = PH ? RBQ0 : RBQ1;
	assign REGS_R0Q = PH ? R0Q0 : R0Q1;


	//**********************************************************
	//PC
	//**********************************************************
	wire PC_STALL = (MA_ACTIVE & BUS_WAIT) | (IF_ACTIVE & BUS_WAIT) | (VECT_ACTIVE & VECT_WAIT) | INST_SPLIT | IFID_STALL;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			PC <= '0;
			PC_1 <= '0;
		end
		else begin
			PC_1 <= PC;
			if (!RES_N) begin
				PC_1 <= '0;
			end
			else if (EN) begin
				if (PIPE.EX.DI.PCW && !EX_STALL) begin
					PC_1 <= ALU_RES;
				end else if (!PC_STALL && !ID_DECI.SLP && !SLP) begin
					PC_1 <= PC + 2;
				end
			end
			PC <= o_RES_N ? PC_1 : '0;
		end
	end

	wire LOAD_ISSUE = (PIPE.EX.DI.MEM.R | (PIPE.EX.DI.MAC.R & ~PIPE.EX.DI.MEM.W)) & ((PIPE.EX.DI.RA.W & PIPE.EX.DI.RA.N == ID_DECI.RA.N & ID_DECI.RA.R) |
	                                                                                 (PIPE.EX.DI.RA.W & PIPE.EX.DI.RA.N == ID_DECI.RB.N & ID_DECI.RB.R) |
	                                                                                 (PIPE.EX.DI.RA.W & PIPE.EX.DI.RA.N ==         5'd0 & ID_DECI.R0R ));
	wire INST_ISSUE = ((IFID_STALL & ~PC[1]) | ~PIPE.ID.PC[1]) & (PIPE.EX.DI.MEM.R | PIPE.EX.DI.MEM.W | PIPE.EX.DI.MAC.R | PIPE.EX.DI.MAC.W) & ~ID_DECI.IID;

	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			MA_ACTIVE <= 0; IF_ACTIVE <= 0; VECT_ACTIVE <= 0; INST_SPLIT <= 0; MAWB_STALL <= 0;
			MA_ACTIVE_1 <= 0; IF_ACTIVE_1 <= 0; VECT_ACTIVE_1 <= 0; INST_SPLIT_1 <= 0; MAWB_STALL_1 <= 0;
		end
		else begin
			MA_ACTIVE_1 <= MA_ACTIVE; IF_ACTIVE_1 <= IF_ACTIVE; VECT_ACTIVE_1 <= VECT_ACTIVE; INST_SPLIT_1 <= INST_SPLIT; MAWB_STALL_1 <= MAWB_STALL;
			if (!RES_N) begin
				MA_ACTIVE_1 <= 0;
				IF_ACTIVE_1 <= 0;
				INST_SPLIT_1 <= 0;
				MAWB_STALL_1 <= 0;
			end
			else if (EN) begin
				if ((PIPE.EX.DI.MEM.R || PIPE.EX.DI.MEM.W || PIPE.EX.DI.MAC.R || PIPE.EX.DI.MAC.W) && !INST_SPLIT && (!IF_ACTIVE || !BUS_WAIT) && !(VECT_ACTIVE && VECT_WAIT)) begin
					MA_ACTIVE_1 <= 1;
				end else if (!BUS_WAIT && MA_ACTIVE) begin
					MA_ACTIVE_1 <= 0;
				end

				if ((PC[1] && (!MA_ACTIVE || !BUS_WAIT) && !IFID_STALL && !EX_STALL) || (PIPE.EX.BC && (!MA_ACTIVE || !BUS_WAIT))) begin
					IF_ACTIVE_1 <= 1;
				end else if (!BUS_WAIT && IF_ACTIVE && !PC_STALL) begin
					IF_ACTIVE_1 <= 0;
				end

				if (PIPE.EX.DI.VECR && !INST_SPLIT && (!IF_ACTIVE || !BUS_WAIT) && (!MA_ACTIVE || !BUS_WAIT)) begin
					VECT_ACTIVE_1 <= 1;
				end else if (!VECT_WAIT && VECT_ACTIVE) begin
					VECT_ACTIVE_1 <= 0;
				end

				if ((INST_ISSUE && !INST_SPLIT && (!MA_ACTIVE || !BUS_WAIT) && (!IFID_STALL || STATE == ID_DECI.LST)) ||
					 (LOAD_ISSUE && !INST_SPLIT && (!MA_ACTIVE || !BUS_WAIT) && (STATE == 3'd0) && !EX_STALL)) begin
					INST_SPLIT_1 <= 1;
				end else if (INST_SPLIT && (!MA_ACTIVE || !BUS_WAIT)) begin
					INST_SPLIT_1 <= 0;
				end

				if (INST_SPLIT && (!MA_ACTIVE || !BUS_WAIT)) begin
					MAWB_STALL_1 <= 1;
				end else if (MAWB_STALL && (!IF_ACTIVE || !BUS_WAIT)) begin
					MAWB_STALL_1 <= 0;
				end
			end
			MA_ACTIVE <= MA_ACTIVE_1 & o_RES_N; IF_ACTIVE <= IF_ACTIVE_1 & o_RES_N; VECT_ACTIVE <= VECT_ACTIVE_1;
			INST_SPLIT <= INST_SPLIT_1 & o_RES_N; MAWB_STALL <= MAWB_STALL_1 & o_RES_N;
		end
	end

	wire BUS_STALL = (MA_ACTIVE & BUS_WAIT) | (IF_ACTIVE & BUS_WAIT) | (VECT_ACTIVE & VECT_WAIT);


	//**********************************************************
	// IF stage
	//**********************************************************
	assign IF_STALL = BUS_STALL | INST_SPLIT | IFID_STALL;

	IFtoID_t   SAVE_ID, SAVE_ID_1;
	bit [15: 0] SAVE_IR, SAVE_IR_1;
	always @(posedge CLK or negedge RST_N) begin
		bit [15: 0] NEW_IR;

		if (!RST_N) begin
			PIPE.ID.IR <= 16'h0000; PIPE.ID.PC <= '0; SAVE_IR <= '0;
			PIPE_1.ID.IR <= 16'h0000; PIPE_1.ID.PC <= '0; SAVE_IR_1 <= '0;
		end
		else begin
			PIPE_1.ID.IR <= PIPE.ID.IR; PIPE_1.ID.PC <= PIPE.ID.PC; SAVE_IR_1 <= SAVE_IR;
			if (!RES_N) begin
				PIPE_1.ID.IR <= 16'h0000;
				PIPE_1.ID.PC <= '0;
				SAVE_IR_1 <= '0;
			end
			else if (EN) begin
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
						SAVE_IR_1 <= BUS_DI[15:0];
					end

					if (ID_DECI.LST == 3'd0) begin
						PIPE_1.ID.IR <= NEW_IR;
						PIPE_1.ID.PC <= PC;
					end
				end

				if (!ID_STALL) begin
					if ((ID_DECI.LST != 3'd0) && (STATE == ID_DECI.LST)) begin
						PIPE_1.ID.IR <= SAVE_ID.IR;
						PIPE_1.ID.PC <= SAVE_ID.PC;
					end
				end
			end
			PIPE.ID.IR <= o_RES_N ? PIPE_1.ID.IR : 16'h0000; PIPE.ID.PC <= o_RES_N ? PIPE_1.ID.PC : '0; SAVE_IR <= o_RES_N ? SAVE_IR_1 : '0;
		end
	end
	// SAVE_ID: SH_core never resets it (it holds while RST_N is low): the chain keeps rotating then
	always @(posedge CLK) begin
		bit [15: 0] NEW_IR2;
		SAVE_ID_1.IR <= SAVE_ID.IR; SAVE_ID_1.PC <= SAVE_ID.PC;
		if (RST_N && RES_N && EN && !IF_STALL && ID_DECI.LST != 3'd0) begin
			NEW_IR2 = (!PC[1] || PIPE.MA.BC) ? (PC[1] ? BUS_DI[15:0] : BUS_DI[31:16]) : SAVE_IR;
			if (ID_DECI.SLP || SLP) NEW_IR2 = 16'h0009;
			SAVE_ID_1.IR <= NEW_IR2;
			SAVE_ID_1.PC <= PC;
		end
		SAVE_ID.IR <= SAVE_ID_1.IR; SAVE_ID.PC <= SAVE_ID_1.PC;
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
			RES_EXP <= 1; INT_REQ_LATCH <= 0; INT_LVL_LATCH <= '0; ILI_EXP <= 0;
			RES_EXP_1 <= 1; INT_REQ_LATCH_1 <= 0; INT_LVL_LATCH_1 <= '0; ILI_EXP_1 <= 0;
		end
		else begin
			RES_EXP_1 <= RES_EXP; INT_REQ_LATCH_1 <= INT_REQ_LATCH; INT_LVL_LATCH_1 <= INT_LVL_LATCH; ILI_EXP_1 <= ILI_EXP;
			if (!RES_N) begin
				RES_EXP_1 <= 1;
				INT_REQ_LATCH_1 <= 0;
				INT_LVL_LATCH_1 <= '0;
				ILI_EXP_1 <= 0;
			end
			else if (EN) begin
				if (!ID_STALL) begin
					if (STATE == 3'd5 && RES_EXP) begin
						RES_EXP_1 <= 0;
					end

					if (INT_REQ && !INT_BLOCKED && !ID_DELAY_SLOT && !IFID_STALL && !INT_REQ_LATCH) begin
						INT_REQ_LATCH_1 <= 1;
						INT_LVL_LATCH_1 <= INT_LVL;
					end else if (STATE == 3'd7 && INT_REQ_LATCH) begin
						INT_REQ_LATCH_1 <= 0;
					end

					if (ID_DECI.ILI && !RES_EXP && !INT_EXP && !ILI_EXP) begin
						ILI_EXP_1 <= 1;
					end else if (STATE == 3'd6 && ILI_EXP) begin
						ILI_EXP_1 <= 0;
					end
				end
			end
			RES_EXP <= RES_EXP_1 | ~o_RES_N; INT_REQ_LATCH <= INT_REQ_LATCH_1 & o_RES_N; INT_LVL_LATCH <= o_RES_N ? INT_LVL_LATCH_1 : '0;
			ILI_EXP <= ILI_EXP_1 & o_RES_N;
		end
	end
	// ILSI: never reset in SH_core
	always @(posedge CLK) begin
		ILSI_1 <= ILSI;
		if (RST_N && RES_N && EN && !ID_STALL && ID_DECI.ILI && !RES_EXP && !INT_EXP && !ILI_EXP) ILSI_1 <= ID_DELAY_SLOT;
		ILSI <= ILSI_1;
	end

	wire [15:0] DEC_IR = RES_EXP || INT_EXP ? 16'h0000 :
								ID_DELAY_SLOT && !PIPE.EX.DI.BR.BD ? 16'h0009 :
								IFID_STALL ? PIPE.EX.IR : PIPE.ID.IR;

	assign BR_T = PIPE.EX.DI.CTRL.W && PIPE.EX.DI.CTRL.S == SR_ ? SR_NEW.T : SR.T;

	// Decoder ROM (SH_core's decrom), read every clock for the thread that executes in the next clock: its address
	// comes from that thread's registers (X_1) and its INT_REQ_NEXT; its last row's SEQ is the row of one clock ago.
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
	bit [4:0] SEQ_D;
	bit [9:0] DA;
	wire o_INT_BLOCKED = PIPE_1.EX.DI.IBI;
	wire o_ID_DELAY_SLOT = ~PIPE_1.EX.DI.BR.BI & (PIPE_1.EX.DI.BR.BT == CB | PIPE_1.EX.DI.BR.BT == UCB);
	always_comb begin
		bit [3:0] top, n, m, lo;
		bit       isLo, isHi, is04, isBr;
		bit [1:0] m2;
		bit [3:0] sub52;
		bit [9:0] key;
		bit [4:0] seq;

		top = PIPE_1.ID.IR[15:12]; n = PIPE_1.ID.IR[11:8]; m = PIPE_1.ID.IR[7:4]; lo = PIPE_1.ID.IR[3:0];
		isLo = (top == 4'h0) | (top == 4'h2) | (top == 4'h3) | (top == 4'h4) | (top == 4'h6);
		isHi = (top == 4'h8) | (top == 4'hC);
		is04 = (top == 4'h0) | (top == 4'h4);
		isBr = (top == 4'h8) | (top == 4'hA) | (top == 4'hB) | (top == 4'hC);
		m2 = (m[3] | m[2] | (m[1] & m[0])) ? 2'd3 : m[1:0];
		if (top == 4'h0 && (lo == 4'h8 || lo == 4'hB || (lo == 4'h9 && m2 != 2'd2)) && n != 4'h0) m2 = 2'd3;
		if (top == 4'h0 && lo == 4'h3 && o_ID_DELAY_SLOT) m2 = 2'd3;
		if (lo == 4'hB && o_ID_DELAY_SLOT && !m2[0]) m2 = 2'd3;
		sub52 = isHi ? n : isLo ? lo : 4'h0;
		key = {top, sub52, is04 ? m2 : {1'b0, isBr & o_ID_DELAY_SLOT}};

		seq = RES_EXP_1 ? 5'd1 : INT_REQ_LATCH_1 ? 5'd2 : ILI_EXP_1 ? (ILSI_1 ? 5'd4 : 5'd3) : SEQ_D;
		if (STATE_1 != 3'd0 || RES_EXP_1 || INT_REQ_LATCH_1)
			DA = {seq[4], 1'b1, seq[3], 1'b1, seq[2:0], STATE_1};
		else if (o_INT_REQ_NEXT && !o_INT_BLOCKED && !o_ID_DELAY_SLOT)
			DA = 10'h000;			//0000: interrupt taken
		else if (o_ID_DELAY_SLOT && !PIPE_1.EX.DI.BR.BD)
			DA = 10'h024;			//0009: killed slot
		else
			DA = key;
	end

	(* romstyle = "M10K" *) bit [79:0] DEC_ROM[1024];
	initial begin
		$readmemh("shdec_rom.hex", DEC_ROM);
	end
	always_ff @(posedge CLK) begin
		R <= DEC_ROM[DA];
		SEQ_D <= R.SEQ;
	end

	wire       DR_BC = (BR_T == ~DEC_IR[9]);
	wire [4:0] DR_RAN = R.RASEL ? {1'b0, DEC_IR[11:8]} : {R.RAC[1], {4{R.RAC[0]}}};
	wire [4:0] DR_RBN = R.RBSEL[0] ? {1'b0, DEC_IR[7:4]} : R.RBSEL[1] ? {1'b0, DEC_IR[11:8]} : {R.RBC[1], {4{R.RBC[0]}}};
	assign ID_DECI = DecInstr_t'({3'b000, R.RSB, R.RSC, R.PCM, R.BPWBA, R.BPLDA, R.BPMAB, R.IMMT,
	                              R.SA, R.SB, R.OP, R.CD, R.CMP, R.ADDS, R.WDS, R.SZ, R.MR, R.MW, R.DF,
	                              DR_RAN, R.RAR, R.RAW, DR_RBN, R.RBR, R.RBW, R.R0R, R.PCW | (R.CB0 & DR_BC),
	                              R.CW, R.CS, R.SRS, R.MACS, R.MACR, R.MACW, R.MACOP,
	                              R.BI, R.BT, R.BD, R.BCV, R.BSR, R.TAS, R.SLP, R.IBI, R.IID, R.LST | {2'b00, R.CB0 & DR_BC}, R.VECR, R.ILI});

	wire [ 2: 0] NEXT_STATE = STATE == ID_DECI.LST ? 3'd0 : STATE + 3'd1;
	always @(posedge CLK or negedge RST_N) begin
		bit BR_COND;

		if (!RST_N) begin
			PIPE.EX.IR <= '0; PIPE.EX.PC <= '0; PIPE.EX.DI <= DECI_RESET; PIPE.EX.RA <= '0; PIPE.EX.RB <= '0; PIPE.EX.R0 <= '0; PIPE.EX.BC <= 0;
			STATE <= '0; IFID_STALL <= 0; SLP <= 1;
			PIPE_1.EX.IR <= '0; PIPE_1.EX.PC <= '0; PIPE_1.EX.DI <= DECI_RESET; PIPE_1.EX.RA <= '0; PIPE_1.EX.RB <= '0; PIPE_1.EX.R0 <= '0; PIPE_1.EX.BC <= 0;
			STATE_1 <= '0; IFID_STALL_1 <= 0; SLP_1 <= 1;
		end
		else begin
			PIPE_1.EX.IR <= PIPE.EX.IR; PIPE_1.EX.PC <= PIPE.EX.PC; PIPE_1.EX.DI <= PIPE.EX.DI; PIPE_1.EX.RA <= PIPE.EX.RA;
			PIPE_1.EX.RB <= PIPE.EX.RB; PIPE_1.EX.R0 <= PIPE.EX.R0; PIPE_1.EX.BC <= PIPE.EX.BC;
			STATE_1 <= STATE; IFID_STALL_1 <= IFID_STALL; SLP_1 <= SLP;
			if (!RES_N) begin
				PIPE_1.EX.IR <= '0;
				PIPE_1.EX.PC <= '0;
				PIPE_1.EX.DI <= DECI_RESET;
				PIPE_1.EX.RA <= '0;
				PIPE_1.EX.RB <= '0;
				PIPE_1.EX.R0 <= '0;
				PIPE_1.EX.BC <= 0;
				STATE_1 <= '0;
				IFID_STALL_1 <= 0;
				SLP_1 <= 0;
			end
			else if (EN) begin
				BR_COND = ID_DECI.BR.BI & ((BR_T == ID_DECI.BR.BCV) | (ID_DECI.BR.BT == UCB));

				if (!ID_STALL) begin
					PIPE_1.EX.IR <= DEC_IR;
					PIPE_1.EX.PC <= PIPE.ID.PC;
					PIPE_1.EX.DI <= ID_DECI;
					PIPE_1.EX.RA <= REGS_RAQ;
					PIPE_1.EX.RB <= REGS_RBQ;
					PIPE_1.EX.R0 <= REGS_R0Q;
					PIPE_1.EX.BC <= BR_COND;
					STATE_1 <= NEXT_STATE;
					IFID_STALL_1 <= |NEXT_STATE;

					if (ID_DECI.SLP) SLP_1 <= 1;
					if (SLP && INT_REQ) SLP_1 <= 0;
				end
			end
			PIPE.EX.IR <= o_RES_N ? PIPE_1.EX.IR : '0; PIPE.EX.PC <= o_RES_N ? PIPE_1.EX.PC : '0;
			PIPE.EX.DI <= o_RES_N ? PIPE_1.EX.DI : DECI_RESET; PIPE.EX.RA <= o_RES_N ? PIPE_1.EX.RA : '0;
			PIPE.EX.RB <= o_RES_N ? PIPE_1.EX.RB : '0; PIPE.EX.R0 <= o_RES_N ? PIPE_1.EX.R0 : '0; PIPE.EX.BC <= PIPE_1.EX.BC & o_RES_N;
			STATE <= o_RES_N ? STATE_1 : '0; IFID_STALL <= IFID_STALL_1 & o_RES_N; SLP <= SLP_1 & o_RES_N;
		end
	end

	//**********************************************************
	//EX stage (SH_core's combinational code; the operands one clock early)
	//**********************************************************
	// Operands. SH_core computes REG_A / REG_B / REG_C and ALU_A / ALU_B in the EX clock from EX / MA / WB / WB2
	// state only (bypass network, operand selects): the long head of its EX -> ID / IF paths (ALU -> T -> branch
	// decode), which in this core are real one-clock paths (X -> X_1 in every clock). So the same code runs here one
	// clock early, on the state the next executing thread holds (X_1, which X takes at the end of this clock:
	// X <= o_RES_N ? X_1 : its reset value), and the result is registered (EXOP): in every clock EXOP holds SH_core's
	// values for X. Under the other thread's RES_N X takes the reset state (DECI_RESET, RA / RB / R0 = 0), whose
	// operands are all 0, as EXOP's (also under RST_N; the registers SH_core does not reset are not selected there).
	// The one input-dependent part, the vector number of the VECT immediate (NMI_N in the reset sequence, INT_VEC in
	// the interrupt one), is left out and ORed in in the EX clock (VECT_IN / VECT_SH, SH_core's placement).
	typedef struct packed {
		bit [31:0] REG_A, REG_B, ALU_A, ALU_B;
		bit        VA, VB;		//ALU_A / ALU_B is the VECT immediate
	} ExOp_t;
	ExOp_t EXOP_N, EXOP;
	always_comb begin
		bit [11: 0] ir_imm;
		bit [ 7: 0] vec;
		bit [31: 0] temp, IMM_VAL, SCR_VAL;
		bit [31: 0] BP_A, BP_B, BP_C;
		bit [31: 0] ra, rb, rc;
		bit BP_A_EXEX, BP_B_EXEX, BP_C_EXEX, BP_A_MAEX, BP_B_MAEX, BP_C_MAEX, BP_A_WBEXA, BP_A_WBEXB, BP_B_WBEXA,
		    BP_B_WBEXB, BP_C_WBEXA, BP_C_WBEXB, BP_A_MALD, BP_B_MALD, BP_C_MALD, BP_A_WBLD, BP_B_WBLD, BP_C_WBLD;

		//Bypassing datapath
		BP_A_EXEX = ((PIPE_1.EX.DI.RA.N == PIPE_1.MA.DI.RA.N) & PIPE_1.EX.DI.RA.R & PIPE_1.MA.DI.RA.W & !((PIPE_1.MA.DI.MEM.R & !PIPE_1.MA.DI.MAC.W) | (PIPE_1.MA.DI.MAC.R & !PIPE_1.MA.DI.MEM.W))) |
							  ((PIPE_1.EX.DI.RA.N == PIPE_1.MA.DI.RB.N) & PIPE_1.EX.DI.RA.R & PIPE_1.MA.DI.RB.W & (PIPE_1.MA.DI.RA.N != PIPE_1.MA.DI.RB.N | !PIPE_1.MA.DI.RA.W));
		BP_B_EXEX = ((PIPE_1.EX.DI.RB.N == PIPE_1.MA.DI.RA.N) & PIPE_1.EX.DI.RB.R & PIPE_1.MA.DI.RA.W & !((PIPE_1.MA.DI.MEM.R & !PIPE_1.MA.DI.MAC.W) | (PIPE_1.MA.DI.MAC.R & !PIPE_1.MA.DI.MEM.W))) |
							  ((PIPE_1.EX.DI.RB.N == PIPE_1.MA.DI.RB.N) & PIPE_1.EX.DI.RB.R & PIPE_1.MA.DI.RB.W & (PIPE_1.MA.DI.RA.N != PIPE_1.MA.DI.RB.N | !PIPE_1.MA.DI.RA.W));
		BP_C_EXEX = ((5'd0            == PIPE_1.MA.DI.RA.N) & PIPE_1.EX.DI.R0R  & PIPE_1.MA.DI.RA.W & !((PIPE_1.MA.DI.MEM.R & !PIPE_1.MA.DI.MAC.W) | (PIPE_1.MA.DI.MAC.R & !PIPE_1.MA.DI.MEM.W))) |
							  ((5'd0            == PIPE_1.MA.DI.RB.N) & PIPE_1.EX.DI.R0R  & PIPE_1.MA.DI.RB.W & (PIPE_1.MA.DI.RA.N != 5'd0            | !PIPE_1.MA.DI.RA.W));

		BP_A_MAEX = ((PIPE_1.EX.DI.RA.N == PIPE_1.WB.DI.RA.N) & PIPE_1.EX.DI.RA.R & PIPE_1.WB.DI.RA.W & !((PIPE_1.WB.DI.MEM.R & !PIPE_1.WB.DI.MAC.W) | (PIPE_1.WB.DI.MAC.R & !PIPE_1.WB.DI.MEM.W))) |
							  ((PIPE_1.EX.DI.RA.N == PIPE_1.WB.DI.RB.N) & PIPE_1.EX.DI.RA.R & PIPE_1.WB.DI.RB.W);
		BP_B_MAEX = ((PIPE_1.EX.DI.RB.N == PIPE_1.WB.DI.RA.N) & PIPE_1.EX.DI.RB.R & PIPE_1.WB.DI.RA.W & !((PIPE_1.WB.DI.MEM.R & !PIPE_1.WB.DI.MAC.W) | (PIPE_1.WB.DI.MAC.R & !PIPE_1.WB.DI.MEM.W))) |
							  ((PIPE_1.EX.DI.RB.N == PIPE_1.WB.DI.RB.N) & PIPE_1.EX.DI.RB.R & PIPE_1.WB.DI.RB.W);
		BP_C_MAEX = ((5'd0            == PIPE_1.WB.DI.RA.N) & PIPE_1.EX.DI.R0R  & PIPE_1.WB.DI.RA.W & !((PIPE_1.WB.DI.MEM.R & !PIPE_1.WB.DI.MAC.W) | (PIPE_1.WB.DI.MAC.R & !PIPE_1.WB.DI.MEM.W))) |
							  ((5'd0            == PIPE_1.WB.DI.RB.N) & PIPE_1.EX.DI.R0R  & PIPE_1.WB.DI.RB.W);

		BP_A_WBEXA = (PIPE_1.EX.DI.RA.N == PIPE_1.WB2.DI.RA.N) & PIPE_1.EX.DI.RA.R & PIPE_1.WB2.DI.RA.W;
		BP_A_WBEXB = (PIPE_1.EX.DI.RA.N == PIPE_1.WB2.DI.RB.N) & PIPE_1.EX.DI.RA.R & PIPE_1.WB2.DI.RB.W;
		BP_B_WBEXA = (PIPE_1.EX.DI.RB.N == PIPE_1.WB2.DI.RA.N) & PIPE_1.EX.DI.RB.R & PIPE_1.WB2.DI.RA.W;
		BP_B_WBEXB = (PIPE_1.EX.DI.RB.N == PIPE_1.WB2.DI.RB.N) & PIPE_1.EX.DI.RB.R & PIPE_1.WB2.DI.RB.W;
		BP_C_WBEXA = (5'd0            == PIPE_1.WB2.DI.RA.N) & PIPE_1.EX.DI.R0R  & PIPE_1.WB2.DI.RA.W;
		BP_C_WBEXB = (5'd0            == PIPE_1.WB2.DI.RB.N) & PIPE_1.EX.DI.R0R  & PIPE_1.WB2.DI.RB.W;

		BP_A_MALD = (PIPE_1.EX.DI.RA.N == PIPE_1.MA.DI.RA.N)  & PIPE_1.EX.DI.RA.R & PIPE_1.MA.DI.RA.W & ((PIPE_1.MA.DI.MEM.R & !PIPE_1.MA.DI.MAC.W) | (PIPE_1.MA.DI.MAC.R & !PIPE_1.MA.DI.MEM.W));
		BP_B_MALD = (PIPE_1.EX.DI.RB.N == PIPE_1.MA.DI.RA.N)  & PIPE_1.EX.DI.RB.R & PIPE_1.MA.DI.RA.W & ((PIPE_1.MA.DI.MEM.R & !PIPE_1.MA.DI.MAC.W) | (PIPE_1.MA.DI.MAC.R & !PIPE_1.MA.DI.MEM.W));
		BP_C_MALD = (5'd0            == PIPE_1.MA.DI.RA.N)  & PIPE_1.EX.DI.R0R  & PIPE_1.MA.DI.RA.W & ((PIPE_1.MA.DI.MEM.R & !PIPE_1.MA.DI.MAC.W) | (PIPE_1.MA.DI.MAC.R & !PIPE_1.MA.DI.MEM.W));

		BP_A_WBLD = (PIPE_1.EX.DI.RA.N == PIPE_1.WB.DI.RA.N)  & PIPE_1.EX.DI.RA.R & PIPE_1.WB.DI.RA.W & ((PIPE_1.WB.DI.MEM.R & !PIPE_1.WB.DI.MAC.W) | (PIPE_1.WB.DI.MAC.R & !PIPE_1.WB.DI.MEM.W));
		BP_B_WBLD = (PIPE_1.EX.DI.RB.N == PIPE_1.WB.DI.RA.N)  & PIPE_1.EX.DI.RB.R & PIPE_1.WB.DI.RA.W & ((PIPE_1.WB.DI.MEM.R & !PIPE_1.WB.DI.MAC.W) | (PIPE_1.WB.DI.MAC.R & !PIPE_1.WB.DI.MEM.W));
		BP_C_WBLD = (5'd0            == PIPE_1.WB.DI.RA.N)  & PIPE_1.EX.DI.R0R  & PIPE_1.WB.DI.RA.W & ((PIPE_1.WB.DI.MEM.R & !PIPE_1.WB.DI.MAC.W) | (PIPE_1.WB.DI.MAC.R & !PIPE_1.WB.DI.MEM.W));

		ir_imm = PIPE_1.EX.IR[11:0];
		vec = RES_EXP_1 || INT_REQ_LATCH_1 ? 8'h00 :		//the inputs' part: VECT_IN, in the EX clock
				ILI_EXP_1     ? 8'h04 | {6'b000000,ILSI_1,1'b0} :
				                PIPE_1.EX.IR[7:0];

		case (PIPE_1.EX.DI.IMMT)
			ZIMM4:  temp = {{28{1'b0}},      ir_imm[ 3:0]};
			SIMM8:  temp = {{24{ir_imm[ 7]}},ir_imm[ 7:0]};
			ZIMM8:  temp = {{24{1'b0}},      ir_imm[ 7:0]};
			SIMM12: temp = {{20{ir_imm[11]}},ir_imm[11:0]};
			ZERO:   temp = 32'h00000000;
			ONE:    temp = 32'h00000001;
			VECT:   temp = {{24{1'b0}},      vec};
			default: temp = 32'h00000000;
		endcase

		if (PIPE_1.EX.DI.BR.BI) begin
			IMM_VAL = {temp[30:0],1'b0};
		end else begin
			case (PIPE_1.EX.DI.MEM.SZ)
				2'b00:   IMM_VAL = temp;
				2'b01:   IMM_VAL = {temp[30:0],1'b0};
				default: IMM_VAL = {temp[29:0],2'b00};
			endcase
		end

		case (PIPE_1.EX.DI.CTRL.S)
			SR_:  SCR_VAL = SR_1 & 32'h000003F3;
			GBR_: SCR_VAL = GBR_1;
			VBR_: SCR_VAL = VBR_1;
			default: SCR_VAL = 32'h00000000;
		endcase

		if (BP_A_EXEX) begin
			BP_A = PIPE_1.MA.RES;
		end
		else if (BP_A_MALD) begin
			BP_A = RD_SAVE_1;
		end
		else if (BP_A_WBLD || PIPE_1.EX.DI.DP.BPLDA) begin
			BP_A = PIPE_1.WB.RD;
		end
		else if (BP_A_MAEX) begin
			BP_A = PIPE_1.WB.RES;
		end
		else if (BP_A_WBEXA || PIPE_1.EX.DI.DP.BPWBA) begin
			BP_A = PIPE_1.WB2.RESA;
		end
		else if (BP_A_WBEXB) begin
			BP_A = PIPE_1.WB2.RESB;
		end
		else begin
			BP_A = PIPE_1.EX.RA;
		end

		ra = BP_A;

		if (BP_B_EXEX || PIPE_1.EX.DI.DP.BPMAB) begin
			BP_B = PIPE_1.MA.RES;
		end
		else if (BP_B_MALD) begin
			BP_B = RD_SAVE_1;
		end
		else if (BP_B_WBLD) begin
			BP_B = PIPE_1.WB.RD;
		end
		else if (BP_B_MAEX) begin
			BP_B = PIPE_1.WB.RES;
		end
		else if (BP_B_WBEXA) begin
			BP_B = PIPE_1.WB2.RESA;
		end
		else if (BP_B_WBEXB) begin
			BP_B = PIPE_1.WB2.RESB;
		end
		else begin
			BP_B = PIPE_1.EX.RB;
		end

		case (PIPE_1.EX.DI.DP.RSB)
			GRX: rb = BP_B;
			BPC: rb = {PC_1[31:2],PC_1[1:0] & {2{~PIPE_1.EX.DI.DP.PCM}}};
			TPC: rb = SAVE_ID_1.PC;
			IPC: rb = PIPE_1.EX.PC;
			SCR: rb = SCR_VAL;
			default: rb = 32'h0;
		endcase

		if (BP_C_EXEX) begin
			BP_C = PIPE_1.MA.RES;
		end
		else if (BP_C_MALD) begin
			BP_C = RD_SAVE_1;
		end
		else if (BP_C_WBLD) begin
			BP_C = PIPE_1.WB.RD;
		end
		else if (BP_C_MAEX) begin
			BP_C = PIPE_1.WB.RES;
		end
		else if (BP_C_WBEXA) begin
			BP_C = PIPE_1.WB2.RESA;
		end
		else if (BP_C_WBEXB) begin
			BP_C = PIPE_1.WB2.RESB;
		end
		else begin
			BP_C = PIPE_1.EX.R0;
		end

		case (PIPE_1.EX.DI.DP.RSC)
			1'b0: rc = BP_C;
			1'b1: rc = IMM_VAL;
		endcase

		EXOP_N.REG_A = ra;
		EXOP_N.REG_B = rb;
		EXOP_N.ALU_A = PIPE_1.EX.DI.ALU.SA ? rc : ra;
		EXOP_N.ALU_B = PIPE_1.EX.DI.ALU.SB ? rc : rb;
		EXOP_N.VA = PIPE_1.EX.DI.ALU.SA & PIPE_1.EX.DI.DP.RSC & (PIPE_1.EX.DI.IMMT == VECT);
		EXOP_N.VB = PIPE_1.EX.DI.ALU.SB & PIPE_1.EX.DI.DP.RSC & (PIPE_1.EX.DI.IMMT == VECT);
		if (!o_RES_N) EXOP_N = '0;
	end
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) EXOP <= '0;
		else EXOP <= EXOP_N;
	end

	wire [ 7: 0] VECT_IN = RES_EXP ? {6'b000000,~NMI_N,1'b0} : INT_REQ_LATCH ? INT_VEC : 8'h00;
	wire [ 9: 0] VECT_SH = PIPE.EX.DI.BR.BI || PIPE.EX.DI.MEM.SZ == 2'b01 ? {1'b0,VECT_IN,1'b0} :
	                       PIPE.EX.DI.MEM.SZ == 2'b00 ? {2'b00,VECT_IN} : {VECT_IN,2'b00};
	wire [31: 0] REG_A = EXOP.REG_A;
	wire [31: 0] REG_B = EXOP.REG_B;

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

		ALU_A = EXOP.ALU_A | {22'h000000, VECT_SH & {10{EXOP.VA}}};
		ALU_B = EXOP.ALU_B | {22'h000000, VECT_SH & {10{EXOP.VB}}};

		adder_a = PIPE.EX.DI.ALU.OP == DIV ? {ALU_A[30:0],SR.T} : ALU_A;
		adder_code = PIPE.EX.DI.ALU.OP == DIV ? {3'b000,(SR.M ~^ SR.Q)} : PIPE.EX.DI.ALU.CD;
		adder_cmp = PIPE.EX.DI.ALU.CMP;
		{ADDER_C,ADDER_RES} = Adder(adder_a,ALU_B,SR.T,adder_code);
		ADDER_V = ~((ALU_A[31] ^ ALU_B[31]) ^ adder_code[0]) & (ALU_A[31] ^ ADDER_RES[31]);
		ge_hs = (~ALU_A[31] & ~ALU_B[31] & ~ADDER_RES[31]) | (ALU_A[31] & ALU_B[31] & ~ADDER_RES[31]) | ((adder_cmp[0] ^ ALU_A[31]) & (~adder_cmp[0] ^ ALU_B[31]));
		eq = ~|ADDER_RES[31:0];

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
			PIPE.MA.IR <= '0; PIPE.MA.DI <= DECI_RESET; PIPE.MA.BC <= 0; PIPE.MA.RES <= '0; PIPE.MA.ADDR <= '0; PIPE.MA.WD <= '0;
			PIPE_1.MA.IR <= '0; PIPE_1.MA.DI <= DECI_RESET; PIPE_1.MA.BC <= 0; PIPE_1.MA.RES <= '0; PIPE_1.MA.ADDR <= '0; PIPE_1.MA.WD <= '0;
		end
		else begin
			PIPE_1.MA.IR <= PIPE.MA.IR; PIPE_1.MA.DI <= PIPE.MA.DI; PIPE_1.MA.BC <= PIPE.MA.BC; PIPE_1.MA.RES <= PIPE.MA.RES;
			PIPE_1.MA.ADDR <= PIPE.MA.ADDR; PIPE_1.MA.WD <= PIPE.MA.WD;
			if (!RES_N) begin
				PIPE_1.MA.IR <= '0;
				PIPE_1.MA.DI <= DECI_RESET;
				PIPE_1.MA.BC <= 0;
				PIPE_1.MA.RES <= '0;
				PIPE_1.MA.ADDR <= '0;
				PIPE_1.MA.WD <= '0;
			end
			else if (EN) begin
				if (!EX_STALL) begin
					PIPE_1.MA.IR <= PIPE.EX.IR;
					PIPE_1.MA.DI <= PIPE.EX.DI;
					PIPE_1.MA.BC <= PIPE.EX.BC;
					PIPE_1.MA.RES <= PIPE.EX.DI.BR.BI ? REG_B : ALU_RES;
					PIPE_1.MA.ADDR <= MA_ADDR;
					PIPE_1.MA.WD <= MA_WD;
				end
			end
			PIPE.MA.IR <= o_RES_N ? PIPE_1.MA.IR : '0; PIPE.MA.DI <= o_RES_N ? PIPE_1.MA.DI : DECI_RESET; PIPE.MA.BC <= PIPE_1.MA.BC & o_RES_N;
			PIPE.MA.RES <= o_RES_N ? PIPE_1.MA.RES : '0; PIPE.MA.ADDR <= o_RES_N ? PIPE_1.MA.ADDR : '0; PIPE.MA.WD <= o_RES_N ? PIPE_1.MA.WD : '0;
		end
	end
	// PIPE.MA.PC: reset by RES_N only in SH_core (it holds while RST_N is low): the chain keeps rotating then
	always @(posedge CLK) begin
		PIPE_1.MA.PC <= PIPE.MA.PC;
		if (RST_N) begin
			if (!RES_N) PIPE_1.MA.PC <= '0;
			else if (EN && !EX_STALL) PIPE_1.MA.PC <= PIPE.EX.PC;
		end
		PIPE.MA.PC <= (RST_N && !o_RES_N) ? '0 : PIPE_1.MA.PC;
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
			SR <= SR_RESET; GBR <= '0; VBR <= '0;
			SR_1 <= SR_RESET; GBR_1 <= '0; VBR_1 <= '0;
		end
		else begin
			SR_1 <= SR; GBR_1 <= GBR; VBR_1 <= VBR;
			if (!RES_N) begin
				SR_1 <= SR_RESET;
				GBR_1 <= '0;
				VBR_1 <= '0;
			end
			else if (EN) begin
				if (!EX_STALL) begin
					if (PIPE.EX.DI.CTRL.W) begin
						case (PIPE.EX.DI.CTRL.S)
							SR_:  SR_1 <= SR_NEW & 32'h000003F3;
							GBR_: GBR_1 <= ALU_RES;
							VBR_: VBR_1 <= ALU_RES;
							default:;
						endcase
					end
				end
			end
			SR <= o_RES_N ? SR_1 : SR_RESET; GBR <= o_RES_N ? GBR_1 : '0; VBR <= o_RES_N ? VBR_1 : '0;
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
			PIPE.WB.IR <= '0; PIPE.WB.DI <= DECI_RESET; PIPE.WB.RES <= '0; PIPE.WB.RD <= '0;
			PIPE_1.WB.IR <= '0; PIPE_1.WB.DI <= DECI_RESET; PIPE_1.WB.RES <= '0; PIPE_1.WB.RD <= '0;
		end
		else begin
			PIPE_1.WB.IR <= PIPE.WB.IR; PIPE_1.WB.DI <= PIPE.WB.DI; PIPE_1.WB.RES <= PIPE.WB.RES; PIPE_1.WB.RD <= PIPE.WB.RD;
			if (!RES_N) begin
				PIPE_1.WB.IR <= '0;
				PIPE_1.WB.DI <= DECI_RESET;
				PIPE_1.WB.RES <= '0;
				PIPE_1.WB.RD <= '0;
			end
			else if (EN) begin
				if (!MA_STALL && !INST_SPLIT) begin
					PIPE_1.WB.IR <= PIPE.MA.IR;
					PIPE_1.WB.DI <= PIPE.MA.DI;
					PIPE_1.WB.RES <= PIPE.MA.RES;
					PIPE_1.WB.RD <= MA_RDATA;
				end
				else if (!MA_STALL && INST_SPLIT) begin
				end
				else if (!(IF_ACTIVE & BUS_WAIT) && MAWB_STALL) begin
					PIPE_1.WB.IR <= PIPE.MA.IR;
					PIPE_1.WB.DI <= PIPE.MA.DI;
					PIPE_1.WB.RES <= PIPE.MA.RES;
					PIPE_1.WB.RD <= RD_SAVE;
				end
			end
			PIPE.WB.IR <= o_RES_N ? PIPE_1.WB.IR : '0; PIPE.WB.DI <= o_RES_N ? PIPE_1.WB.DI : DECI_RESET;
			PIPE.WB.RES <= o_RES_N ? PIPE_1.WB.RES : '0; PIPE.WB.RD <= o_RES_N ? PIPE_1.WB.RD : '0;
		end
	end
	// PIPE.WB.PC, RD_SAVE: never reset in SH_core
	always @(posedge CLK) begin
		PIPE_1.WB.PC <= PIPE.WB.PC; RD_SAVE_1 <= RD_SAVE;
		if (RST_N && RES_N && EN) begin
			if (!MA_STALL && !INST_SPLIT) begin
				PIPE_1.WB.PC <= PIPE.MA.PC;
				RD_SAVE_1 <= MA_RDATA;
			end
			else if (!MA_STALL && INST_SPLIT) begin
				RD_SAVE_1 <= MA_RDATA;
			end
			else if (!(IF_ACTIVE & BUS_WAIT) && MAWB_STALL) begin
				PIPE_1.WB.PC <= PIPE.MA.PC;
			end
		end
		PIPE.WB.PC <= PIPE_1.WB.PC; RD_SAVE <= RD_SAVE_1;
	end

	//**********************************************************
	//WB stage
	//**********************************************************
	wire WB_STALL = BUS_STALL | MAWB_STALL;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			PIPE.WB2.IR <= '0; PIPE.WB2.DI <= DECI_RESET; PIPE.WB2.RESA <= '0; PIPE.WB2.RESB <= '0;
			PIPE_1.WB2.IR <= '0; PIPE_1.WB2.DI <= DECI_RESET; PIPE_1.WB2.RESA <= '0; PIPE_1.WB2.RESB <= '0;
		end
		else begin
			PIPE_1.WB2.IR <= PIPE.WB2.IR; PIPE_1.WB2.DI <= PIPE.WB2.DI; PIPE_1.WB2.RESA <= PIPE.WB2.RESA; PIPE_1.WB2.RESB <= PIPE.WB2.RESB;
			if (!RES_N) begin
				PIPE_1.WB2.IR <= '0;
				PIPE_1.WB2.DI <= DECI_RESET;
				PIPE_1.WB2.RESA <= '0;
				PIPE_1.WB2.RESB <= '0;
			end
			else if (EN) begin
				if (!WB_STALL && !INST_SPLIT) begin
					PIPE_1.WB2.IR <= PIPE.WB.IR;
					PIPE_1.WB2.DI <= PIPE.WB.DI;
					PIPE_1.WB2.RESA <= (PIPE.WB.DI.MEM.R && !PIPE.WB.DI.MAC.W) || (PIPE.WB.DI.MAC.R && !PIPE.WB.DI.MEM.W) ? PIPE.WB.RD : PIPE.WB.RES;
					PIPE_1.WB2.RESB <= PIPE.WB.RES;
				end
				else if (!(IF_ACTIVE & BUS_WAIT) && MAWB_STALL) begin
					PIPE_1.WB2.IR <= PIPE.WB.IR;
					PIPE_1.WB2.DI <= PIPE.WB.DI;
					PIPE_1.WB2.RESA <= (PIPE.WB.DI.MEM.R && !PIPE.WB.DI.MAC.W) || (PIPE.WB.DI.MAC.R && !PIPE.WB.DI.MEM.W) ? PIPE.WB.RD : PIPE.WB.RES;
					PIPE_1.WB2.RESB <= PIPE.WB.RES;
				end
			end
			PIPE.WB2.IR <= o_RES_N ? PIPE_1.WB2.IR : '0; PIPE.WB2.DI <= o_RES_N ? PIPE_1.WB2.DI : DECI_RESET;
			PIPE.WB2.RESA <= o_RES_N ? PIPE_1.WB2.RESA : '0; PIPE.WB2.RESB <= o_RES_N ? PIPE_1.WB2.RESB : '0;
		end
	end

	assign REGS_WAN = PIPE.WB.DI.RA.N;
	assign REGS_WAD = (PIPE.WB.DI.MEM.R && !PIPE.WB.DI.MAC.W) || (PIPE.WB.DI.MAC.R && !PIPE.WB.DI.MEM.W) ? PIPE.WB.RD : PIPE.WB.RES;
	assign REGS_WAE = PIPE.WB.DI.RA.W & !WB_STALL;

	assign REGS_WBN = PIPE.WB.DI.RB.N;
	assign REGS_WBD = PIPE.WB.RES;
	assign REGS_WBE = PIPE.WB.DI.RB.W & (!PIPE.WB.DI.RA.W | PIPE.WB.DI.RA.N != PIPE.WB.DI.RB.N) & !WB_STALL;

	//**********************************************************
	//Ports: once for the executing thread (X), once for the other one (X_1)
	//**********************************************************
	function automatic bit [35:0] WData(input bit [31:0] wd, input bit [1:0] sz, input bit [1:0] a);	//{BA, WDATA}
		bit [31:0] d;
		bit  [3:0] ba;
		case (sz)
			2'b00:   d = {wd[7:0],wd[7:0],wd[7:0],wd[7:0]};
			2'b01:   d = {wd[15:0],wd[15:0]};
			default: d = wd;
		endcase
		case (sz)
			2'b00:   ba = 4'b0001 << ~a[1:0];
			2'b01:   ba = 4'b0011 << {~a[1],1'b0};
			default: ba = 4'b1111;
		endcase
		return {ba, d};
	endfunction

	// executing thread
	wire [35:0] e_WBA = WData(PIPE.MA.WD, PIPE.MA.DI.MEM.SZ, PIPE.MA.ADDR[1:0]);
	wire        MA_ACTIVE_NEXT = !RES_N ? 1'b0 :
	                             !EN ? MA_ACTIVE :
	                             (PIPE.EX.DI.MEM.R || PIPE.EX.DI.MEM.W || PIPE.EX.DI.MAC.R || PIPE.EX.DI.MAC.W) && !INST_SPLIT &&
	                             (!IF_ACTIVE || !BUS_WAIT) && !(VECT_ACTIVE && VECT_WAIT) ? 1'b1 :
	                             !BUS_WAIT && MA_ACTIVE ? 1'b0 : MA_ACTIVE;
	wire [31:0] PC_NEXT = !RES_N ? 32'h00000000 :
	                      !EN ? PC :
	                      PIPE.EX.DI.PCW && !EX_STALL ? ALU_RES :
	                      !PC_STALL && !ID_DECI.SLP && !SLP ? PC + 32'd2 : PC;
	wire [31:0] MA_ADDR_NEXT = !RES_N ? 32'h00000000 : EN && !EX_STALL ? MA_ADDR : PIPE.MA.ADDR;
	wire [119:0] e_CO = {MA_ACTIVE ? PIPE.MA.ADDR : (PC & 32'hFFFFFFFC),                                   //BUS_A
	                     e_WBA[31:0],                                                                     //BUS_DO
	                     PIPE.MA.DI.MEM.W & MA_ACTIVE,                                                    //BUS_WR
	                     e_WBA[35:32] | {4{IF_ACTIVE & ~INST_SPLIT & ~IFID_STALL}},                        //BUS_BA
	                     ((PIPE.MA.DI.MEM.R | PIPE.MA.DI.MEM.W) & MA_ACTIVE & ~MAWB_STALL) | (IF_ACTIVE & ~INST_SPLIT & ~IFID_STALL),	//BUS_REQ
	                     ~(PIPE.MA.DI.MEM.DF & MA_ACTIVE & ~MAWB_STALL),                                  //BUS_ID
	                     PIPE.MA.DI.TAS & MA_ACTIVE & ~MAWB_STALL,                                        //BUS_TAS
	                     !RST_N ? 32'h00000000 : MA_ACTIVE_NEXT ? MA_ADDR_NEXT : (PC_NEXT & 32'hFFFFFFFC), //BUS_A_NEXT
	                     PIPE.MA.DI.MAC.S & {2{(MA_ACTIVE & ~MAWB_STALL)}},                               //MAC_SEL
	                     PIPE.MA.DI.MAC.OP & {4{(MA_ACTIVE & ~MAWB_STALL)}},                              //MAC_OP
	                     SR.S,                                                                            //MAC_S
	                     |PIPE.MA.DI.MAC.S & PIPE.MA.DI.MAC.W & MA_ACTIVE & ~MA_STALL,                     //MAC_WE
	                     SR.I,                                                                            //INT_MASK
	                     PIPE.MA.DI.VECR & ~MA_STALL,                                                     //INT_ACK
	                     INT_REQ & ~INT_REQ_LATCH & ~INT_BLOCKED & ~ID_DELAY_SLOT & ~IFID_STALL & ~ID_STALL,	//INT_ACP
	                     VECT_ACTIVE,                                                                     //VECT_REQ
	                     SLP};                                                                            //SLEEP

	// the other thread (its state does not change in this clock: BUS_A_NEXT = BUS_A, or 0 in reset)
	wire        o_BUS_STALL = (MA_ACTIVE_1 & o_BUS_WAIT) | (IF_ACTIVE_1 & o_BUS_WAIT) | (VECT_ACTIVE_1 & o_VECT_WAIT);
	wire        o_MA_STALL = o_BUS_STALL | MAWB_STALL_1;
	wire        o_ID_STALL = o_BUS_STALL | INST_SPLIT_1;
	wire [35:0] o_WBA = WData(PIPE_1.MA.WD, PIPE_1.MA.DI.MEM.SZ, PIPE_1.MA.ADDR[1:0]);
	wire [31:0] o_BUS_A = MA_ACTIVE_1 ? PIPE_1.MA.ADDR : (PC_1 & 32'hFFFFFFFC);
	wire [119:0] o_CO = {o_BUS_A,                                                                         //BUS_A
	                     o_WBA[31:0],                                                                     //BUS_DO
	                     PIPE_1.MA.DI.MEM.W & MA_ACTIVE_1,                                                //BUS_WR
	                     o_WBA[35:32] | {4{IF_ACTIVE_1 & ~INST_SPLIT_1 & ~IFID_STALL_1}},                  //BUS_BA
	                     ((PIPE_1.MA.DI.MEM.R | PIPE_1.MA.DI.MEM.W) & MA_ACTIVE_1 & ~MAWB_STALL_1) | (IF_ACTIVE_1 & ~INST_SPLIT_1 & ~IFID_STALL_1),	//BUS_REQ
	                     ~(PIPE_1.MA.DI.MEM.DF & MA_ACTIVE_1 & ~MAWB_STALL_1),                            //BUS_ID
	                     PIPE_1.MA.DI.TAS & MA_ACTIVE_1 & ~MAWB_STALL_1,                                  //BUS_TAS
	                     !RST_N || !o_RES_N ? 32'h00000000 : o_BUS_A,                                     //BUS_A_NEXT
	                     PIPE_1.MA.DI.MAC.S & {2{(MA_ACTIVE_1 & ~MAWB_STALL_1)}},                         //MAC_SEL
	                     PIPE_1.MA.DI.MAC.OP & {4{(MA_ACTIVE_1 & ~MAWB_STALL_1)}},                        //MAC_OP
	                     SR_1.S,                                                                          //MAC_S
	                     |PIPE_1.MA.DI.MAC.S & PIPE_1.MA.DI.MAC.W & MA_ACTIVE_1 & ~o_MA_STALL,             //MAC_WE
	                     SR_1.I,                                                                          //INT_MASK
	                     PIPE_1.MA.DI.VECR & ~o_MA_STALL,                                                 //INT_ACK
	                     o_INT_REQ & ~INT_REQ_LATCH_1 & ~o_INT_BLOCKED & ~o_ID_DELAY_SLOT & ~IFID_STALL_1 & ~o_ID_STALL,	//INT_ACP
	                     VECT_ACTIVE_1,                                                                   //VECT_REQ
	                     SLP_1};                                                                          //SLEEP

	assign CO0 = PH ? e_CO : o_CO;
	assign CO1 = PH ? o_CO : e_CO;

	//Debug (SH_core's DBG_REGQ and DBG_BREAK, per thread; see the header)
`ifdef DEBUG
	function automatic bit [31:0] DbgRegQ(input bit [4:0] n, input bit [31:0] raq, input SR_t sr, input bit [31:0] gbr,
	                                      input bit [31:0] vbr, input bit [31:0] wbpc);
		return n <= 5'h10 ? raq : n == 5'h11 ? 32'(sr) : n == 5'h12 ? gbr : n == 5'h13 ? vbr : n == 5'h14 ? wbpc : '0;
	endfunction
	assign DBG_REGQ0 = PH ? DbgRegQ(DBG_REGN0, RAQ0, SR, GBR, VBR, PIPE.WB.PC) : DbgRegQ(DBG_REGN0, RAQ0, SR_1, GBR_1, VBR_1, PIPE_1.WB.PC);
	assign DBG_REGQ1 = PH ? DbgRegQ(DBG_REGN1, RAQ1, SR_1, GBR_1, VBR_1, PIPE_1.WB.PC) : DbgRegQ(DBG_REGN1, RAQ1, SR, GBR, VBR, PIPE.WB.PC);
	assign DBG_BREAK0 = 0;
	assign DBG_BREAK1 = 0;
`endif

endmodule
`endif

`ifdef CUT_SSH_WDT
`define U3_ANY
`elsif CUT_SSH_FRT_OC
`define U3_ANY
`elsif CUT_SSH_FRT_FICR
`define U3_ANY
`elsif CUT_SSH_DMAC1
`define U3_ANY
`elsif CUT_SSH_DMAC_MODES
`define U3_ANY
`elsif CUT_SSH_DIVU_OVF
`define U3_ANY
`elsif CUT_SSH_VECMD
`define U3_ANY
`elsif CUT_SSH_SBY
`define U3_ANY
`elsif CUT_SSH_CACHE_AARD
`define U3_ANY
`endif
`ifdef CUT_SSH_FRT_OC
`define U3_FRT
`elsif CUT_SSH_FRT_FICR
`define U3_FRT
`endif
`ifdef CUT_SSH_DMAC1
`define U3_DMAC
`elsif CUT_SSH_DMAC_MODES
`define U3_DMAC
`endif
`ifdef CUT_SSH_SBY
`define U3_SBY
`elsif CUT_SSH_WDT
`define U3_SBY
`endif
`ifdef CUT_SSH_VECMD
`define U3_INTC
`elsif CUT_SSH_WDT
`define U3_INTC
`elsif CUT_SSH_DMAC_MODES
`define U3_INTC
`elsif CUT_SSH_DIVU_OVF
`define U3_INTC
`elsif CUT_SSH_FRT_OC
`define U3_INTC
`endif
`ifdef CUT_MSH_DIVU_OVF
`define U4_ANY
`elsif CUT_MSH_DMAC_DREQ_IE
`define U4_ANY
`elsif CUT_MSH_WDT_RST
`define U4_ANY
`elsif CUT_MSH_CACHE_TW
`define U4_ANY
`elsif CUT_MSH_FRT_FICR
`define U4_ANY
`endif
`ifdef CUT_MSH_DIVU_OVF
`define U4_INTC
`elsif CUT_MSH_DMAC_DREQ_IE
`define U4_INTC
`endif
`ifdef CUT_MSH_FRT_FICR
// U4: the master's FICR cut is U3's (frt below)
`ifndef U3_FRT
`define U3_FRT
`endif
`endif
`ifdef CUT_MSH_DMAC_DREQ_IE
// U4: the master's DREQ / IE cut is built on U3's DMAC code (dmac below)
`ifndef U3_DMAC
`define U3_DMAC
`endif
`endif
`ifdef U4_INTC
// U4: the master's don't-care codes extend U3's INTC decode (intc below)
`ifndef U3_INTC
`define U3_INTC
`endif
`endif
`ifdef CUT_MSH_BSC_FIX
`define U5_ANY
`elsif CUT_MSH_BSC_MCR
`define U5_ANY
`elsif CUT_MSH_BSC_RTC
`define U5_ANY
`elsif CUT_SSH_BSC_FIX
`define U5_ANY
`elsif CUT_SSH_BSC_MCR
`define U5_ANY
`elsif CUT_SSH_BSC_RTC
`define U5_ANY
`endif
module SH7604 
`ifdef U5_ANY
#(parameter bit UBC_DISABLE=0, bit SCI_DISABLE=0, bit WDT_DISABLE=0, bit [3:0] BUS_AREA_TIMIMG=0, bit BUS_SIZE_BYTE_DISABLE=0, bit BUS_SIZE_WORD_DISABLE=0,
  // U3: cuts of slave features no game used. rtl/Saturn/Saturn.sv sets them on the slave (SSH) only, one per CUT_SSH_*
  // macro; 0 (the default) keeps the feature. What each cut does: the U3 comments in the module files.
  bit CUT_WDT=0, bit CUT_FRT_OC=0, bit CUT_FRT_FICR=0, bit CUT_DMAC1=0, bit CUT_DMAC_MODES=0, bit CUT_DIVU_OVF=0,
  bit CUT_VECMD=0, bit CUT_SBY=0, bit CUT_CACHE_AARD=0,
  // U4: cuts of master features no game (nor the BIOS) used. Saturn.sv sets them on the master (MSH) only, one per
  // CUT_MSH_* macro: CUT_DIVU_OVF and CUT_FRT_FICR above (the same cuts as the slave's) and the three below; 0 (the
  // default) keeps the feature. What each cut does: the U4 comments in the module files.
  bit CUT_DMAC_DREQ_IE=0, bit CUT_WDT_RST=0, bit CUT_CACHE_TW=0,
  // U5: fixed bus-state-controller registers. Saturn.sv sets them per CPU (CUT_MSH_BSC_* on MSH, CUT_SSH_BSC_* on SSH,
  // one per register group: FIX = BCR1 / BCR2 / WCR, MCR, RTC = RTCSR / RTCNT / RTCOR) with the values that CPU writes;
  // 0 (the default) keeps the registers writable. What a fixed register does: the U5 comment in BSC.sv.
  bit CUT_BSC_FIX=0, bit CUT_BSC_MCR=0, bit CUT_BSC_RTC=0,
  bit [15:0] BSC_BCR1=16'h0000, bit [15:0] BSC_BCR2=16'h0000, bit [15:0] BSC_WCR=16'h0000, bit [15:0] BSC_MCR=16'h0000,
  bit [15:0] BSC_MCR_VAR=16'h0000, bit [15:0] BSC_RTCSR=16'h0000, bit [7:0] BSC_RTCOR=8'h00)
`else
`ifdef U4_ANY
#(parameter bit UBC_DISABLE=0, bit SCI_DISABLE=0, bit WDT_DISABLE=0, bit [3:0] BUS_AREA_TIMIMG=0, bit BUS_SIZE_BYTE_DISABLE=0, bit BUS_SIZE_WORD_DISABLE=0,
  // U3: cuts of slave features no game used. rtl/Saturn/Saturn.sv sets them on the slave (SSH) only, one per CUT_SSH_*
  // macro; 0 (the default) keeps the feature. What each cut does: the U3 comments in the module files.
  bit CUT_WDT=0, bit CUT_FRT_OC=0, bit CUT_FRT_FICR=0, bit CUT_DMAC1=0, bit CUT_DMAC_MODES=0, bit CUT_DIVU_OVF=0,
  bit CUT_VECMD=0, bit CUT_SBY=0, bit CUT_CACHE_AARD=0,
  // U4: cuts of master features no game (nor the BIOS) used. Saturn.sv sets them on the master (MSH) only, one per
  // CUT_MSH_* macro: CUT_DIVU_OVF and CUT_FRT_FICR above (the same cuts as the slave's) and the three below; 0 (the
  // default, the slave) keeps the feature. What each cut does: the U4 comments in the module files.
  bit CUT_DMAC_DREQ_IE=0, bit CUT_WDT_RST=0, bit CUT_CACHE_TW=0)
`else
`ifdef U3_ANY
#(parameter bit UBC_DISABLE=0, bit SCI_DISABLE=0, bit WDT_DISABLE=0, bit [3:0] BUS_AREA_TIMIMG=0, bit BUS_SIZE_BYTE_DISABLE=0, bit BUS_SIZE_WORD_DISABLE=0,
  // U3: cuts of slave features no game used. rtl/Saturn/Saturn.sv sets them on the slave (SSH) only, one per CUT_SSH_*
  // macro; 0 (the default, the master) keeps the feature. What each cut does: the U3 comments in the module files.
  bit CUT_WDT=0, bit CUT_FRT_OC=0, bit CUT_FRT_FICR=0, bit CUT_DMAC1=0, bit CUT_DMAC_MODES=0, bit CUT_DIVU_OVF=0,
  bit CUT_VECMD=0, bit CUT_SBY=0, bit CUT_CACHE_AARD=0)
`else
#(parameter bit UBC_DISABLE=0, bit SCI_DISABLE=0, bit WDT_DISABLE=0, bit [3:0] BUS_AREA_TIMIMG=0, bit BUS_SIZE_BYTE_DISABLE=0, bit BUS_SIZE_WORD_DISABLE=0)
`endif
`endif
`endif
(
	input             CLK,
	input             RST_N,
	input             CE_R,
	input             CE_F,
	input             EN,
	
	input             RES_N,
	input             NMI_N,
	
	input       [3:0] IRL_N,
	
	output     [26:0] A,
	input      [31:0] DI,
	output     [31:0] DO,
	output            BS_N,
	output            CS0_N,
	output            CS1_N,
	output            CS2_N,
	output            CS3_N,
	output            RD_WR_N,	//WE_N
	output            CE_N,		//RAS_N
	output            OE_N,		//CAS_N
	output      [3:0] WE_N,		//CASxx_N/DQMxx
	output            RD_N,
	output            IVECF_N,
	output            RFS,
	
	input      [26:0] EA,
	output     [31:0] EDI,
	input      [31:0] EDO,
	input             EBS_N,
	input             ECS0_N,
	input             ECS1_N,
	input             ECS2_N,
	input             ECS3_N,
	input             ERD_WR_N,	//WE_N
	input             ECE_N,		//RAS_N
	input             EOE_N,		//CAS_N
	input       [3:0] EWE_N,		//CASxx_N/DQMxx
	input             ERD_N,
	input             EIVECF_N,
	
	input             WAIT_N,
	input             BRLS_N,	//BACK_N
	output            BGR_N,	//BREQ_N
	
	input             DREQ0,
	output            DACK0,
	input             DREQ1,
	output            DACK1,
	
	output            FTOA,
	output            FTOB,
	input             FTCI,
	input             FTI,
	
	input             RXD,
	output            TXD,
	output            SCKO,
	input             SCKI,
	
	output            WDTOVF_N,
	
	input       [5:0] MD,
	
	input             FAST
	
`ifdef SH2_SHARED_CORE
	                  ,
	// SH2_SHARED_CORE: this CPU's core is a thread of the shared core (rtl/SH/core/SH_core_cs.sv, instantiated in
	// rtl/Saturn/Saturn.sv): its SH_core ports, packed (layout in SH_core_cs.sv)
	output     [49:0] CORE_CI,
	input     [119:0] CORE_CO
`ifdef DEBUG
	                  ,
	output      [4:0] CORE_DBG_REGN,
	output            CORE_DBG_RUN,
	input      [31:0] CORE_DBG_REGQ,
	input             CORE_DBG_BREAK
`endif
`endif
`ifdef SH2_SHARE_DIVU
	                  ,
	// SH2_SHARE_DIVU: the DIVU is shared by both CPUs (SH7604_DIVUX in DIVU.sv, instantiated in rtl/Saturn/Saturn.sv):
	// this CPU's bus signals out, its read data / BUSY / interrupt in
	output     [44:0] DIVUX_O,
	input      [41:0] DIVUX_I
`endif
`ifdef SH2_SHARE_MULTCS
	                  ,
	// SH2_SHARE_MULTCS: the MULT is shared by both CPUs (SH7604_MULTCS in MULT.sv, instantiated in rtl/Saturn/Saturn.sv):
	// this CPU's MAC controls and operand out, its MACH / MACL / MM_DONE in
	output     [40:0] MULTCS_O,
	input      [64:0] MULTCS_I
`endif
`ifdef SH2_SHARE_MULT
	                  ,
	// SH2_SHARE_MULT: the multiply / accumulate datapath is shared by both CPUs (SH7604_MULTX in MULT.sv, instantiated
	// in rtl/Saturn/Saturn.sv): this CPU's operands out, its result in
	output    [133:0] MULTX_O,
	input      [63:0] MULTX_I
`endif
`ifdef DEBUG
	                  ,
	input       [4:0] DBG_REGN,
	output     [31:0] DBG_REGQ,
	input             DBG_RUN,
	output            DBG_BREAK
`endif
);

	import SH7604_PKG::*;
	
	bit [31:0] CBUS_A;
	bit [31:0] CBUS_A_NEXT;	//CBUS_A one clock early (the cache's tag M10K address)
	bit [31:0] CBUS_DO;
	bit [31:0] CBUS_DI;
	bit        CBUS_WR;
	bit  [3:0] CBUS_BA;
	bit        CBUS_REQ;
	bit        CBUS_ID;
	bit        CBUS_TAS;
	
	bit [31:0] IBUS_A;
	bit [31:0] IBUS_DO;
	bit [31:0] IBUS_DI;
	bit  [3:0] IBUS_BA;
	bit        IBUS_WE;
	bit        IBUS_REQ;
	bit        IBUS_PREREQ;
	bit        IBUS_WAIT;
	bit        IBUS_BURST;
	bit        IBUS_LOCK;
	
	bit  [3:0] INT_LVL;
	bit  [7:0] INT_VEC;
	bit        INT_REQ;
	bit        INT_REQ_NEXT;
	bit  [3:0] INT_MASK;
	bit        INT_ACK;
	bit        INT_ACP;
	bit        VECT_REQ;
	bit        VECT_WAIT;
	
	bit        SLEEP;
	
	
	//CACHE
	bit [31:0] CACHE_DI;
	bit [31:0] CACHE_DO;
	bit        CACHE_BUSY;
	bit        CACHE_ACT;
	
	//BSC
	bit [31:0] BSC_IBUS_DO;
	bit [31:0] BSC_DBUS_DO;
	bit        BSC_IBUS_BUSY;
	bit        BSC_DBUS_BUSY;
	bit        BSC_VBUS_BUSY;
	bit        BSC_ACK;
	
	//DMAC
	bit [31:0] DMAC_DO;
	bit        DMAC_ACT;
	bit        DMAC0_IRQ;
	bit  [7:0] DMAC0_VEC;
	bit        DMAC1_IRQ;
	bit  [7:0] DMAC1_VEC;
	
	//INTC
	bit [31:0] INTC_DO;
	bit        INTC_ACT;
	bit        INTC_BUSY;
	bit  [3:0] VBUS_A;
	bit  [7:0] VBUS_DO;
	bit        VBUS_REQ;
	bit        INTC_NMI_REQ;
	
	//MULT
	bit  [1:0] MAC_SEL;
	bit  [3:0] MAC_OP;
	bit        MAC_S;
	bit        MAC_WE;
	bit [31:0] MULT_DO;
	bit        MULT_BUSY;
	
	//SCI
	bit [31:0] SCI_DO;
	bit        SCI_ACT;
	bit        TEI_IRQ;
	bit        TXI_IRQ;
	bit        RXI_IRQ;
	bit        ERI_IRQ;
	
	//FRT
	bit [31:0] FRT_DO;
	bit        FRT_ACT;
	bit        ICI_IRQ;
	bit        OCIA_IRQ;
	bit        OCIB_IRQ;
	bit        OVI_IRQ;
	
	//WDT
	bit [31:0] WDT_DO;
	bit        WDT_ACT;
	bit        WDT_BUSY;
	bit        ITI_IRQ;
	bit        WDT_OVF;
	bit        WDT_PRES;
	bit        WDT_MRES;

	//DIVU
	bit [31:0] DIVU_DO;
	bit        DIVU_BUSY;
	bit        DIVU_ACT;
	bit        DIVU_IRQ;
	bit  [7:0] DIVU_VEC;
	
	//UBC
	bit [31:0] UBC_DO;
	bit        UBC_ACT;
	bit        UBC_IRQ;
	
	//MSBY
	bit [31:0] MSBY_DO;
	bit        MSBY_ACT;
	bit        MSBY_SBY;
	
	//Internal clocks
	bit        CLK2_CE;
	bit        CLK4_CE;
	bit        CLK8_CE;
	bit        CLK16_CE;
	bit        CLK32_CE;
	bit        CLK64_CE;
	bit        CLK128_CE;
	bit        CLK256_CE;
	bit        CLK512_CE;
	bit        CLK1024_CE;
	bit        CLK2048_CE;
	bit        CLK4096_CE;
	bit        CLK8192_CE;
	
	bit        RES_SYNC_N;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			RES_SYNC_N <= 0;
		end
		else begin	
			if (CE_R) begin
				RES_SYNC_N <= RES_N;
			end
		end
	end
	
`ifdef SH2_SHARED_CORE
	// the core: a thread of the shared core, which executes in this CPU's CE_R clocks (SH_core_cs.sv); the same ports and
	// connections as the SH_core instance below
	assign CORE_CI = {RES_SYNC_N, NMI_N, CBUS_DI, CACHE_BUSY | (MULT_BUSY & ~FAST), INT_LVL, INT_VEC, INT_REQ & ~MSBY_SBY,
	                  INT_REQ_NEXT & ~MSBY_SBY, VECT_WAIT};
	assign {CBUS_A, CBUS_DO, CBUS_WR, CBUS_BA, CBUS_REQ, CBUS_ID, CBUS_TAS, CBUS_A_NEXT, MAC_SEL, MAC_OP, MAC_S, MAC_WE,
	        INT_MASK, INT_ACK, INT_ACP, VECT_REQ, SLEEP} = CORE_CO;
`ifdef DEBUG
	assign CORE_DBG_REGN = DBG_REGN;
	assign CORE_DBG_RUN = DBG_RUN;
	assign DBG_REGQ = CORE_DBG_REGQ;
	assign DBG_BREAK = CORE_DBG_BREAK;
`endif
`else
	SH_core core
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.CE(CE_R),
		.EN(EN),
		
		.RES_N(RES_SYNC_N),
		.NMI_N(NMI_N),
		
		.BUS_A(CBUS_A),
		.BUS_DI(CBUS_DI),
		.BUS_DO(CBUS_DO),
		.BUS_WR(CBUS_WR),
		.BUS_BA(CBUS_BA),
		.BUS_REQ(CBUS_REQ),
		.BUS_ID(CBUS_ID),
		.BUS_TAS(CBUS_TAS),
		.BUS_WAIT(CACHE_BUSY | (MULT_BUSY & ~FAST)),
		.BUS_A_NEXT(CBUS_A_NEXT),
		
		.MAC_SEL(MAC_SEL),
		.MAC_OP(MAC_OP),
		.MAC_S(MAC_S),
		.MAC_WE(MAC_WE),
		
		.INT_LVL(INT_LVL),
		.INT_VEC(INT_VEC),
		.INT_REQ(INT_REQ & ~MSBY_SBY),
		.INT_REQ_NEXT(INT_REQ_NEXT & ~MSBY_SBY),
		.INT_MASK(INT_MASK),
		.INT_ACK(INT_ACK),
		.INT_ACP(INT_ACP),
		.VECT_REQ(VECT_REQ),
		.VECT_WAIT(VECT_WAIT),
		
		.SLEEP(SLEEP)
`ifdef DEBUG
		,
		.DBG_REGN(DBG_REGN),
		.DBG_REGQ(DBG_REGQ),
		.DBG_RUN(DBG_RUN),
		.DBG_BREAK(DBG_BREAK)
`endif
	);
`endif
	
	assign CBUS_DI = |MAC_SEL && MAC_OP == 4'b1100 && !MAC_WE ? MULT_DO : CACHE_DO;
	
	wire [31:0] MULT_DI = |MAC_SEL && MAC_OP[3:2] == 2'b10 ? CACHE_DO : CBUS_DO;
`ifdef SH2_SHARE_MULTCS
	// SH2_SHARE_MULTCS: this CPU's MULT is a thread of the shared, C-slowed SH7604_MULTCS (MULT.sv, instantiated in
	// rtl/Saturn/Saturn.sv); the bus read data and busy stay here (SH7604_MULT's code)
	assign MULTCS_O = {MAC_WE, MAC_SEL, MAC_OP, MAC_S, CBUS_A[1], MULT_DI};
	assign MULT_DO = MAC_SEL[1] ? MULTCS_I[64:33] : MULTCS_I[32:1];
	assign MULT_BUSY = ~MULTCS_I[0] && (!MAC_OP[2] ? MAC_SEL[0] : |MAC_SEL);
`else
	SH7604_MULT mult
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.CE_R(CE_R),
		.CE_F(CE_F),
		.EN(EN),
		
		.RES_N(RES_SYNC_N),
		
		.CBUS_A(CBUS_A),
		.CBUS_DI(MULT_DI),
		.CBUS_DO(MULT_DO),
		.CBUS_WR(CBUS_WR),
		.CBUS_BA(CBUS_BA),
		.CBUS_REQ(CBUS_REQ),
		.CBUS_BUSY(MULT_BUSY),
		
		.MAC_SEL(MAC_SEL),
		.MAC_OP(MAC_OP),
		.MAC_S(MAC_S),
		.MAC_WE(MAC_WE)
`ifdef SH2_SHARE_MULT
		,
		.X_O(MULTX_O),
		.X_I(MULTX_I)
`endif
	);
`endif
	

	assign CACHE_DI = |MAC_SEL && MAC_OP == 4'b1110 && !MAC_WE ? MULT_DO : CBUS_DO;
`ifdef CUT_MSH_CACHE_TW
	SH7604_CACHE #(.CUT_AARD(CUT_CACHE_AARD), .CUT_TW(CUT_CACHE_TW)) cache
`else
`ifdef CUT_SSH_CACHE_AARD
	SH7604_CACHE #(.CUT_AARD(CUT_CACHE_AARD)) cache
`else
	SH7604_CACHE cache
`endif
`endif
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.CE_R(CE_R),
		.CE_F(CE_F),
		.EN(EN),
		
		.RES_N(RES_SYNC_N),
		
		.CBUS_A(CBUS_A),
		.CBUS_A_NEXT(CBUS_A_NEXT),
		.CBUS_DI(CACHE_DI),
		.CBUS_DO(CACHE_DO),
		.CBUS_WR(CBUS_WR),
		.CBUS_BA(CBUS_BA),
		.CBUS_REQ(CBUS_REQ),
		.CBUS_ID(CBUS_ID),
		.CBUS_TAS(CBUS_TAS),
		.CBUS_BUSY(CACHE_BUSY),
		
		.IBUS_A(IBUS_A),
		.IBUS_DI(IBUS_DI),
		.IBUS_DO(IBUS_DO),
		.IBUS_WE(IBUS_WE),
		.IBUS_BA(IBUS_BA),
		.IBUS_REQ(IBUS_REQ),
		.IBUS_PREREQ(IBUS_PREREQ),
		.IBUS_BURST(IBUS_BURST),
		.IBUS_LOCK(IBUS_LOCK),
		.IBUS_WAIT(IBUS_WAIT)
	);
	
	// The on-chip modules' address ranges are disjoint, so at most one *_ACT is set, and every module but the INTC
	// already drives 0 when it is not selected: an OR of the outputs equals the priority chain.
	wire IBUS_ANY_ACT = INTC_ACT | DIVU_ACT | DMAC_ACT | FRT_ACT | WDT_ACT | SCI_ACT | UBC_ACT;
	assign IBUS_DI = (INTC_DO & {32{INTC_ACT}}) | DIVU_DO | DMAC_DO | FRT_DO | WDT_DO | SCI_DO | UBC_DO |
	                 (BSC_IBUS_DO & {32{~IBUS_ANY_ACT}});
	assign IBUS_WAIT = INTC_ACT ? INTC_BUSY :
	                   DIVU_ACT ? DIVU_BUSY :
						    DMAC_ACT ? 1'b0 : 
						    UBC_ACT  ? 1'b0 :  
						    FRT_ACT  ? 1'b0 : 
						    WDT_ACT  ? WDT_BUSY : 
						    SCI_ACT  ? 1'b0 : 
	                              BSC_IBUS_BUSY;

	
	SH7604_UBC #(UBC_DISABLE) UBC
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.CE_R(CE_R),
		.CE_F(CE_F),
		.EN(EN),
		
		.RES_N(RES_SYNC_N),
		
		.IBUS_A(IBUS_A),
		.IBUS_DI(IBUS_DO),
		.IBUS_DO(UBC_DO),
		.IBUS_BA(IBUS_BA),
		.IBUS_WE(IBUS_WE),
		.IBUS_REQ(IBUS_REQ),
		.IBUS_BUSY(),
		.IBUS_ACT(UBC_ACT),
		
		.IRQ(UBC_IRQ)
	);
	
	
	//Clock divider
	always @(posedge CLK or negedge RST_N) begin
		bit [12:0] DIV_CNT;
		
		if (!RST_N) begin
			CLK2_CE <= 0;
			CLK4_CE <= 0;
			CLK8_CE <= 0;
			CLK16_CE <= 0;
			CLK32_CE <= 0;
			CLK64_CE <= 0;
			CLK128_CE <= 0;
			CLK256_CE <= 0;
			CLK512_CE <= 0;
			CLK1024_CE <= 0;
			CLK2048_CE <= 0;
			CLK4096_CE <= 0;
			CLK8192_CE <= 0;
			DIV_CNT <= '0;
		end
		else if (!RES_SYNC_N) begin
			CLK2_CE <= 0;
			CLK4_CE <= 0;
			CLK8_CE <= 0;
			CLK16_CE <= 0;
			CLK32_CE <= 0;
			CLK64_CE <= 0;
			CLK128_CE <= 0;
			CLK256_CE <= 0;
			CLK512_CE <= 0;
			CLK1024_CE <= 0;
			CLK2048_CE <= 0;
			CLK4096_CE <= 0;
			CLK8192_CE <= 0;
			DIV_CNT <= '0;
		end
		else if (CE_R) begin	
			DIV_CNT <= DIV_CNT + 13'd1;
			
			CLK2_CE    <= (DIV_CNT ==? 13'b????????????1);
			CLK4_CE    <= (DIV_CNT ==? 13'b???????????11);
			CLK8_CE    <= (DIV_CNT ==? 13'b??????????111);
			CLK16_CE   <= (DIV_CNT ==? 13'b?????????1111);
			CLK32_CE   <= (DIV_CNT ==? 13'b????????11111);
			CLK64_CE   <= (DIV_CNT ==? 13'b???????111111);
			CLK128_CE  <= (DIV_CNT ==? 13'b??????1111111);
			CLK256_CE  <= (DIV_CNT ==? 13'b?????11111111);
			CLK512_CE  <= (DIV_CNT ==? 13'b????111111111);
			CLK1024_CE <= (DIV_CNT ==? 13'b???1111111111);
			CLK2048_CE <= (DIV_CNT ==? 13'b??11111111111);
			CLK4096_CE <= (DIV_CNT ==? 13'b?111111111111);
			CLK8192_CE <= (DIV_CNT ==? 13'b1111111111111);
		end
	end
	
	bit  [31:0] DBUS_A;
	bit  [31:0] DBUS_DO;
	bit   [3:0] DBUS_BA;
	bit         DBUS_WE;
	bit         DBUS_REQ;
	bit         DBUS_BURST;
	bit         DBUS_LOCK;
`ifdef U3_DMAC
`ifdef CUT_MSH_DMAC_DREQ_IE
	SH7604_DMAC #(.CUT_CH1(CUT_DMAC1), .CUT_MODES(CUT_DMAC_MODES), .CUT_DREQ_IE(CUT_DMAC_DREQ_IE)) dmac
`else
	SH7604_DMAC #(.CUT_CH1(CUT_DMAC1), .CUT_MODES(CUT_DMAC_MODES)) dmac
`endif
`else
	SH7604_DMAC dmac
`endif
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.CE_R(CE_R),
		.CE_F(CE_F),
		.EN(EN),
		
		.RES_N(RES_SYNC_N),
		.NMI_N(NMI_N),
		
		.DREQ0(DREQ0),
		.DACK0(DACK0),
		.DREQ1(DREQ1),
		.DACK1(DACK1),
		
		.RXI_IRQ(1'b0),
		.TXI_IRQ(1'b0),
		
		.IBUS_A(IBUS_A),
		.IBUS_DI(IBUS_DO),
		.IBUS_DO(DMAC_DO),
		.IBUS_BA(IBUS_BA),
		.IBUS_WE(IBUS_WE),
		.IBUS_REQ(IBUS_REQ),
		.IBUS_ACT(DMAC_ACT),
		
		.DBUS_A(DBUS_A),
		.DBUS_DI(BSC_DBUS_DO),
		.DBUS_DO(DBUS_DO),
		.DBUS_BA(DBUS_BA),
		.DBUS_WE(DBUS_WE),
		.DBUS_REQ(DBUS_REQ),
		.DBUS_BURST(DBUS_BURST),
		.DBUS_LOCK(DBUS_LOCK),
		.DBUS_WAIT(BSC_DBUS_BUSY),
		
		.BSC_ACK(BSC_ACK),
		
		.DMAC0_IRQ(DMAC0_IRQ),
		.DMAC0_VEC(DMAC0_VEC),
		.DMAC1_IRQ(DMAC1_IRQ),
		.DMAC1_VEC(DMAC1_VEC)
	);
	
	bit  [26:0] IA;
	bit  [31:0] IDI;
	bit  [31:0] IDO;
	bit         IBS_N;
	bit         ICS0_N;
	bit         ICS1_N;
	bit         ICS2_N;
	bit         ICS3_N;
	bit         IRD_WR_N;
	bit         ICE_N;
	bit         IOE_N;
	bit   [3:0] IWE_N;
	bit         IRD_N;
	bit         IIVECF_N;
	bit         BUS_RLS;
`ifdef U5_ANY
	SH7604_BSC #(.AREA_TIMIMG(BUS_AREA_TIMIMG), .SIZE_BYTE_DISABLE(BUS_SIZE_BYTE_DISABLE), .SIZE_WORD_DISABLE(BUS_SIZE_WORD_DISABLE),
	             .FIX_BCR(CUT_BSC_FIX), .FIX_MCR(CUT_BSC_MCR), .FIX_RTC(CUT_BSC_RTC),	//U5
	             .BCR1_FIX(BSC_BCR1), .BCR2_FIX(BSC_BCR2), .WCR_FIX(BSC_WCR), .MCR_FIX(BSC_MCR), .MCR_VAR(BSC_MCR_VAR),
	             .RTCSR_FIX(BSC_RTCSR), .RTCOR_FIX(BSC_RTCOR)) bsc
`else
	SH7604_BSC #(.AREA_TIMIMG(BUS_AREA_TIMIMG), .SIZE_BYTE_DISABLE(BUS_SIZE_BYTE_DISABLE), .SIZE_WORD_DISABLE(BUS_SIZE_WORD_DISABLE)) bsc
`endif
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.CE_R(CE_R),
		.CE_F(CE_F),
		.EN(EN),
		
		.RES_N(RES_SYNC_N),
		
		.CLK4_CE(CLK4_CE),
		.CLK16_CE(CLK16_CE),
		.CLK64_CE(CLK64_CE),
		.CLK256_CE(CLK256_CE),
		.CLK1024_CE(CLK1024_CE),
		.CLK2048_CE(CLK2048_CE),
		.CLK4096_CE(CLK4096_CE),
		
		.A(IA),
		.DI(IDI),
		.DO(IDO),
		.BS_N(IBS_N),
		.CS0_N(ICS0_N),
		.CS1_N(ICS1_N),
		.CS2_N(ICS2_N),
		.CS3_N(ICS3_N),
		.RD_WR_N(IRD_WR_N),
		.CE_N(ICE_N),
		.OE_N(IOE_N),
		.WE_N(IWE_N),
		.RD_N(IRD_N),
		.IVECF_N(IIVECF_N),
		.WAIT_N(WAIT_N),
		.BRLS_N(BRLS_N),
		.BGR_N(BGR_N),
		.RFS(RFS),
		.MD(MD),
		
		.CBUS_A(IBUS_A),
		.CBUS_DI(IBUS_DO),
		.CBUS_DO(BSC_IBUS_DO),
		.CBUS_BA(IBUS_BA),
		.CBUS_WE(IBUS_WE),
		.CBUS_REQ(IBUS_REQ),
		.CBUS_PREREQ(IBUS_PREREQ),
		.CBUS_BURST(IBUS_BURST),
		.CBUS_LOCK(IBUS_LOCK),
		.CBUS_BUSY(BSC_IBUS_BUSY),
		.CBUS_ACT(),
		
		.DBUS_A(DBUS_A),
		.DBUS_DI(DBUS_DO),
		.DBUS_DO(BSC_DBUS_DO),
		.DBUS_BA(DBUS_BA),
		.DBUS_WE(DBUS_WE),
		.DBUS_REQ(DBUS_REQ),
		.DBUS_BURST(DBUS_BURST),
		.DBUS_LOCK(DBUS_LOCK),
		.DBUS_BUSY(BSC_DBUS_BUSY),
		
		.VBUS_A(VBUS_A),
		.VBUS_DO(VBUS_DO),
		.VBUS_REQ(VBUS_REQ),
		.VBUS_BUSY(BSC_VBUS_BUSY),
		
		.IRQ(),
		
		.CACK(BSC_ACK),
		.BUS_RLS(BUS_RLS),
		
		.FAST(FAST)
	);
	
	assign {A,DO}                                 = !BUS_RLS ? {IA,IDO}                                     : {EA,EDO};
	// The BSC reads DI only in its own bus cycles (DAT_BUF in T2/TRD, VEC_BUF in TV2) and BUS_RLS is 0 in every state
	// but T0: it is only set at a CE_F in T0 (master: after BGR, slave: after BREQ dropped) and no cycle starts while
	// it, the master's BGR or the slave's !BREQ is set (BSC.sv; CE_R and CE_F never in the same clock: Saturn.sv
	// SYS_CE_F = ~SYS_CE_R). So the EDO side of the former !BUS_RLS ? DI : EDO was never sampled.
	assign IDI                                    = DI;
	assign {BS_N,CS0_N,CS1_N,CS2_N,CS3_N}         = !BUS_RLS ? {IBS_N,ICS0_N,ICS1_N,ICS2_N,ICS3_N}          : {EBS_N,ECS0_N,ECS1_N,ECS2_N,ECS3_N};
	assign {RD_WR_N,CE_N,OE_N,WE_N,RD_N,IVECF_N}  = !BUS_RLS ? {IRD_WR_N,ICE_N,IOE_N,IWE_N,IRD_N,IIVECF_N}  : {ERD_WR_N,ECE_N,EOE_N,EWE_N,ERD_N,EIVECF_N};
	assign EDI = DI;
	
	
`ifdef U3_INTC
	SH7604_INTC #(.NO_UBC_BSC_IRQ(1), .NO_SCI_IRQ(SCI_DISABLE), .CUT_VECMD(CUT_VECMD),	//UBC.sv drives IRQ 0, BSC_IRQ is tied 0 below
`ifdef U4_INTC
	              .NO_INT_4_7(CUT_WDT & CUT_DMAC_MODES & CUT_DIVU_OVF), .NO_FRT_OCOV(CUT_FRT_OC),	//U3: requests the cuts make constant 0
	              .NO_INT_4_6(CUT_DIVU_OVF & CUT_DMAC_DREQ_IE)) intc	//U4: the master's DIVU and DMAC requests are constant 0
`else
	              .NO_INT_4_7(CUT_WDT & CUT_DMAC_MODES & CUT_DIVU_OVF), .NO_FRT_OCOV(CUT_FRT_OC)) intc	//U3: requests the cuts make constant 0
`endif
`else
	SH7604_INTC #(.NO_UBC_BSC_IRQ(1), .NO_SCI_IRQ(SCI_DISABLE)) intc	//UBC.sv drives IRQ 0, BSC_IRQ is tied 0 below
`endif
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.CE_R(CE_R),
		.CE_F(CE_F),
		.EN(EN),
		
		.RES_N(RES_SYNC_N),
		.NMI_N(NMI_N),
		.IRL_N(IRL_N),
		
		.INT_MASK(INT_MASK),
		.INT_ACK(INT_ACK),
		.INT_ACP(INT_ACP),
		.INT_LVL(INT_LVL),
		.INT_VEC(INT_VEC),
		.INT_REQ(INT_REQ),
		.INT_REQ_NEXT(INT_REQ_NEXT),
		.VECT_REQ(VECT_REQ),
		.VECT_WAIT(VECT_WAIT),
		
		.NMI_REQ(INTC_NMI_REQ),
		
		.UBC_IRQ(UBC_IRQ),
		.DIVU_IRQ(DIVU_IRQ),
		.DIVU_VEC(DIVU_VEC),
		.DMAC0_IRQ(DMAC0_IRQ),
		.DMAC0_VEC(DMAC0_VEC),
		.DMAC1_IRQ(DMAC1_IRQ),
		.DMAC1_VEC(DMAC1_VEC),
		.WDT_IRQ(ITI_IRQ),
		.BSC_IRQ(1'b0),
		.SCI_ERI_IRQ(ERI_IRQ),
		.SCI_RXI_IRQ(RXI_IRQ),
		.SCI_TXI_IRQ(TXI_IRQ),
		.SCI_TEI_IRQ(TEI_IRQ),
		.FRT_ICI_IRQ(ICI_IRQ),
		.FRT_OCI_IRQ(OCIA_IRQ | OCIB_IRQ),
		.FRT_OVI_IRQ(OVI_IRQ),
		
		.IBUS_A(IBUS_A),
		.IBUS_DI(IBUS_DO),
		.IBUS_DO(INTC_DO),
		.IBUS_BA(IBUS_BA),
		.IBUS_WE(IBUS_WE),
		.IBUS_REQ(IBUS_REQ),
		.IBUS_BUSY(INTC_BUSY),
		.IBUS_ACT(INTC_ACT),
		
		.VBUS_A(VBUS_A),
		.VBUS_DI(VBUS_DO),
		.VBUS_REQ(VBUS_REQ),
		.VBUS_WAIT(BSC_VBUS_BUSY)
	);
	
`ifdef SH2_SHARE_DIVU
	// SH2_SHARE_DIVU: this CPU's DIVU is a thread of the shared, C-slowed SH7604_DIVUX (DIVU.sv, instantiated in
	// rtl/Saturn/Saturn.sv); the address decode and the bus read formatting stay here (SH7604_DIVU's code)
	assign DIVU_ACT = (IBUS_A >= 32'hFFFFFF00 && IBUS_A <= 32'hFFFFFF3F);
	assign DIVUX_O = {RES_SYNC_N, DIVU_ACT, IBUS_A[4:0], IBUS_BA, IBUS_WE, IBUS_REQ, IBUS_DO};
	wire [31:0] DIVUX_RDO = DIVUX_I[41:10];
	assign DIVU_DO = DIVU_ACT ? (IBUS_BA != 4'b1111 ? {2{DIVUX_RDO[15:0]}} : DIVUX_RDO) : '0;
	assign DIVU_BUSY = DIVUX_I[9];
	assign DIVU_IRQ = DIVUX_I[8];
	assign DIVU_VEC = DIVUX_I[7:0];
`else
`ifdef CUT_MSH_DIVU_OVF
	SH7604_DIVU #(.CUT_OVFIE(CUT_DIVU_OVF)) divu
`else
`ifdef CUT_SSH_DIVU_OVF
	SH7604_DIVU #(.CUT_OVFIE(CUT_DIVU_OVF)) divu
`else
	SH7604_DIVU divu
`endif
`endif
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.CE_R(CE_R),
		.CE_F(CE_F),
		.EN(EN),
		
		.RES_N(RES_SYNC_N),
		
		.IBUS_A(IBUS_A),
		.IBUS_DI(IBUS_DO),
		.IBUS_DO(DIVU_DO),
		.IBUS_BA(IBUS_BA),
		.IBUS_WE(IBUS_WE),
		.IBUS_REQ(IBUS_REQ),
		.IBUS_BUSY(DIVU_BUSY),
		.IBUS_ACT(DIVU_ACT),
		
		.IRQ(DIVU_IRQ),
		.VEC(DIVU_VEC)
	);
`endif

	SH7604_SCI #(SCI_DISABLE) sci
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.CE_R(CE_R),
		.CE_F(CE_F),
		.EN(EN),
		
		.RES_N(RES_SYNC_N),
		
		.RXD(RXD),
		.TXD(TXD),
		.SCKO(SCKO),
		.SCKI(SCKI),
		
		.CLK4_CE(CLK4_CE),
		.CLK16_CE(CLK16_CE),
		.CLK64_CE(CLK64_CE),
		.CLK256_CE(CLK256_CE),
		
		.IBUS_A(IBUS_A),
		.IBUS_DI(IBUS_DO),
		.IBUS_DO(SCI_DO),
		.IBUS_BA(IBUS_BA),
		.IBUS_WE(IBUS_WE),
		.IBUS_REQ(IBUS_REQ),
		.IBUS_BUSY(),
		.IBUS_ACT(SCI_ACT),
		
		.TEI_IRQ(TEI_IRQ),
		.TXI_IRQ(TXI_IRQ),
		.RXI_IRQ(RXI_IRQ),
		.ERI_IRQ(ERI_IRQ)
	);
	
`ifdef U3_FRT
	SH7604_FRT #(.CUT_OC(CUT_FRT_OC), .CUT_FICR(CUT_FRT_FICR)) frt
`else
	SH7604_FRT frt
`endif
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.CE_R(CE_R),
		.CE_F(CE_F),
		.EN(EN),
		
		.RES_N(RES_SYNC_N),
		.SBY(MSBY_SBY),
		
		.FTOA(FTOA),
		.FTOB(FTOB),
		.FTCI(FTCI),
		.FTI(FTI),
		
		.CLK4_CE(CLK4_CE),
		.CLK8_CE(CLK8_CE),
		.CLK32_CE(CLK32_CE),
		.CLK128_CE(CLK128_CE),
		
		.IBUS_A(IBUS_A),
		.IBUS_DI(IBUS_DO),
		.IBUS_DO(FRT_DO),
		.IBUS_BA(IBUS_BA),
		.IBUS_WE(IBUS_WE),
		.IBUS_REQ(IBUS_REQ),
		.IBUS_BUSY(),
		.IBUS_ACT(FRT_ACT),
		
		.ICI_IRQ(ICI_IRQ),
		.OCIA_IRQ(OCIA_IRQ),
		.OCIB_IRQ(OCIB_IRQ),
		.OVI_IRQ(OVI_IRQ)
	);
	
`ifdef CUT_MSH_WDT_RST
	SH7604_WDT #(.DISABLE(WDT_DISABLE | CUT_WDT), .CUT(CUT_WDT), .CUT_RST(CUT_WDT_RST)) wdt
`else
`ifdef CUT_SSH_WDT
	SH7604_WDT #(.DISABLE(WDT_DISABLE | CUT_WDT), .CUT(CUT_WDT)) wdt
`else
	SH7604_WDT #(WDT_DISABLE) wdt
`endif
`endif
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.CE_R(CE_R),
		.CE_F(CE_F),
		.EN(EN),
		
		.RES_N(RES_SYNC_N),
		.SBY(MSBY_SBY),
		.NMI(INTC_NMI_REQ),
		
		.WDTOVF_N(WDTOVF_N),
		
		.CLK2_CE(CLK2_CE),
		.CLK64_CE(CLK64_CE),
		.CLK128_CE(CLK128_CE),
		.CLK256_CE(CLK256_CE),
		.CLK512_CE(CLK512_CE),
		.CLK1024_CE(CLK1024_CE),
		.CLK4096_CE(CLK4096_CE),
		.CLK8192_CE(CLK8192_CE),
		
		.IBUS_A(IBUS_A),
		.IBUS_DI(IBUS_DO),
		.IBUS_DO(WDT_DO),
		.IBUS_BA(IBUS_BA),
		.IBUS_WE(IBUS_WE),
		.IBUS_REQ(IBUS_REQ),
		.IBUS_BUSY(WDT_BUSY),
		.IBUS_ACT(WDT_ACT),
		
		.ITI_IRQ(ITI_IRQ),
		.OVF(WDT_OVF),
		.PRES(WDT_PRES),
		.MRES(WDT_MRES)
	);
	
`ifdef U3_SBY
	SH7604_MSBY #(.CUT_SBY(CUT_SBY | CUT_WDT)) msby	//U3: CUT_SSH_WDT stops standby too (the WDT ends it)
`else
	SH7604_MSBY msby
`endif
	(
		.CLK(CLK),
		.RST_N(RST_N),
		.CE_R(CE_R),
		.CE_F(CE_F),
		.EN(EN),
		
		.RES_N(RES_SYNC_N),
		
		.IBUS_A(IBUS_A),
		.IBUS_DI(IBUS_DO),
		.IBUS_DO(MSBY_DO),
		.IBUS_BA(IBUS_BA),
		.IBUS_WE(IBUS_WE),
		.IBUS_REQ(IBUS_REQ),
		.IBUS_BUSY(),
		.IBUS_ACT(MSBY_ACT),
		
		.SLEEP(SLEEP),
		.WDT_OVF(WDT_OVF),
		.SBY(MSBY_SBY)
	);
	
endmodule
`ifdef U3_INTC
`undef U3_INTC
`endif
`ifdef U3_SBY
`undef U3_SBY
`endif
`ifdef U3_DMAC
`undef U3_DMAC
`endif
`ifdef U3_FRT
`undef U3_FRT
`endif
`ifdef U3_ANY
`undef U3_ANY
`endif
`ifdef U4_INTC
`undef U4_INTC
`endif
`ifdef U4_ANY
`undef U4_ANY
`endif
`ifdef U5_ANY
`undef U5_ANY
`endif

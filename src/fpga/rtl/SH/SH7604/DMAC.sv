`ifdef CUT_SSH_DMAC1
`define U3_DMAC
`elsif CUT_SSH_DMAC_MODES
`define U3_DMAC
`endif
`ifdef CUT_MSH_DMAC_DREQ_IE
// U4: the master's DREQ / IE cut is built on U3's DMAC code (CUT_CH1 = CUT_MODES = 0 there)
`ifndef U3_DMAC
`define U3_DMAC
`endif
`endif
`ifdef U3_DMAC
`ifdef CUT_MSH_DMAC_DREQ_IE
module SH7604_DMAC #(parameter bit CUT_CH1=0, bit CUT_MODES=0, bit CUT_DREQ_IE=0) (	//U3 (the slave) / U4 CUT_DREQ_IE (the master): see U3_CHCRW below
`else
module SH7604_DMAC #(parameter bit CUT_CH1=0, bit CUT_MODES=0) (	//U3, the slave only: see U3_CHCRW below
`endif
`else
module SH7604_DMAC (
`endif
	input             CLK,
	input             RST_N,
	input             CE_R,
	input             CE_F,
	input             EN,
	
	input             RES_N,
	input             NMI_N,
	
	input             DREQ0,
	output            DACK0,
	input             DREQ1,
	output            DACK1,
	
	input             RXI_IRQ,
	input             TXI_IRQ,
	
	input      [31:0] IBUS_A,
	input      [31:0] IBUS_DI,
	output     [31:0] IBUS_DO,
	input       [3:0] IBUS_BA,
	input             IBUS_WE,
	input             IBUS_REQ,
	output            IBUS_ACT,
	
	output     [31:0] DBUS_A,
	input      [31:0] DBUS_DI,
	output     [31:0] DBUS_DO,
	output      [3:0] DBUS_BA,
	output            DBUS_WE,
	output            DBUS_REQ,
	output            DBUS_LOCK,
	output            DBUS_BURST,
	input             DBUS_WAIT,
	
	input             BSC_ACK,
	
	output            DMAC0_IRQ,
	output      [7:0] DMAC0_VEC,
	output            DMAC1_IRQ,
	output      [7:0] DMAC1_VEC
);

	import SH7604_PKG::*;

	SARx_t      SAR[2];
	DARx_t      DAR[2];
	TCRx_t      TCR[2];
	CHCRx_t     CHCR[2];
	DRCRx_t     DRCR[2];
	VCRDMAx_t   VCRDMA0;
	VCRDMAx_t   VCRDMA1;
	DMAOR_t     DMAOR;
		
`ifdef U3_DMAC
	// U3 (the slave only; 0 = as before).
	// CUT_CH1 (CUT_SSH_DMAC1): channel 1 never transfers. SAR1, DAR1 and TCR1 are not kept (writes ignored, reads 0);
	//   a start of channel 1 (DME and DE1, no TE1 / NMIF / AE) completes at once: TE1 is set in the clock the transfer
	//   request would have been raised, without a bus cycle. CHCR1, DRCR1, VCRDMA1 and the channel-1 end interrupt as
	//   before. Channel 1 never requests, so DMA_CH stays 0 and DMAOR.PR has nothing to arbitrate.
	// CUT_MODES (CUT_SSH_DMAC_MODES): a CHCR write (either channel) stores TB = 0 and IE = 0 (no burst mode, no end
	//   interrupt) and TS = 3 as 2 (no 16-byte units: RD_BUF is not used); the other bits as written. Every request
	//   is an auto-request: AR is kept and read back as written, but a start with AR = 0 runs as with AR = 1 (DREQ,
	//   DS, DL and DRCR.RS have no effect).
`ifdef CUT_MSH_DMAC_DREQ_IE
	// U4 CUT_DREQ_IE (CUT_MSH_DMAC_DREQ_IE, the master only; 0 = as before): no external-request (DREQ) transfers and
	//   no transfer-end interrupt, on both channels. A CHCR write stores IE, DS and DL as 0 (they read 0; DMAC0/1_IRQ
	//   stay 0) and DRCR writes are ignored (RS reads 0). Every start is an auto-request: AR is kept and read back as
	//   written, but a start with AR = 0 runs as with AR = 1 (before, with the DREQ pins tied high as on the Saturn, such
	//   a start ran continuously with DL = 1 and never with DL = 0 or with DRCR.RS != 0). Burst mode, 16-byte units,
	//   channel 1, single address mode and the rest as before. The master wrote IE = DS = DL = 0 in every CHCR write,
	//   AR = 1 in every start and DRCR = 0 only (BIOS boot, BIOS menus and every game; work/usage logs).
`endif
	function automatic bit [31:0] U3_CHCRW(input bit [31:0] d);
		bit [31:0] r;
		r = d;
		if (CUT_MODES) begin
			r[4] = 1'b0;				//TB
			r[2] = 1'b0;				//IE
			r[10] = d[10] & ~d[11];		//TS 3 -> 2
		end
`ifdef CUT_MSH_DMAC_DREQ_IE
		if (CUT_DREQ_IE) begin
			r[2] = 1'b0;				//IE (U4)
			r[6:5] = 2'b00;				//DS, DL (U4)
		end
`endif
		return r;
	endfunction

`endif
	function bit [3:0] BAFromAddr(input bit [1:0] addr, input bit [1:0] sz);
		bit [3:0] res;
	
		case (sz)
			2'b00: res = {~addr[1]&~addr[0],~addr[1]&addr[0],addr[1]&~addr[0],addr[1]&addr[0]};
			2'b01: res = {~addr[1]         ,~addr[1]        ,addr[1]                 ,addr[1]};
			2'b10: res = 4'b1111;
			2'b11: res = 4'b1111;
		endcase
		return res;
	endfunction
	
	//Signed address step: +/-1, +/-2, +/-4 by transfer size (16-byte units step by 4 per long word)
	function bit [31:0] GetAddrStep(input bit [1:0] sz, input bit dec);
		bit [31:0] res;
	
		case (sz)
			2'b00: res = dec ? 32'hFFFFFFFF : 32'd1;
			2'b01: res = dec ? 32'hFFFFFFFE : 32'd2;
			2'b10: res = dec ? 32'hFFFFFFFC : 32'd4;
			2'b11: res = dec ? 32'hFFFFFFFC : 32'd4;
		endcase
		return res;
	endfunction
	
	wire REG1_SEL = (IBUS_A >= 32'hFFFFFE71 && IBUS_A <= 32'hFFFFFE72);
	wire REG2_SEL = (IBUS_A >= 32'hFFFFFF80 && IBUS_A <= 32'hFFFFFFB3);

	wire CH_EN[2] = '{DMAOR.DME & CHCR[0].DE, DMAOR.DME & CHCR[1].DE};
	wire CH_AVAIL[2] = '{~CHCR[0].TE & ~DMAOR.NMIF & ~DMAOR.AE, ~CHCR[1].TE & ~DMAOR.NMIF & ~DMAOR.AE};

`ifdef U3_DMAC
	wire [31:0] U3_CHCR_D = U3_CHCRW(IBUS_DI & CHCRx_WMASK);	//CHCR write data (U3)

`endif
	bit         CH_REQ[2];
	bit         CH_REQ_CLR[2];
	always @(posedge CLK or negedge RST_N) begin
		bit         DREQ0_REQ;
		bit         DREQ1_REQ;
		bit         DREQ0_OLD;
		bit         DREQ1_OLD;
		
		if (!RST_N) begin
			DREQ0_REQ <= 0;
			DREQ1_REQ <= 0;
			DREQ0_OLD <= 0;
			DREQ1_OLD <= 0;
			CH_REQ <= '{0,0};
		end
		else if (CE_R) begin
			DREQ0_OLD <= DREQ0;
			if (!CHCR[0].DS) DREQ0_REQ <= ~DREQ0 ^ CHCR[0].DL;
			else DREQ0_REQ <= (~DREQ0 ^ CHCR[0].DL) & (DREQ0_OLD ^ CHCR[0].DL);
			
			if (!CH_REQ[0] && CH_EN[0] && CH_AVAIL[0]) begin
`ifdef U3_DMAC
`ifdef CUT_MSH_DMAC_DREQ_IE
				if (CHCR[0].AR || CUT_MODES || CUT_DREQ_IE) CH_REQ[0] <= 1;
`else
				if (CHCR[0].AR || CUT_MODES) CH_REQ[0] <= 1;
`endif
`else
				if (CHCR[0].AR) CH_REQ[0] <= 1;
`endif
				else 
					case(DRCR[0].RS)
						2'b00: CH_REQ[0] <= DREQ0_REQ;
						2'b01: CH_REQ[0] <= RXI_IRQ;
						2'b10: CH_REQ[0] <= TXI_IRQ;
						2'b11: CH_REQ[0] <= 0;
					endcase
			end
			else if (CH_REQ_CLR[0] || !CH_EN[0]) begin
				CH_REQ[0] <= 0;
			end
			
			DREQ1_OLD <= DREQ1;
			if (!CHCR[1].DS) DREQ1_REQ <= ~DREQ1 ^ CHCR[1].DL;
			else DREQ1_REQ <= (~DREQ1 ^ CHCR[1].DL) & (DREQ1_OLD ^ CHCR[1].DL);
			
`ifdef U3_DMAC
			if (!CUT_CH1 && !CH_REQ[1] && CH_EN[1] && CH_AVAIL[1]) begin
`ifdef CUT_MSH_DMAC_DREQ_IE
				if (CHCR[1].AR || CUT_MODES || CUT_DREQ_IE) CH_REQ[1] <= 1;
`else
				if (CHCR[1].AR || CUT_MODES) CH_REQ[1] <= 1;
`endif
`else
			if (!CH_REQ[1] && CH_EN[1] && CH_AVAIL[1]) begin
				if (CHCR[1].AR) CH_REQ[1] <= 1;
`endif
				else 
					case(DRCR[1].RS)
						2'b00: CH_REQ[1] <= DREQ1_REQ;
						2'b01: CH_REQ[1] <= RXI_IRQ;
						2'b10: CH_REQ[1] <= TXI_IRQ;
						2'b11: CH_REQ[1] <= 0;
					endcase
			end
			else if (CH_REQ_CLR[1] || !CH_EN[1]) begin
				CH_REQ[1] <= 0;
			end
		end
	end
	
	bit         DMA_REQ;
	bit         DMA_REQ_CLR;
	bit         DMA_CH;
	bit         RB_PRIO;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			DMA_REQ <= 0;
			DMA_CH <= 0;
			RB_PRIO <= 0;
		end
		else if (CE_R) begin
			if (!DMA_REQ) begin
				if ((CH_REQ[0] && CH_EN[0] && CH_AVAIL[0]) && 
				    (CH_REQ[1] && CH_EN[1] && CH_AVAIL[1]) && DMAOR.PR) begin
					DMA_REQ <= 1;
					DMA_CH <= RB_PRIO;
				end
				else if (CH_REQ[0] && CH_EN[0] && CH_AVAIL[0]) begin
					DMA_REQ <= 1;
					DMA_CH <= 0;
				end
				else if (CH_REQ[1] && CH_EN[1] && CH_AVAIL[1]) begin
					DMA_REQ <= 1;
					DMA_CH <= 1;
				end
			end
			else if (DMA_REQ_CLR) begin
				DMA_REQ <= 0;
				RB_PRIO <= ~RB_PRIO;
			end
		end
	end
	
	bit         DMA_WR;
	bit         DMA_RD;
	bit         DMA_BURST;
	bit         DMA_LOCK;
	bit  [31:0] RD_BUF[4];
	bit   [1:0] LW_CNT;
	bit   [1:0] SA_BA;
	
	//SAR and DAR never step in the same clock: SAR only in the DMA_RD branch, DAR only in the DMA_WR branch below
	//(DMA_RD has priority). So one adder steps both: the one of the current transfer phase, +/- the size increment.
	wire [31:0] AR_BASE = DMA_RD ? SAR[DMA_CH] : DAR[DMA_CH];
	wire        AR_DEC  = DMA_RD ? (~&CHCR[DMA_CH].TS & CHCR[DMA_CH].SM == 2'b10) : (CHCR[DMA_CH].DM == 2'b10);
	wire [31:0] AR_NEXT = AR_BASE + GetAddrStep(CHCR[DMA_CH].TS, AR_DEC);
	wire [23:0] TCR_NEXT = TCR[DMA_CH] - 24'd1;
	
	//SAR, DAR and TCR are written by the CPU only on CE_R clocks and stepped by a transfer only on CE_F clocks (the
	//two never coincide: CE_R and CE_F alternate, SYS_CE_R = MCLK_DIV, SYS_CE_F = ~MCLK_DIV). So the four address
	//registers share one write-data mux (bus data on CE_R, the stepped address on CE_F), the two counters another one,
	//and each register only has its own write enable.
	wire        REG2_WR  = CE_R & REG2_SEL & IBUS_WE & IBUS_REQ;
	wire        XFER     = (DMA_RD | DMA_WR) & ~DBUS_WAIT & CE_F;
	wire        SAR_STEP = XFER &  DMA_RD & (&CHCR[DMA_CH].TS | CHCR[DMA_CH].SM == 2'b01 | CHCR[DMA_CH].SM == 2'b10);
	wire        DAR_STEP = XFER & ~DMA_RD & DMA_WR & (CHCR[DMA_CH].DM == 2'b01 | CHCR[DMA_CH].DM == 2'b10);
	wire        TCR_STEP = XFER & ((DMA_RD & CHCR[DMA_CH].TA & ~CHCR[DMA_CH].AM & LW_CNT == 2'd0) | (~DMA_RD & DMA_WR));
	wire [31:0] AR_D     = CE_R ? IBUS_DI : AR_NEXT;
	wire [23:0] TC_D     = CE_R ? IBUS_DI[23:0] : TCR_NEXT;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			SAR <= '{2{SARx_INIT}};
			DAR <= '{2{DARx_INIT}};
			TCR <= '{2{TCRx_INIT}};
		end
		else begin
`ifdef U3_DMAC
			if ((REG2_WR && IBUS_A[5:2] == 4'h0) || (SAR_STEP && !DMA_CH)) SAR[0] <= AR_D;
			if ((REG2_WR && IBUS_A[5:2] == 4'h4 && !CUT_CH1) || (SAR_STEP &&  DMA_CH)) SAR[1] <= AR_D;
			if ((REG2_WR && IBUS_A[5:2] == 4'h1) || (DAR_STEP && !DMA_CH)) DAR[0] <= AR_D;
			if ((REG2_WR && IBUS_A[5:2] == 4'h5 && !CUT_CH1) || (DAR_STEP &&  DMA_CH)) DAR[1] <= AR_D;
			if ((REG2_WR && IBUS_A[5:2] == 4'h2) || (TCR_STEP && !DMA_CH)) TCR[0] <= TC_D;
			if ((REG2_WR && IBUS_A[5:2] == 4'h6 && !CUT_CH1) || (TCR_STEP &&  DMA_CH)) TCR[1] <= TC_D;
`else
			if ((REG2_WR && IBUS_A[5:2] == 4'h0) || (SAR_STEP && !DMA_CH)) SAR[0] <= AR_D;
			if ((REG2_WR && IBUS_A[5:2] == 4'h4) || (SAR_STEP &&  DMA_CH)) SAR[1] <= AR_D;
			if ((REG2_WR && IBUS_A[5:2] == 4'h1) || (DAR_STEP && !DMA_CH)) DAR[0] <= AR_D;
			if ((REG2_WR && IBUS_A[5:2] == 4'h5) || (DAR_STEP &&  DMA_CH)) DAR[1] <= AR_D;
			if ((REG2_WR && IBUS_A[5:2] == 4'h2) || (TCR_STEP && !DMA_CH)) TCR[0] <= TC_D;
			if ((REG2_WR && IBUS_A[5:2] == 4'h6) || (TCR_STEP &&  DMA_CH)) TCR[1] <= TC_D;
`endif
		end
	end
	
	always @(posedge CLK or negedge RST_N) begin
		bit         RD_BUF_LATCH;
		bit         CHCR_TE_OLD[2];
		
		if (!RST_N) begin
			CHCR <= '{2{CHCRx_INIT}};
			CHCR_TE_OLD <= '{2{1'b0}};
			
			DMA_WR <= 0;
			DMA_RD <= 0;
			DMA_BURST <= 0;
			DMA_LOCK <= 0;
			CH_REQ_CLR <= '{0,0};
			DMA_REQ_CLR <= 0;
			LW_CNT <= '0;
			RD_BUF_LATCH <= 0;
		end
		else begin
			CH_REQ_CLR[0] <= 0;
			CH_REQ_CLR[1] <= 0;
			DMA_REQ_CLR <= 0;
			if (DMA_REQ && !DMA_RD && !DMA_WR && CE_F) begin
				if (!CHCR[DMA_CH].TA || (CHCR[DMA_CH].TA && !CHCR[DMA_CH].AM)) begin
					DMA_RD <= 1;
					LW_CNT <= &CHCR[DMA_CH].TS ? 2'd3 : 2'd0;
					CH_REQ_CLR[DMA_CH] <= CHCR[DMA_CH].TA & ~CHCR[DMA_CH].AM;
					DMA_BURST <= &CHCR[DMA_CH].TS;
					DMA_LOCK <= ~CHCR[DMA_CH].TA | CHCR[DMA_CH].TB | &CHCR[DMA_CH].TS;
				end
				else begin
					DMA_WR <= 1;
					LW_CNT <= &CHCR[DMA_CH].TS ? 2'd3 : 2'd0;
					CH_REQ_CLR[DMA_CH] <= 1;
					DMA_BURST <= &CHCR[DMA_CH].TS;
					DMA_LOCK <= CHCR[DMA_CH].TB | &CHCR[DMA_CH].TS;
				end
			end
			else if ((DMA_RD || DMA_WR) && !DBUS_WAIT && CE_F) begin
				if (DMA_RD) begin
					if (!CHCR[DMA_CH].TA && (LW_CNT == 2'd0)) begin
						DMA_RD <= 0;
						DMA_WR <= 1;
						DMA_BURST <= &CHCR[DMA_CH].TS;
						DMA_LOCK <= CHCR[DMA_CH].TB | &CHCR[DMA_CH].TS;
						LW_CNT <= &CHCR[DMA_CH].TS ? 2'd3 : 2'd0;
						CH_REQ_CLR[DMA_CH] <= 1;
						if (TCR_NEXT == 24'd0) begin
							DMA_LOCK <= 0;
						end
					end
					else if (CHCR[DMA_CH].TA && !CHCR[DMA_CH].AM && (LW_CNT == 2'd0)) begin
						CH_REQ_CLR[DMA_CH] <= 1;
						DMA_REQ_CLR <= 1;
						LW_CNT <= &CHCR[DMA_CH].TS ? 2'd3 : 2'd0;
						
						if (!CHCR[DMA_CH].TB) DMA_RD <= 0;
						
						if (TCR_NEXT == 24'd0) begin
							CHCR[DMA_CH].TE <= 1;
							DMA_RD <= 0;
							DMA_BURST <= 0;
						end
					end
					RD_BUF_LATCH <= 1;
					SA_BA <= SAR[DMA_CH][1:0];
				end
				else if (DMA_WR) begin
					if (LW_CNT == 2'd1) begin
						if (!CHCR[DMA_CH].TB) DMA_LOCK <= 0;
					end 
					if ((LW_CNT == 2'd0) || (TCR_NEXT == 24'd0)) begin
						if (!CHCR[DMA_CH].TA) begin
							DMA_WR <= 0;
							if (CHCR[DMA_CH].TB) begin
								DMA_RD <= 1;
								DMA_BURST <= &CHCR[DMA_CH].TS;
								DMA_LOCK <= 1;
								LW_CNT <= &CHCR[DMA_CH].TS ? 2'd3 : 2'd0;
							end
						end 
						else if (CHCR[DMA_CH].TA && CHCR[DMA_CH].AM) begin
							CH_REQ_CLR[DMA_CH] <= 1;
							LW_CNT <= &CHCR[DMA_CH].TS ? 2'd3 : 2'd0;
							
							if (!CHCR[DMA_CH].TB) DMA_WR <= 0;
						end
						
						DMA_REQ_CLR <= 1;
					end
					
					if (TCR_NEXT == 24'd1) begin
						if (&CHCR[DMA_CH].TS) DMA_LOCK <= 0;
					end
					if (TCR_NEXT == 24'd0) begin
						CHCR[DMA_CH].TE <= 1;
						DMA_RD <= 0;
						DMA_WR <= 0;
						DMA_BURST <= 0;
					end
				end
				
				if (LW_CNT != 2'd0) LW_CNT <= LW_CNT - 2'd1;
				else LW_CNT <= &CHCR[DMA_CH].TS ? 2'd3 : 2'd0;
					
				// (a1) RD_BUF[1..3]: the MLAB ring RBQ below (written in the same clocks as this shift was made)
			end
			
			if (RD_BUF_LATCH && CE_R) begin
`ifdef U3_DMAC
				if (!CUT_MODES) RD_BUF[0] <= DBUS_DI;
`else
				RD_BUF[0] <= DBUS_DI;
`endif
				RD_BUF_LATCH <= 0;
			end
			
`ifdef U3_DMAC
			if (CE_R && CUT_CH1 && CH_EN[1] && CH_AVAIL[1]) CHCR[1].TE <= 1;	//CUT_CH1: a channel-1 start completes at once
			if (CUT_MODES) begin	//CUT_MODES: TS is never 3, so the TS = 3 terms above give LW_CNT = 0 and DMA_BURST = 0
				LW_CNT <= 2'd0;		//always; held here as constants, so synthesis drops the 16-byte unit counter
				DMA_BURST <= 0;		//and the burst flag
			end
`endif
			if (CE_R) begin
				if (REG2_SEL && IBUS_WE && IBUS_REQ) begin
					case ({IBUS_A[5:2],2'b00})
						6'h0C: begin
`ifdef U3_DMAC
							CHCR[0][31:2] <= U3_CHCR_D[31:2];
`else
							CHCR[0][31:2] <= IBUS_DI[31:2] & CHCRx_WMASK[31:2];
`endif
							if (!IBUS_DI[1] && CHCR_TE_OLD[0]) begin CHCR[0][1] <= 0; CHCR_TE_OLD[0] <= 0; end
							CHCR[0][0] <= IBUS_DI[0] & CHCRx_WMASK[0];
						end
						6'h1C: begin
`ifdef U3_DMAC
							CHCR[1][31:2] <= U3_CHCR_D[31:2];
`else
							CHCR[1][31:2] <= IBUS_DI[31:2] & CHCRx_WMASK[31:2];
`endif
							if (!IBUS_DI[1] && CHCR_TE_OLD[1]) begin CHCR[1][1] <= 0; CHCR_TE_OLD[1] <= 0; end
							CHCR[1][0] <= IBUS_DI[0] & CHCRx_WMASK[0];
						end
						default:;
					endcase
				end
			end
			if (CE_F) begin
				if (REG2_SEL && !IBUS_WE && IBUS_REQ) begin
					case ({IBUS_A[5:2],2'b00})
						6'h0C: CHCR_TE_OLD[0] <= CHCR[0].TE;
						6'h1C: CHCR_TE_OLD[1] <= CHCR[1].TE;
						default:;
					endcase
				end
			end
		end
	end
	
	// (a1) RD_BUF[1..3], the 16-byte unit's 3-deep shift chain (moved at every transfer step, read at RD_BUF[3]), as a
	// 4-entry ring in an MLAB: a step writes RD_BUF[0] at RBQ_WP and advances it, so the entry written three steps back
	// (RBQ_WP + 1) is what RD_BUF[3] held. The step condition is the else-if branch above that held the shift (its
	// first branch needs !DMA_RD && !DMA_WR); RST_N low = that block's reset branch, no step. RBQ_WP is never reset
	// (RD_BUF never was), so the chain / ring mapping survives resets.
	// (A3) the ring in an M10K instead of an MLAB (two memory LABs): its read address is registered on every clock edge
	// with the value RBQ_WP + 1 takes at that edge (RBQ_WP_N + 1), so after the edge the output is the word RBQ[RBQ_WP + 1]
	// as the MLAB's asynchronous read gave. A step writes slot RBQ_WP and moves RBQ_WP_N + 1 to RBQ_WP + 2, never the
	// slot written on that edge (no read-during-write case); without a step nothing is written and the address stays.
	(* ramstyle = "M10K, no_rw_check" *) bit [31:0] RBQ[4];
	bit   [1:0] RBQ_WP = 2'd0;
	wire        RD_BUF_STEP = RST_N && (DMA_RD || DMA_WR) && !DBUS_WAIT && CE_F;
`ifdef U3_DMAC
	wire        RBQ_EN = !CUT_MODES;	//CUT_MODES: no 16-byte units, RD_BUF is not used
`else
	wire        RBQ_EN = 1'b1;
`endif
	wire  [1:0] RBQ_WP_N = RBQ_WP + {1'b0,RBQ_EN && RD_BUF_STEP};
	bit  [31:0] RD_BUF3;
	always @(posedge CLK) begin
		if (RBQ_EN && RD_BUF_STEP) begin RBQ[RBQ_WP] <= RD_BUF[0]; RBQ_WP <= RBQ_WP + 2'd1; end
		RD_BUF3 <= RBQ[RBQ_WP_N + 2'd1];
	end

	wire DMA_ACCESS = DMA_RD | DMA_WR;
	
	bit [31:0] DBUS_DO_TEMP;
	always_comb begin
		case (CHCR[DMA_CH].TS)
			2'b00: 
				case (SA_BA)
					2'b00: DBUS_DO_TEMP = {4{DBUS_DI[31:24]}};
					2'b01: DBUS_DO_TEMP = {4{DBUS_DI[23:16]}};
					2'b10: DBUS_DO_TEMP = {4{DBUS_DI[15: 8]}};
					2'b11: DBUS_DO_TEMP = {4{DBUS_DI[ 7: 0]}};
				endcase
			2'b01: 
				case (SA_BA[1])
					1'b0: DBUS_DO_TEMP = {2{DBUS_DI[31:16]}};
					1'b1: DBUS_DO_TEMP = {2{DBUS_DI[15: 0]}};
				endcase
			2'b10: DBUS_DO_TEMP = DBUS_DI;
			2'b11: DBUS_DO_TEMP = RD_BUF3;
		endcase
	end
	
	assign DBUS_A = AR_BASE & 32'h07FFFFFF;	//no DMA_ACCESS gate on DBUS_A / DBUS_BA: the BSC reads them only with DBUS_REQ (= DMA_ACCESS)
	assign DBUS_DO = DBUS_DO_TEMP;
	assign DBUS_BA = BAFromAddr(AR_BASE[1:0],CHCR[DMA_CH].TS);
	assign DBUS_WE = DMA_RD ? 1'b0 : 
	                 DMA_WR ? 1'b1 : 
	                 1'b0;
	assign DBUS_REQ = DMA_ACCESS;
	assign DBUS_BURST = DMA_BURST;
	assign DBUS_LOCK  = DMA_LOCK;
	
	assign DACK0 = (BSC_ACK & !DMA_CH & ((DMA_RD & (~CHCR[0].AM | CHCR[0].TA)) | (DMA_WR & (CHCR[0].AM | CHCR[0].TA)))) ^ ~CHCR[0].AL;
	assign DACK1 = (BSC_ACK &  DMA_CH & ((DMA_RD & (~CHCR[1].AM | CHCR[1].TA)) | (DMA_WR & (CHCR[1].AM | CHCR[1].TA)))) ^ ~CHCR[1].AL;
	
	assign DMAC0_IRQ = CHCR[0].TE & CHCR[0].IE;
	assign DMAC0_VEC = VCRDMA0.VC;
	assign DMAC1_IRQ = CHCR[1].TE & CHCR[1].IE;
	assign DMAC1_VEC = VCRDMA1.VC;
	
	//Registers
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			DRCR[0] <= DRCRx_INIT;
			DRCR[1] <= DRCRx_INIT;
			VCRDMA0 <= VCRDMAx_INIT;
			VCRDMA1 <= VCRDMAx_INIT;
			DMAOR <= DMAOR_INIT;
			// synopsys translate_off
			DMAOR.DME <= 1;
			// synopsys translate_on
		end
		else if (CE_R) begin
			if (!RES_N) begin
				DRCR[0] <= DRCRx_INIT;
				DRCR[1] <= DRCRx_INIT;
				VCRDMA0 <= VCRDMAx_INIT;
				VCRDMA1 <= VCRDMAx_INIT;
				DMAOR <= DMAOR_INIT;
				// synopsys translate_off
				DMAOR.DME <= 1;
				// synopsys translate_on
			end
			else if (REG1_SEL && IBUS_WE && IBUS_REQ) begin
`ifdef CUT_MSH_DMAC_DREQ_IE
				if (IBUS_BA[2] && !CUT_DREQ_IE) DRCR[0] <= IBUS_DI[23:16] & DRCRx_WMASK;	//U4 CUT_DREQ_IE: DRCR not writable
				if (IBUS_BA[1] && !CUT_DREQ_IE) DRCR[1] <= IBUS_DI[15: 8] & DRCRx_WMASK;
`else
				if (IBUS_BA[2]) DRCR[0] <= IBUS_DI[23:16] & DRCRx_WMASK;
				if (IBUS_BA[1]) DRCR[1] <= IBUS_DI[15: 8] & DRCRx_WMASK;
`endif
			end
			else if (REG2_SEL && IBUS_WE && IBUS_REQ) begin
				case ({IBUS_A[5:2],2'b00})
					6'h20: VCRDMA0 <= IBUS_DI & VCRDMAx_WMASK;
					6'h28: VCRDMA1 <= IBUS_DI & VCRDMAx_WMASK;
					6'h30: begin
						DMAOR[31:3] <= IBUS_DI[31:3] & DMAOR_WMASK[31:3];
						DMAOR[2:1]  <= DMAOR[2:1] & IBUS_DI[2:1];
						DMAOR[0]    <= IBUS_DI[0] & DMAOR_WMASK[0];
					end
					default:;
				endcase
			end
			
			if (!NMI_N) DMAOR.NMIF <= 1;
		end
	end
	
	bit [31:0] REG_DO;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			REG_DO <= '0;
		end
		else if (CE_F) begin
			if (REG1_SEL && !IBUS_WE && IBUS_REQ) begin
				REG_DO <= {8'h00,DRCR[0] & DRCRx_RMASK,DRCR[1] & DRCRx_RMASK,8'h00};
			end
			else if (REG2_SEL && !IBUS_WE && IBUS_REQ) begin
				case ({IBUS_A[5:2],2'b00})
					6'h00: REG_DO <= SAR[0];
					6'h04: REG_DO <= DAR[0];
					6'h08: REG_DO <= {8'h00,TCR[0]};
					6'h0C: REG_DO <= CHCR[0] & CHCRx_RMASK;
					6'h10: REG_DO <= SAR[1];
					6'h14: REG_DO <= DAR[1];
					6'h18: REG_DO <= {8'h00,TCR[1]};
					6'h1C: REG_DO <= CHCR[1] & CHCRx_RMASK;
					6'h20: REG_DO <= VCRDMA0 & VCRDMAx_RMASK;
					6'h28: REG_DO <= VCRDMA1 & VCRDMAx_RMASK;
					6'h30: REG_DO <= DMAOR & DMAOR_RMASK;
					default:REG_DO <= '0;
				endcase
			end
		end
	end
	
	assign IBUS_DO = REG1_SEL || REG2_SEL ? REG_DO : '0;
	assign IBUS_ACT = REG1_SEL | REG2_SEL;
	

endmodule
`ifdef U3_DMAC
`undef U3_DMAC
`endif

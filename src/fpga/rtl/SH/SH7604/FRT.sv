`ifdef CUT_SSH_FRT_OC
`define U3_FRT
`elsif CUT_SSH_FRT_FICR
`define U3_FRT
`endif
`ifdef CUT_MSH_FRT_FICR
// U4: the master's FICR cut is U3's CUT_FICR (CUT_OC = 0 there)
`ifndef U3_FRT
`define U3_FRT
`endif
`endif
`ifdef U3_FRT
module SH7604_FRT #(parameter bit CUT_OC=0, bit CUT_FICR=0) (	//U3, the slave only: see U3_OCRA below
`else
module SH7604_FRT (
`endif
	input             CLK,
	input             RST_N,
	input             CE_R,
	input             CE_F,
	input             EN,
	
	input             RES_N,
	input             SBY,
	
	output reg        FTOA,
	output reg        FTOB,
	input             FTCI,
	input             FTI,
	
	input             CLK4_CE,
	input             CLK8_CE,
	input             CLK32_CE,
	input             CLK128_CE,
	
	input      [31:0] IBUS_A,
	input      [31:0] IBUS_DI,
	output     [31:0] IBUS_DO,
	input       [3:0] IBUS_BA,
	input             IBUS_WE,
	input             IBUS_REQ,
	output            IBUS_BUSY,
	output            IBUS_ACT,
	
	output            ICI_IRQ,
	output            OCIA_IRQ,
	output            OCIB_IRQ,
	output            OVI_IRQ
);

	import SH7604_PKG::*;
	
	FRC_t       FRC;
	OCR_t       OCRA;
	OCR_t       OCRB;
	FICR_t      ICR;
	TIER_t      TIER;
	FTCSR_t     FTCSR;
	TCR_t       TCR;
	TOCR_t      TOCR;
	
`ifdef U3_FRT
	// U3 (the slave only; 0 = as before). CUT_OC (CUT_SSH_FRT_OC): OCRA, OCRB, TCR and TOCR keep their reset values
	// (writes ignored, reads return them), TIER.OCIAE / OCIBE / OVIE stay 0: FRC counts at phi/8, input capture on the
	// falling edge, compare match A and B and the overflow at FRC = FFFF; the OCFA / OCFB / OVF flags and CCLRA as
	// before; no OCIA / OCIB / OVI interrupt; an OCR high-byte write no longer loads TEMP. CUT_FICR (CUT_SSH_FRT_FICR):
	// FICR is not kept: a capture only sets ICF, and FICR reads return 0 (the high-byte read also loads TEMP with 0),
	// i.e. the FRT behaves as if FICR were stuck at 0 (a FICR read still holds off a capture for a clock, as before).
	wire [15:0] U3_OCRA = CUT_OC ? OCR_INIT : OCRA;
	wire [15:0] U3_OCRB = CUT_OC ? OCR_INIT : OCRB;
	TCR_t       U3_TCR;
	TOCR_t      U3_TOCR;
	assign U3_TCR  = CUT_OC ? TCR_INIT  : TCR;
	assign U3_TOCR = CUT_OC ? TOCR_INIT : TOCR;
	localparam bit [7:0] U3_TIER_WMASK = TIER_WMASK & (CUT_OC ? 8'hF1 : 8'hFF);

`endif
`ifdef CUT_MSH_FRT_FICR
	// U4 CUT_MSH_FRT_FICR: SH7604.sv gives the master CUT_FICR too (with CUT_OC = 0): the FICR cut above. The master never
	// read FICR in any run (BIOS boot, BIOS menus, every game; work/usage logs); its input captures (ICF, the ICI
	// interrupt, the FTCSR polls) and the output compare / overflow functions are kept.
`endif
	//Clock selector
	bit         FTCI_OLD;
	always @(posedge CLK) begin
		FTCI_OLD <= FTCI;
	end
	
	bit         FRC_CE;
	always_comb begin
`ifdef U3_FRT
		case (U3_TCR.CKS)
`else
		case (TCR.CKS)
`endif
			2'b00: FRC_CE = CLK8_CE;
			2'b01: FRC_CE = CLK32_CE;
			2'b10: FRC_CE = CLK128_CE;
			2'b11: FRC_CE = FTCI & ~FTCI_OLD;
		endcase
	end
	
	wire REG_SEL = (IBUS_A >= 32'hFFFFFE10 && IBUS_A <= 32'hFFFFFE19);
	wire FTCSR_WRITE = REG_SEL && IBUS_A[3:0] == 4'h1 && IBUS_WE && IBUS_REQ;
	wire FTCSR_READ = REG_SEL && IBUS_A[3:0] == 4'h1 && !IBUS_WE && IBUS_REQ;
	always @(posedge CLK or negedge RST_N) begin
		bit         OCFA_SET,OCFB_SET,OVF_SET;
		
		if (!RST_N) begin
			FTCSR.OCFA <= 0;
			FTCSR.OCFB <= 0;
			FTCSR.OVF <= 0;
		end
		else if (CE_F) begin
			if (!RES_N) begin
				{OCFA_SET,OCFB_SET,OVF_SET} <= '0;
			end else if (EN) begin
				if (FTCSR_READ) begin
					if (FTCSR.OCFA) OCFA_SET <= 1;
					if (FTCSR.OCFB) OCFB_SET <= 1;
					if (FTCSR.OVF) OVF_SET <= 1;
				end
			end
		end
		else if (CE_R) begin
			if (!RES_N || SBY) begin
				FTCSR.OCFA <= 0;
				FTCSR.OCFB <= 0;
				FTCSR.OVF <= 0;
			end else if (EN) begin
				if (FRC_CE) begin
`ifdef U3_FRT
					if (FRC == U3_OCRA) begin
						FTOA <= U3_TOCR.OLVLA;
						FTCSR.OCFA <= 1;
					end
					if (FRC == U3_OCRB) begin
						FTOB <= U3_TOCR.OLVLB;
						FTCSR.OCFB <= 1;
					end
`else
					if (FRC == OCRA) begin
						FTOA <= TOCR.OLVLA;
						FTCSR.OCFA <= 1;
					end
					if (FRC == OCRB) begin
						FTOB <= TOCR.OLVLB;
						FTCSR.OCFB <= 1;
					end
`endif
					
					if (FRC == 16'hFFFF) begin
						FTCSR.OVF <= 1;
					end
				end
				
				if (FTCSR_WRITE) begin
					if (!IBUS_DI[19] && OCFA_SET && FTCSR.OCFA) begin FTCSR.OCFA <= 0; OCFA_SET <= 0; end
					if (!IBUS_DI[18] && OCFB_SET && FTCSR.OCFB) begin FTCSR.OCFB <= 0; OCFB_SET <= 0; end
					if (!IBUS_DI[17] && OVF_SET  && FTCSR.OVF ) begin FTCSR.OVF <= 0;  OVF_SET <= 0; end
				end
			end
		end
	end
	
	wire ICR_READ = REG_SEL && IBUS_A[3:0] == 4'h9 && !IBUS_WE && IBUS_REQ;
	always @(posedge CLK or negedge RST_N) begin
		bit         CAPT;
		bit         FTI_OLD;
		bit         ICR_READ_OLD;
		bit         ICF_SET;
		
		if (!RST_N) begin
			ICR <= 16'h0000;
			FTCSR.ICF <= 0;
			CAPT <= 0;
			FTI_OLD <= 0;
			ICR_READ_OLD <= 0;
		end
		else if (CE_F) begin
			if (!RES_N) begin
				ICF_SET <= 0;
			end else if (EN) begin
				if (FTCSR_READ) begin
					if (FTCSR.ICF) ICF_SET <= 1;
				end
			end
		end
		else if (CE_R) begin
			if (!RES_N || SBY) begin
				ICR <= 16'h0000;
				FTCSR.ICF <= 0;
				CAPT <= 0;
				FTI_OLD <= 0;
				ICR_READ_OLD <= 0;
			end else if (EN) begin
				FTI_OLD <= FTI;
`ifdef U3_FRT
				CAPT <= ~(FTI ^ U3_TCR.IEDG) & (FTI_OLD ^ U3_TCR.IEDG);
`else
				CAPT <= ~(FTI ^ TCR.IEDG) & (FTI_OLD ^ TCR.IEDG);
`endif
				
				ICR_READ_OLD <= ICR_READ;
				if (ICR_READ && !ICR_READ_OLD && CAPT) begin
					CAPT <= 1;
				end
				else if (CAPT) begin
					ICR <= FRC;
					FTCSR.ICF <= 1;
				end
				
				if (FTCSR_WRITE) begin
					if (!IBUS_DI[23] && ICF_SET && FTCSR.ICF) begin FTCSR.ICF <= 0; ICF_SET <= 0; end
				end
			end
		end
	end

	
	assign ICI_IRQ = FTCSR.ICF & TIER.ICIE;
	assign OCIA_IRQ = FTCSR.OCFA & TIER.OCIAE;
	assign OCIB_IRQ = FTCSR.OCFB & TIER.OCIBE;
	assign OVI_IRQ = FTCSR.OVF & TIER.OVIE;
	
	//Registers
	bit [ 7: 0] TEMP;
	bit [ 7: 0] REG_DO;
	bit         BUSY;
	always @(posedge CLK or negedge RST_N) begin
		bit [15: 0] OCR;
		
		if (!RST_N) begin
			TIER <= TIER_INIT;
			FRC  <= FRC_INIT;
			OCRA <= OCR_INIT;
			OCRB <= OCR_INIT;
			TCR  <= TCR_INIT;
			TOCR <= TOCR_INIT;
			FTCSR.CCLRA <= 0;
			FTCSR.UNUSED <= '0;
			REG_DO <= '0;
			BUSY <= 0;
			// synopsys translate_off
			TEMP <= 8'h00;
			// synopsys translate_on
		end
		else if (CE_R) begin
			if (FRC_CE) begin
				FRC <= FRC + 16'd1;
			end
			
			if (!RES_N || SBY) begin
				TIER <= TIER_INIT;
				FRC  <= FRC_INIT;
				OCRA <= OCR_INIT;
				OCRB <= OCR_INIT;
				TCR  <= TCR_INIT;
				TOCR <= TOCR_INIT;
				FTCSR.CCLRA <= 0;
				FTCSR.UNUSED <= '0;
			end
			else if (REG_SEL && IBUS_WE && IBUS_REQ) begin
				case (IBUS_A[3:0])
`ifdef U3_FRT
					4'h0: TIER <= IBUS_DI[31:24] & U3_TIER_WMASK;
`else
					4'h0: TIER <= IBUS_DI[31:24] & TIER_WMASK;
`endif
					4'h1: FTCSR.CCLRA <= IBUS_DI[16];
					4'h2: TEMP <= IBUS_DI[15:8];
					4'h3: FRC <= {TEMP,IBUS_DI[7:0]} & FRC_WMASK;
`ifdef U3_FRT
					4'h4: if (!CUT_OC) TEMP <= IBUS_DI[31:24];
`else
					4'h4: TEMP <= IBUS_DI[31:24];
`endif
					4'h5: if (!TOCR.OCRS) OCRA <= {TEMP,IBUS_DI[23:16]} & OCR_WMASK; 
					      else OCRB <= {TEMP,IBUS_DI[23:16]} & OCR_WMASK;
					4'h6: TCR <= IBUS_DI[15:8] & TCR_WMASK;
					4'h7: TOCR <= (IBUS_DI[7:0] & TOCR_WMASK);
					default:;
				endcase
			end
			
`ifdef U3_FRT
			if (FRC == U3_OCRA && FTCSR.CCLRA && FRC_CE) begin
`else
			if (FRC == OCRA && FTCSR.CCLRA && FRC_CE) begin
`endif
				FRC <= 16'h0000;
			end
		end
		else if (CE_F) begin
			if (REG_SEL && !IBUS_WE && IBUS_REQ) begin
`ifdef U3_FRT
				OCR = !U3_TOCR.OCRS ? U3_OCRA : U3_OCRB;
`else
				OCR = !TOCR.OCRS ? OCRA : OCRB;
`endif
				case (IBUS_A[3:0])
					4'h0:       REG_DO <= (TIER | 8'h01) & TIER_RMASK;
					4'h1:       REG_DO <= FTCSR & FTCSR_RMASK; 
					4'h2: begin {REG_DO,TEMP} <= FRC; BUSY <= 1; end
					4'h3:       REG_DO <= TEMP; 
					4'h4:       REG_DO <= OCR[15:8];
					4'h5:       REG_DO <= OCR[7:0];
`ifdef U3_FRT
					4'h6:       REG_DO <= U3_TCR & TCR_RMASK;
`else
					4'h6:       REG_DO <= TCR & TCR_RMASK;
`endif
`ifdef U3_FRT
					4'h7:       REG_DO <= (U3_TOCR | 8'hE0) & TOCR_RMASK;
`else
					4'h7:       REG_DO <= (TOCR | 8'hE0) & TOCR_RMASK;
`endif
`ifdef U3_FRT
					4'h8:       {REG_DO,TEMP} <= CUT_FICR ? 16'h0000 : ICR;
`else
					4'h8:       {REG_DO,TEMP} <= ICR;
`endif
					4'h9:       REG_DO <= TEMP; 
					default:;
				endcase
			end
			
			if (CLK4_CE && BUSY) BUSY <= 0;
		end
	end
	
	assign IBUS_DO = REG_SEL ? {4{REG_DO}} : '0;
	assign IBUS_BUSY = BUSY;
	assign IBUS_ACT = REG_SEL;
	
endmodule
`ifdef U3_FRT
`undef U3_FRT
`endif

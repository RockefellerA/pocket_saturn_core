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
`define U4_INTC
`elsif CUT_MSH_DMAC_DREQ_IE
`define U4_INTC
`endif
`ifdef U4_INTC
// U4: the master's don't-care codes extend U3's decode (U3's parameters 0 there)
`ifndef U3_INTC
`define U3_INTC
`endif
`endif
module SH7604_INTC
#(parameter bit NO_UBC_BSC_IRQ=0,	//UBC_IRQ and BSC_IRQ are constant 0 (SH7604: UBC.sv drives 0, BSC_IRQ is tied 0)
`ifdef U3_INTC
            bit NO_SCI_IRQ=0,		//the SCI requests are constant 0 (SH7604 with SCI_DISABLE: SCR stays 0)
            bit CUT_VECMD=0,		//U3 CUT_SSH_VECMD (the slave only): ICR.VECMD stays 0, see ICR
            bit NO_INT_4_7=0,		//U3 (the slave only): DIVU, DMAC0/1 and WDT never request (codes 4-7), see lvl_short
`ifdef U4_INTC
            bit NO_FRT_OCOV=0,		//U3 (the slave only): FRT OCI and OVI never request (codes 14, 15), see vec_short
            bit NO_INT_4_6=0)		//U4 (the master only): DIVU and DMAC0/1 never request (codes 4-6; the WDT's 7 can), see lvl_short
`else
            bit NO_FRT_OCOV=0)		//U3 (the slave only): FRT OCI and OVI never request (codes 14, 15), see vec_short
`endif
`else
            bit NO_SCI_IRQ=0)		//the SCI requests are constant 0 (SH7604 with SCI_DISABLE: SCR stays 0)
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
	
	input       [3:0] INT_MASK,
	input             INT_ACK,
	input             INT_ACP,
	output reg  [3:0] INT_LVL,
	output reg  [7:0] INT_VEC,
	output            INT_REQ,
	output            INT_REQ_NEXT,	//INT_REQ's value in the next clock (INT_ACTIVE's input)
	
	input             VECT_REQ,
	output            VECT_WAIT,
	
	output reg        NMI_REQ,
	
	input      [31:0] IBUS_A,
	input      [31:0] IBUS_DI,
	output     [31:0] IBUS_DO,
	input       [3:0] IBUS_BA,
	input             IBUS_WE,
	input             IBUS_REQ,
	output            IBUS_BUSY,
	output            IBUS_ACT,
	
	output      [3:0] VBUS_A,
	input       [7:0] VBUS_DI,
	output            VBUS_REQ,
	input             VBUS_WAIT,
	
	input             UBC_IRQ,
	input             DIVU_IRQ,
	input       [7:0] DIVU_VEC,
	input             DMAC0_IRQ,
	input       [7:0] DMAC0_VEC,
	input             DMAC1_IRQ,
	input       [7:0] DMAC1_VEC,
	input             WDT_IRQ,
	input             BSC_IRQ,
	input             SCI_ERI_IRQ,
	input             SCI_RXI_IRQ,
	input             SCI_TXI_IRQ,
	input             SCI_TEI_IRQ,
	input             FRT_ICI_IRQ,
	input             FRT_OCI_IRQ,
	input             FRT_OVI_IRQ
);

	import SH7604_PKG::*;
	
	ICR_t      ICR;
	IPRA_t     IPRA;
	IPRB_t     IPRB;
	VCRWDT_t   VCRWDT;
	VCRA_t     VCRA;
	VCRB_t     VCRB;
	VCRC_t     VCRC;
	VCRD_t     VCRD;
	
	const bit [ 3:0] NMI_INT     = 4'd1;
	const bit [ 3:0] UBC_INT     = 4'd2;
	const bit [ 3:0] IRL_INT     = 4'd3; 
	const bit [ 3:0] DIVU_INT    = 4'd4;
	const bit [ 3:0] DMAC0_INT   = 4'd5;
	const bit [ 3:0] DMAC1_INT   = 4'd6;
	const bit [ 3:0] WDT_INT     = 4'd7;
	const bit [ 3:0] BSC_INT     = 4'd8;
	const bit [ 3:0] SCI_ERI_INT = 4'd9;
	const bit [ 3:0] SCI_RXI_INT = 4'd10;
	const bit [ 3:0] SCI_TXI_INT = 4'd11;
	const bit [ 3:0] SCI_TEI_INT = 4'd12;
	const bit [ 3:0] FRT_ICI_INT = 4'd13;
	const bit [ 3:0] FRT_OCI_INT = 4'd14;
	const bit [ 3:0] FRT_OVI_INT = 4'd15;
	
	bit        IRL_REQ;
	bit [ 3:0] IRL_LVL;
	bit [ 3:0] INT_ACTIVE;
	bit [ 3:0] INT_ACCEPTED;
	
	always @(posedge CLK or negedge RST_N) begin
		bit NMI_N_OLD;
		
		if (!RST_N) begin
			NMI_REQ <= 0;
		end
		else if (!RES_N) begin	
			NMI_REQ <= 0;
		end
		else if (EN && CE_R) begin	
			NMI_N_OLD <= NMI_N;
			if (!(NMI_N ^ ICR.NMIE) && (NMI_N_OLD ^ ICR.NMIE) && !NMI_REQ) begin
				NMI_REQ <= 1;
			end
			else if (INT_ACP && NMI_REQ) begin
				NMI_REQ <= 0;
			end
		end
	end
	
	always @(posedge CLK or negedge RST_N) begin
		bit [3:0] IRL_OLD[4];
		bit [3:0] IRL_NORM;
		
		if (!RST_N) begin
			IRL_OLD <= '{4{'1}};
			IRL_NORM <= '0;
		end
		else if (!RES_N) begin	
			IRL_OLD <= '{4{'1}};
			IRL_NORM <= '0;
		end
		else if (EN && CE_R) begin	
			IRL_OLD[0] <= ~IRL_N;
			IRL_OLD[1] <= IRL_OLD[0];
			IRL_OLD[2] <= IRL_OLD[1];
			IRL_OLD[3] <= IRL_OLD[2];
			if (IRL_OLD[0] == ~IRL_N && IRL_OLD[1] == ~IRL_N && IRL_OLD[2] == ~IRL_N && IRL_OLD[3] == ~IRL_N) begin
				IRL_LVL <= ~IRL_N;
				IRL_NORM <= ~IRL_N;
			end else begin
				IRL_LVL <= IRL_NORM;
			end
		end
	end
	assign IRL_REQ = |IRL_LVL; 
	
	bit  [ 3: 0] INT;
	always_comb begin
		bit  [ 4: 0] IP[7];
		
		IP = '{7{5'd0}};
		INT = '0;
		
		if ( NMI_REQ                                                                                                          ) begin 
			IP[0] = 5'd16; IP[1] = 5'd16; IP[2] = 5'd16; IP[3] = 5'd16; IP[4] = 5'd16; IP[5] = 5'd16; IP[6] = 5'd16;
			INT = NMI_INT; 
		end
		if ( UBC_IRQ                                                   && 4'd15       > INT_MASK && 5'd15              > IP[0]) begin 
			IP[1] = 5'd15; IP[2] = 5'd15; IP[3] = 5'd15; IP[4] = 5'd15; IP[5] = 5'd15; IP[6] = 5'd15;
			INT = UBC_INT; 
		end
		if ( IRL_REQ                                                   && IRL_LVL     > INT_MASK && {1'b0,IRL_LVL}     > IP[1]) begin 
			IP[2] = {1'b0,IRL_LVL}; IP[3] = {1'b0,IRL_LVL}; IP[4] = {1'b0,IRL_LVL}; IP[5] = {1'b0,IRL_LVL}; IP[6] = {1'b0,IRL_LVL};
			INT = IRL_INT; 
		end
		if ( DIVU_IRQ                                                  && IPRA.DIVUIP > INT_MASK && {1'b0,IPRA.DIVUIP} > IP[2]) begin 
			IP[3] = {1'b0,IPRA.DIVUIP};  IP[4] = {1'b0,IPRA.DIVUIP}; IP[5] = {1'b0,IPRA.DIVUIP}; IP[6] = {1'b0,IPRA.DIVUIP};
			INT = DIVU_INT; 
		end
		if ((DMAC0_IRQ   || DMAC1_IRQ                                ) && IPRA.DMACIP > INT_MASK && {1'b0,IPRA.DMACIP} > IP[3]) begin 
			IP[4] = {1'b0,IPRA.DMACIP}; IP[5] = {1'b0,IPRA.DMACIP}; IP[6] = {1'b0,IPRA.DMACIP};
			INT = DMAC0_IRQ ? DMAC0_INT : DMAC1_INT; 
		end
		if ((WDT_IRQ     || BSC_IRQ                                  ) && IPRA.WDTIP  > INT_MASK && {1'b0,IPRA.WDTIP}  > IP[4]) begin 
			IP[5] = {1'b0,IPRA.WDTIP}; IP[6] = {1'b0,IPRA.WDTIP};
			INT = WDT_IRQ ? WDT_INT : BSC_INT; 
		end
		if ((SCI_ERI_IRQ || SCI_RXI_IRQ || SCI_TXI_IRQ || SCI_TEI_IRQ) && IPRB.SCIIP  > INT_MASK && {1'b0,IPRB.SCIIP}  > IP[5]) begin 
			IP[6] = {1'b0,IPRB.SCIIP};
			INT = SCI_ERI_IRQ ? SCI_ERI_INT : SCI_RXI_IRQ ? SCI_RXI_INT : SCI_TXI_IRQ ? SCI_TXI_INT : SCI_TEI_INT; 
		end
		if ((FRT_ICI_IRQ || FRT_OCI_IRQ || FRT_OVI_IRQ               ) && IPRB.FRTIP  > INT_MASK && {1'b0,IPRB.FRTIP}  > IP[6]) begin
			INT = FRT_ICI_IRQ ? FRT_ICI_INT : FRT_OCI_IRQ ? FRT_OCI_INT : FRT_OVI_INT; 
		end
		
	end
	always @(posedge CLK) INT_ACTIVE <= INT;
	assign INT_REQ = |INT_ACTIVE;
	assign INT_REQ_NEXT = |INT;
	
	// INT_ACTIVE and INT_ACCEPTED only take codes of sources that can request (INT_ACTIVE <= INT every clock, power-up 0;
	// INT_ACCEPTED takes INT_ACTIVE or 0). With NO_UBC_BSC_IRQ and NO_SCI_IRQ, UBC_INT (2), BSC_INT (8) and SCI_*_INT
	// (9-12) never occur, so their entries are don't-cares: below they share the neighbouring entries, which needs fewer
	// decode terms (1xxx: FRT, by bits 1:0; 001x: IRL).
`ifdef U3_INTC
	// U3 (the slave only): with NO_INT_4_7 (SH7604.sv: CUT_WDT, CUT_DMAC_MODES and CUT_DIVU_OVF together, so the WDT,
	// DMAC and DIVU requests are constant 0) the codes 4-7 never occur either, so bit 2 is a don't-care below the FRT
	// codes and the 0xx entries serve 1xx; with NO_FRT_OCOV (CUT_FRT_OC: OCIAE, OCIBE, OVIE stay 0) 14 and 15 never
	// occur, so 1xxx is FRT_ICI (13) only.
`endif
`ifdef U4_INTC
	// U4 (the master only): with NO_INT_4_6 (SH7604.sv: CUT_DIVU_OVF and CUT_DMAC_DREQ_IE together, so the DIVU and the
	// DMAC requests are constant 0; the WDT's interval interrupt stays) the codes 4-6 never occur, so a code 1xx is the
	// WDT's 7: bits 1:0 are don't-cares there and are taken as 11 below.
`endif
generate if (NO_UBC_BSC_IRQ && NO_SCI_IRQ) begin : lvl_short
	always_comb begin
		if (INT_ACTIVE[3]) INT_LVL = IPRB.FRTIP;				//FRT_ICI/OCI/OVI (13-15)
`ifdef U3_INTC
`ifdef U4_INTC
		else case ({INT_ACTIVE[2] & ~NO_INT_4_7, INT_ACTIVE[1:0] | {2{INT_ACTIVE[2] & NO_INT_4_6}}})
`else
		else case ({INT_ACTIVE[2] & ~NO_INT_4_7, INT_ACTIVE[1:0]})
`endif
`else
		else case (INT_ACTIVE[2:0])
`endif
			3'd1:        INT_LVL = 4'hF;					//NMI
			3'd2, 3'd3:  INT_LVL = IRL_LVL;					//IRL (3)
			3'd4:        INT_LVL = IPRA.DIVUIP;
			3'd5, 3'd6:  INT_LVL = IPRA.DMACIP;
			3'd7:        INT_LVL = IPRA.WDTIP;
			default:     INT_LVL = 4'h0;
		endcase
	end
end else begin : lvl_full
	always_comb begin
		case (INT_ACTIVE)
			NMI_INT:     INT_LVL = 4'hF;
			UBC_INT:     INT_LVL = 4'hF;
			IRL_INT:     INT_LVL = IRL_LVL;
			DIVU_INT:    INT_LVL = IPRA.DIVUIP;
			DMAC0_INT:   INT_LVL = IPRA.DMACIP;
			DMAC1_INT:   INT_LVL = IPRA.DMACIP;
			WDT_INT:     INT_LVL = IPRA.WDTIP;
			BSC_INT:     INT_LVL = IPRA.WDTIP;
			SCI_ERI_INT: INT_LVL = IPRB.SCIIP;
			SCI_RXI_INT: INT_LVL = IPRB.SCIIP;
			SCI_TXI_INT: INT_LVL = IPRB.SCIIP;
			SCI_TEI_INT: INT_LVL = IPRB.SCIIP;
			FRT_ICI_INT: INT_LVL = IPRB.FRTIP;
			FRT_OCI_INT: INT_LVL = IPRB.FRTIP;
			FRT_OVI_INT: INT_LVL = IPRB.FRTIP;
			default:     INT_LVL = 4'h0;
		endcase
	end
end endgenerate
	
	bit  [ 3: 0] IRL_LVL_SAVE;
	wire [ 7: 0] IRL_VEC = !ICR.VECMD ? {5'b01000,IRL_LVL_SAVE[3:1]} : VBUS_DI;
generate if (NO_UBC_BSC_IRQ && NO_SCI_IRQ) begin : vec_short
	always_comb begin
`ifdef U3_INTC
		if (INT_ACCEPTED[3]) INT_VEC = {1'b0, !INT_ACCEPTED[1] || NO_FRT_OCOV ? VCRC.FICV : !INT_ACCEPTED[0] ? VCRC.FOCV : VCRD.FOVV};	//13-15
`else
		if (INT_ACCEPTED[3]) INT_VEC = {1'b0, !INT_ACCEPTED[1] ? VCRC.FICV : !INT_ACCEPTED[0] ? VCRC.FOCV : VCRD.FOVV};	//13-15
`endif
`ifdef U3_INTC
`ifdef U4_INTC
		else case ({INT_ACCEPTED[2] & ~NO_INT_4_7, INT_ACCEPTED[1:0] | {2{INT_ACCEPTED[2] & NO_INT_4_6}}})
`else
		else case ({INT_ACCEPTED[2] & ~NO_INT_4_7, INT_ACCEPTED[1:0]})
`endif
`else
		else case (INT_ACCEPTED[2:0])
`endif
			3'd1:        INT_VEC = 8'd11;					//NMI
			3'd2, 3'd3:  INT_VEC = IRL_VEC;					//IRL (3)
			3'd4:        INT_VEC = DIVU_VEC;
			3'd5:        INT_VEC = DMAC0_VEC;
			3'd6:        INT_VEC = DMAC1_VEC;
			3'd7:        INT_VEC = {1'b0,VCRWDT.WITV};
			default:     INT_VEC = 8'd0;
		endcase
	end
end else begin : vec_full
	always_comb begin
		case (INT_ACCEPTED)
			NMI_INT:     INT_VEC = 8'd11;
			UBC_INT:     INT_VEC = 8'd12;
			IRL_INT:     INT_VEC = IRL_VEC;
			DIVU_INT:    INT_VEC = DIVU_VEC;
			DMAC0_INT:   INT_VEC = DMAC0_VEC;
			DMAC1_INT:   INT_VEC = DMAC1_VEC;
			WDT_INT:     INT_VEC = {1'b0,VCRWDT.WITV};
			BSC_INT:     INT_VEC = {1'b0,VCRWDT.BCMV};
			SCI_ERI_INT: INT_VEC = {1'b0,VCRA.SERV};
			SCI_RXI_INT: INT_VEC = {1'b0,VCRA.SRXV};
			SCI_TXI_INT: INT_VEC = {1'b0,VCRB.STXV};
			SCI_TEI_INT: INT_VEC = {1'b0,VCRB.STEV};
			FRT_ICI_INT: INT_VEC = {1'b0,VCRC.FICV};
			FRT_OCI_INT: INT_VEC = {1'b0,VCRC.FOCV};
			FRT_OVI_INT: INT_VEC = {1'b0,VCRD.FOVV};
			default:     INT_VEC = 8'd0;
		endcase
	end
end endgenerate
	
	bit [3:0] VBA;
	bit       VBREQ;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			VBREQ <= 0;
			VBA <= '0;
			INT_ACCEPTED <= '0;
		end else if (EN && CE_F) begin	
			if (VECT_REQ && !VBREQ) begin
				VBREQ <= 1;
				VBA <= INT_MASK;
			end else if (VBREQ && !VBUS_WAIT) begin
				VBREQ <= 0;
			end
		end else if (EN && CE_R) begin	
			if (INT_ACP) begin 
				INT_ACCEPTED <= INT_ACTIVE; 
				IRL_LVL_SAVE <= IRL_LVL; 
			end
			if (INT_ACK) INT_ACCEPTED <= '0;
		end
	end
	assign VECT_WAIT = VBREQ;
	
	assign VBUS_A   = VBA;
	assign VBUS_REQ = VBREQ && INT_ACCEPTED == IRL_INT && ICR.VECMD;
	
	
	//Registers
	wire REG_SEL = (IBUS_A >= 32'hFFFFFE60 & IBUS_A <= 32'hFFFFFE69) | (IBUS_A >= 32'hFFFFFEE0 & IBUS_A <= 32'hFFFFFEE5);
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			ICR    <= ICR_INIT;
			IPRA   <= IPRA_INIT;
			IPRB   <= IPRB_INIT;
			VCRWDT <= VCRWDT_INIT;
			VCRA   <= VCRA_INIT;
			VCRB   <= VCRB_INIT;
			VCRC   <= VCRC_INIT;
			VCRD   <= VCRD_INIT;
		end
		else if (CE_R) begin
			if (!RES_N) begin
				ICR    <= ICR_INIT;
				IPRA   <= IPRA_INIT;
				IPRB   <= IPRB_INIT;
				VCRWDT <= VCRWDT_INIT;
				VCRA   <= VCRA_INIT;
				VCRB   <= VCRB_INIT;
				VCRC   <= VCRC_INIT;
				VCRD   <= VCRD_INIT;
				ICR.NMIL <= NMI_N;
			end
			else begin
				if (REG_SEL && IBUS_WE && IBUS_REQ) begin
					case ({IBUS_A[7:1],1'b0})
						8'h60: begin
							if (IBUS_BA[3]) IPRB[15:8] = IBUS_DI[31:24] & IPRB_WMASK[15:8];
							if (IBUS_BA[2]) IPRB[ 7:0] = IBUS_DI[23:16] & IPRB_WMASK[ 7:0];
						end
						8'h62: begin
							if (IBUS_BA[1]) VCRA[15:8] = IBUS_DI[15:8] & VCRA_WMASK[15:8];
							if (IBUS_BA[0]) VCRA[ 7:0] = IBUS_DI[ 7:0] & VCRA_WMASK[ 7:0];
						end
						8'h64: begin
							if (IBUS_BA[3]) VCRB[15:8] = IBUS_DI[31:24] & VCRB_WMASK[15:8];
							if (IBUS_BA[2]) VCRB[ 7:0] = IBUS_DI[23:16] & VCRB_WMASK[ 7:0];
						end
						8'h66: begin
							if (IBUS_BA[1]) VCRC[15:8] = IBUS_DI[15:8] & VCRC_WMASK[15:8];
							if (IBUS_BA[0]) VCRC[ 7:0] = IBUS_DI[ 7:0] & VCRC_WMASK[ 7:0];
						end
						8'h68: begin
							if (IBUS_BA[3]) VCRD[15:8] = IBUS_DI[31:24] & VCRD_WMASK[15:8];
							if (IBUS_BA[2]) VCRD[ 7:0] = IBUS_DI[23:16] & VCRD_WMASK[ 7:0];
						end
						8'hE0: begin
							if (IBUS_BA[3]) ICR[15:8] = IBUS_DI[31:24] & ICR_WMASK[15:8];
`ifdef CUT_SSH_VECMD
							// U3 CUT_VECMD: VECMD is written as 0 (reads 0): IRL interrupts are always auto-vectored, no vector fetch
							// cycle (VBUS_REQ stays 0); the slave only ever wrote ICR = 0 (work/usage logs).
							if (IBUS_BA[2]) ICR[ 7:0] = IBUS_DI[23:16] & ICR_WMASK[ 7:0] & {7'h7F, ~CUT_VECMD};
`else
							if (IBUS_BA[2]) ICR[ 7:0] = IBUS_DI[23:16] & ICR_WMASK[ 7:0];
`endif
						end
						8'hE2: begin
							if (IBUS_BA[1]) IPRA[15:8] = IBUS_DI[15:8] & IPRA_WMASK[15:8];
							if (IBUS_BA[0]) IPRA[ 7:0] = IBUS_DI[ 7:0] & IPRA_WMASK[ 7:0];
						end
						8'hE4: begin
							if (IBUS_BA[3]) VCRWDT[15:8] = IBUS_DI[31:24] & VCRWDT_WMASK[15:8];
							if (IBUS_BA[2]) VCRWDT[ 7:0] = IBUS_DI[23:16] & VCRWDT_WMASK[ 7:0];
						end
						default:;
					endcase
				end
				ICR.NMIL <= NMI_N;
			end
		end
	end
	
	bit [31:0] BUS_DO;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			BUS_DO <= '0;
		end
		else if (CE_F) begin
			if (REG_SEL && !IBUS_WE && IBUS_REQ) begin
				case ({IBUS_A[7:1],1'b0})
					8'h60: BUS_DO <= {2{IPRB & IPRB_RMASK}};
					8'h62: BUS_DO <= {2{VCRA & VCRA_RMASK}};
					8'h64: BUS_DO <= {2{VCRB & VCRB_RMASK}};
					8'h66: BUS_DO <= {2{VCRC & VCRC_RMASK}};
					8'h68: BUS_DO <= {2{VCRD & VCRD_RMASK}};
					8'hE0: BUS_DO <= {2{ICR & ICR_RMASK}};
					8'hE2: BUS_DO <= {2{IPRA & IPRA_RMASK}};
					8'hE4: BUS_DO <= {2{VCRWDT & VCRWDT_RMASK}};
					default:BUS_DO <= '0;
				endcase
			end
		end
	end
	
	assign IBUS_DO = BUS_DO;
	assign IBUS_BUSY = 0;
	assign IBUS_ACT = REG_SEL;

endmodule
`ifdef U3_INTC
`undef U3_INTC
`endif
`ifdef U4_INTC
`undef U4_INTC
`endif

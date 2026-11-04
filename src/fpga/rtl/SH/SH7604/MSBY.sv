`ifdef CUT_SSH_SBY
`define U3_SBY
`elsif CUT_SSH_WDT
`define U3_SBY
`endif
`ifdef U3_SBY
module SH7604_MSBY #(parameter bit CUT_SBY=0) (	//U3 CUT_SSH_SBY / CUT_SSH_WDT (the slave only): SBYCR.SBY stays 0, see SBYCR
`else
module SH7604_MSBY (
`endif
	input             CLK,
	input             RST_N,
	input             CE_R,
	input             CE_F,
	input             EN,
	
	input             RES_N,
	
	input      [31:0] IBUS_A,
	input      [31:0] IBUS_DI,
	output     [31:0] IBUS_DO,
	input       [3:0] IBUS_BA,
	input             IBUS_WE,
	input             IBUS_REQ,
	output            IBUS_BUSY,
	output            IBUS_ACT,
	
	input             SLEEP,
	input             WDT_OVF,
	output reg        SBY
);

	import SH7604_PKG::*;
	
	SBYCR_t     SBYCR;
	
	wire REG_SEL = (IBUS_A == 32'hFFFFFE91);
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			SBYCR <= SBYCR_INIT;
			// synopsys translate_off
			// synopsys translate_on
		end
		else if (EN && CE_R) begin
			if (REG_SEL && IBUS_WE && IBUS_REQ) begin
`ifdef U3_SBY
				// U3 CUT_SBY (SH7604.sv: CUT_SSH_SBY or CUT_SSH_WDT): SBY is written as 0: SLEEP never enters standby (SBY stays 0).
				// With the WDT cut standby could not end (the exit is NMI -> WDT count -> WDT_OVF), so CUT_SSH_WDT sets it too.
				// SBYCR is not read back in this SH7604 (IBUS_DO of this module is not on the read bus); the slave never wrote
				// SBYCR (work/usage logs).
				SBYCR <= IBUS_DI[23:16] & SBYCR_WMASK & {~CUT_SBY, 7'h7F};
`else
				SBYCR <= IBUS_DI[23:16] & SBYCR_WMASK;
`endif
			end
		end
	end
	
	always @(posedge CLK or negedge RST_N) begin
		bit          SLEEP_OLD;
		
		if (!RST_N) begin
			SBY <= 0;
		end
		else if (EN && CE_R) begin
			SLEEP_OLD <= SLEEP;
			if (SLEEP && !SLEEP_OLD && SBYCR.SBY) begin
				SBY <= 1;
			end
			if (WDT_OVF && SBY) begin
				SBY <= 0;
			end
		end
	end
//	assign SBY = SBYCR.SBY;
	
	bit [31:0] REG_DO;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			REG_DO <= '0;
		end
		else if (CE_F) begin
			if (REG_SEL && !IBUS_WE && IBUS_REQ) begin
				REG_DO <= {4{SBYCR & SBYCR_RMASK}};
			end
		end
	end
	
	assign IBUS_DO = REG_SEL ? REG_DO : 32'h00000000;
	assign IBUS_BUSY = 0;
	assign IBUS_ACT = REG_SEL;
	
endmodule
`ifdef U3_SBY
`undef U3_SBY
`endif

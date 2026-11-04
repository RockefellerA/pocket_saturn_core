module SH2_regfile (
	input             CLK,
	input             RST_N,
	input             CE,
	input             EN,
	
	input       [4:0] WA_ADDR,
	input      [31:0] WA_D,
	input             WAE,
	input       [4:0] WB_ADDR,
	input      [31:0] WB_D,
	input             WBE,
	
	input       [4:0] RA_ADDR,
	output     [31:0] RA_Q,
	input       [4:0] RB_ADDR,
	output     [31:0] RB_Q,
	output     [31:0] R0_Q

`ifdef DEBUG
	                  ,
	output     [31:0] R0,
	output     [31:0] R1,
	output     [31:0] R2,
	output     [31:0] R3,
	output     [31:0] R4,
	output     [31:0] R5,
	output     [31:0] R6,
	output     [31:0] R7,
	output     [31:0] R8,
	output     [31:0] R9,
	output     [31:0] R10,
	output     [31:0] R11,
	output     [31:0] R12,
	output     [31:0] R13,
	output     [31:0] R14,
	output     [31:0] R15,
	output     [31:0] PR_
`endif
);
	
	// synopsys translate_off
	`define SIM
	// synopsys translate_on
	
`ifdef SIM

	reg [31:0]  GR[16+1];
	
	bit  [4:0] WB_ADDR_LATCH;
	bit [31:0] WB_D_LATCH;
	bit        WBE_LATCH;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			WB_ADDR_LATCH <= '0;
			WB_D_LATCH <= '0;
			WBE_LATCH <= 0;
		end
		else begin
			WBE_LATCH <= 0;
			if (CE) begin
				WB_ADDR_LATCH <= WB_ADDR;
				WB_D_LATCH <= WB_D;
				WBE_LATCH <= WBE;
			end
		end
	end
	
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			GR <= '{'h01234567,'h11111111,'h89ABCDEF,'h11111111,'0,'0,'0,'0,'0,'0,'0,'0,'0,'0,'0,'0,'0};
		end
		else if (EN) begin
			if (WAE && CE) begin
				GR[WA_ADDR] <= WA_D;
			end
			if (WBE_LATCH) begin
				GR[WB_ADDR_LATCH] <= WB_D_LATCH;
			end
		end
	end

	assign RA_Q = GR[RA_ADDR];
	assign RB_Q = GR[RB_ADDR];
	
	reg [31:0] GR0;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			GR0 <= '0;
		end
		else if (EN) begin
			if (WAE && (WA_ADDR == 5'd0) && CE) begin
				GR0 <= WA_D;
			end
			if (WBE_LATCH && (WB_ADDR_LATCH == 5'd0)) begin
				GR0 <= WB_D_LATCH;
			end
		end
	end
	
	assign R0_Q = GR0;
	
`else
	
	bit  [4:0] WB_ADDR_LATCH;
	bit [31:0] WB_D_LATCH;
	bit        WBE_LATCH;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			WB_ADDR_LATCH <= '0;
			WB_D_LATCH <= '0;
			WBE_LATCH <= 0;
		end
		else begin
			WBE_LATCH <= 0;
			if (CE) begin
				WB_ADDR_LATCH <= WB_ADDR;
				WB_D_LATCH <= WB_D;
				WBE_LATCH <= WBE;
			end
		end
	end
	
	// The A and B write ports share one MLAB write port: port A writes in CE clocks, port B (latched) in the clock
	// after, which is never a CE clock (CE_R and CE_F alternate). PR is word 16 of the 32-word MLABs (a 32-bit MLAB
	// RAM is 32 words deep anyway), so no PR register and no PR read muxes; R0's copy for the third read port is
	// written from the same port. (PR is not cleared by RST_N any more: like R0-R15 in the MLABs, it keeps its value
	// over a reset without reconfiguration; the SH-2's PR is undefined after reset.)
	wire  [4:0] W_ADDR = CE ? WA_ADDR : WB_ADDR_LATCH;
	wire [31:0] REG_D = CE ? WA_D : WB_D_LATCH;
	wire        REG_WE = (WAE & CE) | WBE_LATCH;
	SH_regram32 regramA(.clock(CLK), .wraddress(W_ADDR), .data(REG_D), .wren(REG_WE & EN), .rdaddress(RA_ADDR), .q(RA_Q));
	SH_regram32 regramB(.clock(CLK), .wraddress(W_ADDR), .data(REG_D), .wren(REG_WE & EN), .rdaddress(RB_ADDR), .q(RB_Q));

	bit  [31:0] GR0;
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			GR0 <= '0;
		end
		else if (EN) begin
			if (REG_WE && W_ADDR == 5'd0) begin
				GR0 <= REG_D;
			end
		end
	end
	assign R0_Q = GR0;
`endif

`ifdef DEBUG
	reg [31:0] DBG_GR[17];
	always @(posedge CLK or negedge RST_N) begin
		if (!RST_N) begin
			DBG_GR <= '{17{'0}};
		end
		else if (EN) begin
			if (WAE && CE) begin
				DBG_GR[WA_ADDR] <= WA_D;
			end
			if (WBE_LATCH) begin
				DBG_GR[WB_ADDR_LATCH] <= WB_D_LATCH;
			end
		end
	end
	
	assign R0 = DBG_GR[0];
	assign R1 = DBG_GR[1];
	assign R2 = DBG_GR[2];
	assign R3 = DBG_GR[3];
	assign R4 = DBG_GR[4];
	assign R5 = DBG_GR[5];
	assign R6 = DBG_GR[6];
	assign R7 = DBG_GR[7];
	assign R8 = DBG_GR[8];
	assign R9 = DBG_GR[9];
	assign R10 = DBG_GR[10];
	assign R11 = DBG_GR[11];
	assign R12 = DBG_GR[12];
	assign R13 = DBG_GR[13];
	assign R14 = DBG_GR[14];
	assign R15 = DBG_GR[15];
	assign PR_ = DBG_GR[16];
`endif
	
endmodule

// 32 x 32 MLAB, asynchronous read (as SH_regram, 5-bit address)
module SH_regram32 (
	input         clock,
	input  [31:0] data,
	input   [4:0] rdaddress,
	input   [4:0] wraddress,
	input         wren,
	output [31:0] q
);
	altdpram	altdpram_component (
				.data (data),
				.inclock (clock),
				.rdaddress (rdaddress),
				.wraddress (wraddress),
				.wren (wren),
				.q (q),
				.aclr (1'b0),
				.byteena (1'b1),
				.inclocken (1'b1),
				.rdaddressstall (1'b0),
				.rden (1'b1),
				.wraddressstall (1'b0));
	defparam
		altdpram_component.indata_aclr = "OFF",
		altdpram_component.indata_reg = "INCLOCK",
		altdpram_component.intended_device_family = "Cyclone V",
		altdpram_component.lpm_type = "altdpram",
		altdpram_component.outdata_aclr = "OFF",
		altdpram_component.outdata_reg = "UNREGISTERED",
		altdpram_component.ram_block_type = "MLAB",
		altdpram_component.rdaddress_aclr = "OFF",
		altdpram_component.rdaddress_reg = "UNREGISTERED",
		altdpram_component.rdcontrol_aclr = "OFF",
		altdpram_component.rdcontrol_reg = "UNREGISTERED",
		altdpram_component.read_during_write_mode_mixed_ports = "CONSTRAINED_DONT_CARE",
		altdpram_component.width = 32,
		altdpram_component.widthad = 5,
		altdpram_component.width_byteena = 1,
		altdpram_component.wraddress_aclr = "OFF",
		altdpram_component.wraddress_reg = "INCLOCK",
		altdpram_component.wrcontrol_aclr = "OFF",
		altdpram_component.wrcontrol_reg = "INCLOCK";
endmodule

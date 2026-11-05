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

`ifdef FRESH_SH2_REGM10K
// FRESH_SH2_REGM10K (fresh-eyes review, sh2 item 1): the register file's two read-port copies in M10K blocks instead of
// MLABs (an MLAB costs a whole LAB however small: 4 LABs for the two cores' files). An M10K read is synchronous, and
// the read index (the decoder row's RA.N / RB.N) exists only in the ID clock, so the read is registered at the END of
// the ID clock (RD_EN) and the block's output then IS the pipeline's EX.RA / EX.RB register: it holds while RD_EN is 0
// (the M10K read enable), and a write at the read edge returns the old word (OLD_DATA), as the MLAB's asynchronous read
// in the ID clock did not see that edge's write either. The core zeroes the operands after a soft reset itself
// (SH_core: PIPE.EX.RA <= 0 on RES_N; here a one-bit flag). Same single write port as SH2_regfile: port A in CE clocks,
// the latched port B in the clock after. Not for DEBUG builds (their register view reads the file at DBG_REGN).
module SH2_regfile_m10k (
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
	input       [4:0] RB_ADDR,
	input             RD_EN,		//read RA_ADDR / RB_ADDR at the edge ending this clock; otherwise RA_Q / RB_Q hold
	output     [31:0] RA_Q,
	output     [31:0] RB_Q,
	output     [31:0] R0_Q
);
	
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
	
	wire  [4:0] W_ADDR = CE ? WA_ADDR : WB_ADDR_LATCH;
	wire [31:0] REG_D = CE ? WA_D : WB_D_LATCH;
	wire        REG_WE = (WAE & CE) | WBE_LATCH;
	SH_regram32_m10k regramA(.clock(CLK), .wraddress(W_ADDR), .data(REG_D), .wren(REG_WE & EN), .rdaddress(RA_ADDR), .rden(RD_EN), .q(RA_Q));
	SH_regram32_m10k regramB(.clock(CLK), .wraddress(W_ADDR), .data(REG_D), .wren(REG_WE & EN), .rdaddress(RB_ADDR), .rden(RD_EN), .q(RB_Q));

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
	
endmodule

// 32 x 32 M10K, synchronous read with read enable (the output holds while rden is 0), old data on a read of the word
// written at the same edge
module SH_regram32_m10k (
	input         clock,
	input  [31:0] data,
	input   [4:0] rdaddress,
	input   [4:0] wraddress,
	input         wren,
	input         rden,
	output [31:0] q
);
	altsyncram	altsyncram_component (
				.address_a (wraddress),
				.address_b (rdaddress),
				.clock0 (clock),
				.data_a (data),
				.wren_a (wren),
				.rden_b (rden),
				.q_b (q),
				.aclr0 (1'b0),
				.aclr1 (1'b0),
				.addressstall_a (1'b0),
				.addressstall_b (1'b0),
				.byteena_a (1'b1),
				.byteena_b (1'b1),
				.clock1 (1'b1),
				.clocken0 (1'b1),
				.clocken1 (1'b1),
				.clocken2 (1'b1),
				.clocken3 (1'b1),
				.data_b ({32{1'b1}}),
				.eccstatus (),
				.q_a (),
				.rden_a (1'b1),
				.wren_b (1'b0));
	defparam
		altsyncram_component.address_aclr_b = "NONE",
		altsyncram_component.address_reg_b = "CLOCK0",
		altsyncram_component.rdcontrol_reg_b = "CLOCK0",
		altsyncram_component.clock_enable_input_a = "BYPASS",
		altsyncram_component.clock_enable_input_b = "BYPASS",
		altsyncram_component.clock_enable_output_b = "BYPASS",
		altsyncram_component.intended_device_family = "Cyclone V",
		altsyncram_component.lpm_type = "altsyncram",
		altsyncram_component.numwords_a = 32,
		altsyncram_component.numwords_b = 32,
		altsyncram_component.operation_mode = "DUAL_PORT",
		altsyncram_component.outdata_aclr_b = "NONE",
		altsyncram_component.outdata_reg_b = "UNREGISTERED",
		altsyncram_component.power_up_uninitialized = "FALSE",
		altsyncram_component.ram_block_type = "M10K",
		altsyncram_component.read_during_write_mode_mixed_ports = "OLD_DATA",
		altsyncram_component.widthad_a = 5,
		altsyncram_component.widthad_b = 5,
		altsyncram_component.width_a = 32,
		altsyncram_component.width_b = 32,
		altsyncram_component.width_byteena_a = 1;
endmodule
`endif

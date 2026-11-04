module HMCS400_ROM
#(
	parameter rom_file = " "
)
(
	input          CLK,
	input  [10: 0] ADDR,
	output [ 9: 0] Q
);

// synopsys translate_off
`define SIM
// synopsys translate_on
	
`ifdef SIM

	reg [9:0] MEM [2**11];
	initial begin
		$readmemh(rom_file, MEM);
	end
	
	assign Q = MEM[ADDR];

`else

	wire [9:0] sub_wire0;
		
	altsyncram	altsyncram_component (
				.address_a (ADDR),
				.clock0 (CLK),
				.q_a (sub_wire0),
				.aclr0 (1'b0),
				.aclr1 (1'b0),
				.address_b (1'b1),
				.addressstall_a (1'b0),
				.addressstall_b (1'b0),
				.byteena_a (1'b1),
				.byteena_b (1'b1),
				.clock1 (1'b1),
				.clocken0 (1'b1),
				.clocken1 (1'b1),
				.clocken2 (1'b1),
				.clocken3 (1'b1),
				.data_a ({10{1'b1}}),
				.data_b (1'b1),
				.eccstatus (),
				.q_b (),
				.rden_a (1'b1),
				.rden_b (1'b1),
				.wren_a (1'b0),
				.wren_b (1'b0));
	defparam
		altsyncram_component.address_aclr_a = "NONE",
		altsyncram_component.clock_enable_input_a = "BYPASS",
		altsyncram_component.clock_enable_output_a = "BYPASS",
		altsyncram_component.init_file = rom_file,
		altsyncram_component.intended_device_family = "Cyclone V",
		altsyncram_component.lpm_hint = "ENABLE_RUNTIME_MOD=NO",
		altsyncram_component.lpm_type = "altsyncram",
		altsyncram_component.numwords_a = 2**11,
		altsyncram_component.operation_mode = "ROM",
		altsyncram_component.outdata_aclr_a = "NONE",
		altsyncram_component.outdata_reg_a = "UNREGISTERED",
		altsyncram_component.widthad_a = 11,
		altsyncram_component.width_a = 10,
		altsyncram_component.width_byteena_a = 1;

		
	assign Q = sub_wire0;
	
`endif

endmodule 

// The 16 x 16 stack (four nibble lanes) as four 16 x 4 M10Ks. The read address is registered on the rising clock edge
// and the output is not, so Q is MEM[ADDR] as of the previous clock (the MLAB version read it asynchronously). That is
// the same value whenever the core uses it: the core uses memory data only on CYC[3] CE edges; the address (BUS_A)
// changes only on CYC[1] and CYC[3] CE edges and the contents only on CYC[3] CE edges, so at least one other clock
// edge (the CYC[2] CE edge, or more) comes between any change and the next use, and there the M10K registers the
// current address and reads the current contents. This holds for any SMPC_CE timing.
module HMCS400_STACK (
	input          CLK,
	input  [ 5: 2] ADDR,
	input  [15: 0] DATA,
	input  [ 3: 0] WREN,
	output [15: 0] Q
);

	SMPC_RAM #(4,4,0) LANE3(CLK, ADDR, DATA[15:12], WREN[3], ADDR, Q[15:12]);
	SMPC_RAM #(4,4,0) LANE2(CLK, ADDR, DATA[11: 8], WREN[2], ADDR, Q[11: 8]);
	SMPC_RAM #(4,4,0) LANE1(CLK, ADDR, DATA[ 7: 4], WREN[1], ADDR, Q[ 7: 4]);
	SMPC_RAM #(4,4,0) LANE0(CLK, ADDR, DATA[ 3: 0], WREN[0], ADDR, Q[ 3: 0]);

endmodule 

// Simple dual-port M10K: written on the rising clock edge; the read address is registered on the rising (RD_NEG = 0)
// or the falling (RD_NEG = 1) clock edge and the output is not registered. With RD_NEG = 1, Q seen on a rising edge is
// MEM[RADDR] after the writes of the previous rising edge, for RADDR as it was during the clock before: exactly what an
// asynchronously read MLAB gives a logic that samples on rising edges (the SCU DSP's data RAMs work this way).
module SMPC_RAM
#(
	parameter AW = 4,
	parameter DW = 4,
	parameter RD_NEG = 0
)
(
	input           CLK,
	input  [AW-1:0] WADDR,
	input  [DW-1:0] DATA,
	input           WREN,
	input  [AW-1:0] RADDR,
	output [DW-1:0] Q
);

	altsyncram	altsyncram_component (
				.address_a (WADDR),
				.clock0 (CLK),
				.data_a (DATA),
				.wren_a (WREN),
				.address_b (RADDR),
				.clock1 (RD_NEG ? ~CLK : 1'b1),
				.q_b (Q),
				.aclr0 (1'b0),
				.aclr1 (1'b0),
				.addressstall_a (1'b0),
				.addressstall_b (1'b0),
				.byteena_a (1'b1),
				.byteena_b (1'b1),
				.clocken0 (1'b1),
				.clocken1 (1'b1),
				.clocken2 (1'b1),
				.clocken3 (1'b1),
				.data_b ({DW{1'b1}}),
				.eccstatus (),
				.q_a (),
				.rden_a (1'b1),
				.rden_b (1'b1),
				.wren_b (1'b0));
	defparam
		altsyncram_component.address_aclr_b = "NONE",
		altsyncram_component.address_reg_b = RD_NEG ? "CLOCK1" : "CLOCK0",
		altsyncram_component.clock_enable_input_a = "BYPASS",
		altsyncram_component.clock_enable_input_b = "BYPASS",
		altsyncram_component.clock_enable_output_b = "BYPASS",
		altsyncram_component.intended_device_family = "Cyclone V",
		altsyncram_component.lpm_type = "altsyncram",
		altsyncram_component.numwords_a = 2**AW,
		altsyncram_component.numwords_b = 2**AW,
		altsyncram_component.operation_mode = "DUAL_PORT",
		altsyncram_component.outdata_aclr_b = "NONE",
		altsyncram_component.outdata_reg_b = "UNREGISTERED",
		altsyncram_component.power_up_uninitialized = "FALSE",
		altsyncram_component.ram_block_type = "M10K",
		altsyncram_component.read_during_write_mode_mixed_ports = "DONT_CARE",
		altsyncram_component.widthad_a = AW,
		altsyncram_component.widthad_b = AW,
		altsyncram_component.width_a = DW,
		altsyncram_component.width_b = DW,
		altsyncram_component.width_byteena_a = 1;

endmodule 

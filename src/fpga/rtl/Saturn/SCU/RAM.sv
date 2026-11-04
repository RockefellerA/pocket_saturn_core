// synopsys translate_off
`define SIM
// synopsys translate_on

// The DSP program RAM as a true dual-port M10K: port A is read at the program counter and written by the CPU (PPD),
// port B (same address, same clock) is written by DSP DMA. The two writes never come together (DMA writes only while
// T0, CPU writes only while not T0), so DATA_A and DATA_B need no multiplexer. The read word is only used (loaded into
// IC) at the end of a DSP CE clock, a CE_R clock; the RAM reads it on the rising edge that starts that clock, which
// ends a CE_F clock, and writes happen only on edges that end CE_R clocks. So a read that comes with a write (whose
// result depends on the read-during-write mode) is never used.
module DSP_PRG_RAM
#(
	parameter addr_width = 8,
	parameter data_width = 8,
	parameter mem_init_file = " ",
	parameter mem_sim_file = " "
)
(
	input                   CLK,
	
	input  [addr_width-1:0] ADDR,
	input  [data_width-1:0] DATA_A,
	input                   WREN_A,
	input  [data_width-1:0] DATA_B,
	input                   WREN_B,
	output [data_width-1:0] Q
);

	altsyncram	altsyncram_component (
				.address_a (ADDR),
				.clock0 (CLK),
				.data_a (DATA_A),
				.wren_a (WREN_A),
				.q_a (Q),
				.address_b (ADDR),
				.data_b (DATA_B),
				.wren_b (WREN_B),
				.q_b (),
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
				.eccstatus (),
				.rden_a (1'b1),
				.rden_b (1'b1));

	defparam
		altsyncram_component.address_reg_b = "CLOCK0",
		altsyncram_component.clock_enable_input_a = "BYPASS",
		altsyncram_component.clock_enable_input_b = "BYPASS",
		altsyncram_component.clock_enable_output_a = "BYPASS",
		altsyncram_component.clock_enable_output_b = "BYPASS",
		altsyncram_component.indata_reg_b = "CLOCK0",
		altsyncram_component.intended_device_family = "Cyclone V",
		altsyncram_component.lpm_hint = "ENABLE_RUNTIME_MOD=NO",
		altsyncram_component.lpm_type = "altsyncram",
		altsyncram_component.numwords_a = 2**addr_width,
		altsyncram_component.numwords_b = 2**addr_width,
		altsyncram_component.operation_mode = "BIDIR_DUAL_PORT",
		altsyncram_component.outdata_aclr_a = "NONE",
		altsyncram_component.outdata_aclr_b = "NONE",
		altsyncram_component.outdata_reg_a = "UNREGISTERED",
		altsyncram_component.outdata_reg_b = "UNREGISTERED",
		altsyncram_component.power_up_uninitialized = "FALSE",
		altsyncram_component.ram_block_type = "M10K",
		altsyncram_component.read_during_write_mode_mixed_ports = "DONT_CARE",
		altsyncram_component.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
		altsyncram_component.read_during_write_mode_port_b = "NEW_DATA_NO_NBE_READ",
		altsyncram_component.widthad_a = addr_width,
		altsyncram_component.widthad_b = addr_width,
		altsyncram_component.width_a = data_width,
		altsyncram_component.width_b = data_width,
		altsyncram_component.width_byteena_a = 1,
		altsyncram_component.width_byteena_b = 1,
		altsyncram_component.wrcontrol_wraddress_reg_b = "CLOCK0";
	
endmodule


// A DSP data RAM as a true dual-port M10K. Port A, on the rising clock edge, takes the DSP (D1 bus) and CPU (PDD)
// writes; port B, on the falling clock edge, reads (as before: the address is registered on the falling edge, the
// output is not) and takes the DSP DMA writes. A DMA write so lands half a clock earlier than when it shared port A:
// on the falling edge before the rising edge it used to land on. From the next falling edge on every read sees the
// new word, as before. A DMA write and a port A write to the same RAM never come in the same clock (port A writes
// only while T0 && RAMW is not set for this RAM, port B only while it is), and writes decided in different clocks
// keep their order, so every read returns what it used to, except the read on the falling edge of the DMA write
// itself, which used to return the old word (M10K true dual-port mode cannot: port B gives the new word here). That
// read is never used: a DMA write happens only in a CE_R clock; reads taken at the end of a CE_F clock (the CPU's PDD
// read, DMA_DO) come from the falling edge of that CE_F clock; reads taken at the end of a CE_R clock (X / Y / D1 bus,
// the DMA count) are taken only on a DSP CE with RUN, and RUN is off (PAUSED) while T0 is set and the instruction
// touches the DMA's RAM (PAUSED is updated at the end of every CE_F clock from the current instruction, so it holds
// at every DSP CE). DATA_A and DATA_B need no multiplexer.
module DSP_DATA_RAM
#(
	parameter addr_width = 8,
	parameter data_width = 8,
	parameter mem_init_file = " ",
	parameter mem_sim_file = " "
)
(
	input                   CLK,
	
	input  [addr_width-1:0] ADDR,
	input  [data_width-1:0] DATA_A,
	input                   WREN_A,
	input  [data_width-1:0] DATA_B,
	input                   WREN_B,
	output [data_width-1:0] Q
);

	altsyncram	altsyncram_component (
				.address_a (ADDR),
				.clock0 (CLK),
				.data_a (DATA_A),
				.wren_a (WREN_A),
				.q_a (),
				.address_b (ADDR),
				.clock1 (~CLK),
				.data_b (DATA_B),
				.wren_b (WREN_B),
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
				.eccstatus (),
				.rden_a (1'b1),
				.rden_b (1'b1));
	defparam
		altsyncram_component.address_aclr_b = "NONE",
		altsyncram_component.address_reg_b = "CLOCK1",
		altsyncram_component.clock_enable_input_a = "BYPASS",
		altsyncram_component.clock_enable_input_b = "BYPASS",
		altsyncram_component.clock_enable_output_a = "BYPASS",
		altsyncram_component.clock_enable_output_b = "BYPASS",
		altsyncram_component.indata_reg_b = "CLOCK1",
		altsyncram_component.intended_device_family = "Cyclone V",
		altsyncram_component.lpm_type = "altsyncram",
		altsyncram_component.numwords_a = 2**addr_width,
		altsyncram_component.numwords_b = 2**addr_width,
		altsyncram_component.operation_mode = "BIDIR_DUAL_PORT",
		altsyncram_component.outdata_aclr_a = "NONE",
		altsyncram_component.outdata_aclr_b = "NONE",
		altsyncram_component.outdata_reg_a = "UNREGISTERED",
		altsyncram_component.outdata_reg_b = "UNREGISTERED",
		altsyncram_component.power_up_uninitialized = "FALSE",
		altsyncram_component.ram_block_type = "M10K",
		altsyncram_component.read_during_write_mode_mixed_ports = "DONT_CARE",
		altsyncram_component.read_during_write_mode_port_a = "NEW_DATA_NO_NBE_READ",
		altsyncram_component.read_during_write_mode_port_b = "NEW_DATA_NO_NBE_READ",
		altsyncram_component.widthad_a = addr_width,
		altsyncram_component.widthad_b = addr_width,
		altsyncram_component.width_a = data_width,
		altsyncram_component.width_b = data_width,
		altsyncram_component.width_byteena_a = 1,
		altsyncram_component.width_byteena_b = 1,
		altsyncram_component.wrcontrol_wraddress_reg_b = "CLOCK1";
	
endmodule


// The C-bus read cache (8 words) in an M10K instead of an MLAB: written on the rising edge as before, read with the
// address registered on the falling edge and the output not registered. The MLAB read was asynchronous: in every clock
// it gave the word at the current RADDR with every write up to the rising edge that started the clock. RADDR comes
// from rising-edge registers, so it is the same at the falling edge, which also comes after that write (writes happen
// only on rising edges): the logic that takes Q on the next rising edge gets the same word. Q is not used in any other
// way (it only feeds the DMA buffer write data, RD_DATA, which is registered).
module SCU_CBUS_CACHE
(
	input         CLK,
	
	input  [ 2:0] WADDR,
	input  [31:0] DATA,
	input         WREN,
	input  [ 2:0] RADDR,
	output [31:0] Q
);

	altsyncram	altsyncram_component (
				.address_a (WADDR),
				.clock0 (CLK),
				.data_a (DATA),
				.wren_a (WREN),
				.address_b (RADDR),
				.clock1 (~CLK),
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
				.data_b ({32{1'b1}}),
				.eccstatus (),
				.q_a (),
				.rden_a (1'b1),
				.rden_b (1'b1),
				.wren_b (1'b0));
	defparam
		altsyncram_component.address_aclr_b = "NONE",
		altsyncram_component.address_reg_b = "CLOCK1",
		altsyncram_component.clock_enable_input_a = "BYPASS",
		altsyncram_component.clock_enable_input_b = "BYPASS",
		altsyncram_component.clock_enable_output_b = "BYPASS",
		altsyncram_component.intended_device_family = "Cyclone V",
		altsyncram_component.lpm_type = "altsyncram",
		altsyncram_component.numwords_a = 8,
		altsyncram_component.numwords_b = 8,
		altsyncram_component.operation_mode = "DUAL_PORT",
		altsyncram_component.outdata_aclr_b = "NONE",
		altsyncram_component.outdata_reg_b = "UNREGISTERED",
		altsyncram_component.power_up_uninitialized = "FALSE",
		altsyncram_component.ram_block_type = "M10K",
		altsyncram_component.read_during_write_mode_mixed_ports = "DONT_CARE",
		altsyncram_component.widthad_a = 3,
		altsyncram_component.widthad_b = 3,
		altsyncram_component.width_a = 32,
		altsyncram_component.width_b = 32,
		altsyncram_component.width_byteena_a = 1;
	
endmodule

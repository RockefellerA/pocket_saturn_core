// Pocket CD disc source (glue/cd): the clock crossing to APF's command handler (core_bridge_cmd.v, clk_74a).
//
// - Data slot table reads: dt_rd (one clock, clk_sys) with dt_addr (held while dt_busy) reads datatable word dt_addr
//   (entry e = {id} at word 2e, {size in bytes} at word 2e + 1); dt_q is valid once dt_busy has fallen.
//   (core_bridge_cmd's mf_datatable port a, 2 clocks read latency: the value is taken 3 clocks after the address.)
// - Target command "data slot read" (0x0180): the caller holds target_dataslot_id / slotoffset / bridgeaddr / length
//   (clk_sys registers, read by core_bridge_cmd on clk_74a when the command starts: quasi-static) and pulses cmd_start;
//   cmd_busy until APF has finished (target_dataslot_done), cmd_err = target_dataslot_err then.
//   dsr_read follows sotn's pocket_cd: raised, dropped once done has fallen (the command was taken; done is 0 already
//   before the first command), then done rising ends the command.
// Toggle handshakes with two-register synchronisers both ways; one request of each kind at a time.
module cd_apf (
	input              clk,                // clk_sys
	input              dt_rd,
	input      [ 9: 0] dt_addr,
	output             dt_busy,
	output reg [31: 0] dt_q,               // (clk_74a register, stable while it is read)
	input              cmd_start,
	output             cmd_busy,
	output reg [ 2: 0] cmd_err,            // (clk_74a register)

	input              clk_74a,
	output reg [ 9: 0] datatable_addr,
	input      [31: 0] datatable_q,
	output reg         dsr_read,
	input              dsr_done,
	input      [ 2: 0] dsr_err
);
	// ---- clk_sys side
	reg        dt_req = 0, cmd_req = 0;
	reg  [1:0] dt_ack_s = 0, cmd_ack_s = 0;
	wire       dt_ack, cmd_ack;
	always @(posedge clk) begin
		dt_ack_s  <= {dt_ack_s[0], dt_ack};
		cmd_ack_s <= {cmd_ack_s[0], cmd_ack};
		if (dt_rd) dt_req <= ~dt_req;
		if (cmd_start) cmd_req <= ~cmd_req;
	end
	assign dt_busy  = dt_req != dt_ack_s[1];
	assign cmd_busy = cmd_req != cmd_ack_s[1];

	// ---- clk_74a side
	reg  [1:0] dt_req_s = 0, cmd_req_s = 0, done_s = 0;
	reg        dt_ack_r = 0, cmd_ack_r = 0;
	reg  [1:0] dt_cnt = 0;
	reg        dt_run = 0;
	reg  [1:0] c_st = 0;
	assign dt_ack = dt_ack_r;
	assign cmd_ack = cmd_ack_r;
	always @(posedge clk_74a) begin
		dt_req_s  <= {dt_req_s[0], dt_req};
		cmd_req_s <= {cmd_req_s[0], cmd_req};
		done_s    <= {done_s[0], dsr_done};

		if (!dt_run) begin
			if (dt_req_s[1] != dt_ack_r) begin datatable_addr <= dt_addr; dt_cnt <= 2'd0; dt_run <= 1; end
		end else begin
			dt_cnt <= dt_cnt + 2'd1;
			if (dt_cnt == 2'd3) begin dt_q <= datatable_q; dt_ack_r <= dt_req_s[1]; dt_run <= 0; end
		end

		case (c_st)
		2'd0: if (cmd_req_s[1] != cmd_ack_r) begin dsr_read <= 1; c_st <= 2'd1; end
		2'd1: if (!done_s[1]) begin dsr_read <= 0; c_st <= 2'd2; end          // taken
		2'd2: if (done_s[1]) begin cmd_err <= dsr_err; cmd_ack_r <= cmd_req_s[1]; c_st <= 2'd0; end
		default: c_st <= 2'd0;
		endcase
	end
	initial begin dsr_read = 0; datatable_addr = 0; end
endmodule

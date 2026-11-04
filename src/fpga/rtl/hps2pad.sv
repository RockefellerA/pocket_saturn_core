module HPS2PAD (
	output     [ 6: 0] PDR1I,
	input      [ 6: 0] PDR1O,
	input      [ 6: 0] DDR1,
	output     [ 6: 0] PDR2I,
	input      [ 6: 0] PDR2O,
	input      [ 6: 0] DDR2,
	
	input      [15: 0] JOY1
);

	// Port 1: digital pad. Port 2: nothing connected (inputs read back the pull-ups).
	always_comb begin
		PDR1I = (PDR1O & DDR1) | ~DDR1;
		if (DDR1[6:5] == 2'b10) begin
			case (PDR1O[6])
				1'b0:  PDR1I[3:0] = JOY1[15:12];
				1'b1:  PDR1I[3:0] = {JOY1[3],3'b100};
			endcase
		end else if (DDR1[6:5] == 2'b11) begin
			case (PDR1O[6:5])
				2'b00: PDR1I[3:0] = JOY1[ 7: 4];
				2'b01: PDR1I[3:0] = JOY1[15:12];
				2'b10: PDR1I[3:0] = JOY1[11: 8];
				2'b11: PDR1I[3:0] = {JOY1[3],3'b100};
			endcase
		end
		
		PDR2I = (PDR2O & DDR2) | ~DDR2;
	end
	
endmodule

// CW SOS FM Transmitter based on http://hamsterworks.co.nz/mediawiki/index.php/FM_SOS

module top(input clk, output clkin, modout, lock);

    wire clkout;

// PLL running at 255 MHz (near max 275 MHz) 
// Generated using icepll utility in icestorm package [ icepll -i 12 -o 255 ]

    SB_PLL40_CORE #(
        .FEEDBACK_PATH("SIMPLE"),
        .PLLOUT_SELECT("GENCLK"),
        .DIVR(4'b0000),
        .DIVF(7'b1010100),  // 255 MHz
        .DIVQ(3'b010),
        .FILTER_RANGE(3'b001)
    ) uut (
        .LOCK(lock),
        .RESETB(1'b1),
        .BYPASS(1'b0),
        .REFERENCECLK(clk),
        .PLLOUTCORE(clkout)
    );

    reg [31:0] phase_acc = 0;
    reg [19:0] beep_counter = 0;
    reg [4:0] shift_counter = 0;
    reg [33:0] message = 34'b1010100011101110111000101010000000;

    assign clkin = clk;
    wire modout = phase_acc[31];

    always @(posedge clkout)
    begin
	if (beep_counter == 20'hFFFFF)
	begin
		if (shift_counter == 5'b00000)
			message <= {message[0], message[33:1]};
		shift_counter <= shift_counter + 1;	
	end

	if (message[0] == 1'b1)
		if (beep_counter[19] == 1)
			phase_acc <= phase_acc + 1685564126;  // 100.075e6 / 255e6) * 2^32 
		else
			phase_acc <= phase_acc + 1683037674;  // (99.925e6 / 255e6) * 2^32  
	else
		phase_acc <= phase_acc + 1684300900;         // Carrier @ 100MHz
	
	beep_counter <= beep_counter + 1;		
    end

endmodule


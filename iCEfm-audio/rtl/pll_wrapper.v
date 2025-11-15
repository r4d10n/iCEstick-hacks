// Generic PLL Wrapper for Multiple FPGA Families
// Supports: iCE40-HX, iCE40-UP5K, ECP5
//
// This module provides a unified interface for different PLL primitives
// Define FPGA_FAMILY macro during synthesis:
//   - FPGA_ICE40HX  for iCE40 HX series
//   - FPGA_ICE40UP  for iCE40 UltraPlus series
//   - FPGA_ECP5     for Lattice ECP5 series
//
// Author: Based on iCEstick-hacks FM transmitter project
// License: MIT

module pll_wrapper #(
    parameter INPUT_FREQ_MHZ = 12,      // Input clock frequency in MHz
    parameter OUTPUT_FREQ_MHZ = 255     // Desired output frequency in MHz
)(
    input  wire clk_in,
    output wire clk_out,
    output wire locked
);

`ifdef FPGA_ICE40HX
    //--------------------------------------------------------------------
    // iCE40 HX Series PLL
    // Using SB_PLL40_CORE primitive
    //--------------------------------------------------------------------
    // For 12 MHz -> 255 MHz:
    // DIVR = 0 (input divider = 1)
    // DIVF = 84 (feedback divider = 85, giving 12MHz * 85 / 4 = 255 MHz)
    // DIVQ = 2 (output divider = 4)
    // Formula: Fout = Fin * (DIVF+1) / ((2^DIVQ) * (DIVR+1))

    SB_PLL40_CORE #(
        .FEEDBACK_PATH("SIMPLE"),
        .DIVR(4'b0000),         // DIVR = 0
        .DIVF(7'b1010100),      // DIVF = 84 (binary: 1010100)
        .DIVQ(3'b010),          // DIVQ = 2
        .FILTER_RANGE(3'b001)   // PLL filter range
    ) pll_inst (
        .REFERENCECLK(clk_in),
        .PLLOUTCORE(clk_out),
        .LOCK(locked),
        .RESETB(1'b1),
        .BYPASS(1'b0)
    );

`elsif FPGA_ICE40UP
    //--------------------------------------------------------------------
    // iCE40 UltraPlus Series PLL
    // Using SB_PLL40_2F_CORE or SB_PLL40_2_PAD primitive
    //--------------------------------------------------------------------
    // Similar to HX but with slightly different parameters
    // For 12 MHz -> 240 MHz (more conservative for UP5K):
    // DIVR = 0, DIVF = 79, DIVQ = 2
    // Fout = 12 * 80 / 4 = 240 MHz

    SB_PLL40_CORE #(
        .FEEDBACK_PATH("SIMPLE"),
        .DIVR(4'b0000),         // DIVR = 0
        .DIVF(7'b1001111),      // DIVF = 79 (12 * 80 / 4 = 240 MHz)
        .DIVQ(3'b010),          // DIVQ = 2
        .FILTER_RANGE(3'b001)
    ) pll_inst (
        .REFERENCECLK(clk_in),
        .PLLOUTCORE(clk_out),
        .LOCK(locked),
        .RESETB(1'b1),
        .BYPASS(1'b0)
    );

`elsif FPGA_ECP5
    //--------------------------------------------------------------------
    // Lattice ECP5 Series PLL
    // Using EHXPLLL primitive (High-speed PLL)
    //--------------------------------------------------------------------
    // For 12 MHz -> 255 MHz:
    // CLKI_DIV = 1, CLKFB_DIV = 1, CLKOP_DIV = 1
    // Multiply by 21.25 (not exact, using integer multiplication)
    // Using 12 MHz * 20 / 1 = 240 MHz for compatibility

    (* ICP_CURRENT="12" *)
    (* LPF_RESISTOR="8" *)
    EHXPLLL #(
        .PLLRST_ENA("DISABLED"),
        .INTFB_WAKE("DISABLED"),
        .STDBY_ENABLE("DISABLED"),
        .DPHASE_SOURCE("DISABLED"),
        .CLKOP_FPHASE(0),
        .CLKOP_CPHASE(0),
        .OUTDIVIDER_MUXA("DIVA"),
        .CLKOP_ENABLE("ENABLED"),
        .CLKOP_DIV(3),           // Output divider
        .CLKFB_DIV(20),          // Feedback divider
        .CLKI_DIV(1),            // Input divider
        .FEEDBK_PATH("CLKOP")
    ) pll_inst (
        .CLKI(clk_in),
        .CLKFB(clk_out),
        .CLKOP(clk_out),
        .RST(1'b0),
        .STDBY(1'b0),
        .PHASESEL0(1'b0),
        .PHASESEL1(1'b0),
        .PHASEDIR(1'b0),
        .PHASESTEP(1'b0),
        .PLLWAKESYNC(1'b0),
        .ENCLKOP(1'b1),
        .LOCK(locked)
    );

`else
    //--------------------------------------------------------------------
    // No PLL - Direct passthrough (for simulation or unsupported target)
    //--------------------------------------------------------------------
    assign clk_out = clk_in;
    assign locked = 1'b1;

    initial begin
        $display("WARNING: No FPGA family defined. PLL is bypassed.");
        $display("Define one of: FPGA_ICE40HX, FPGA_ICE40UP, FPGA_ECP5");
    end

`endif

endmodule

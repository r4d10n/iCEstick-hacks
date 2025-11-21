//-----------------------------------------------------------------------------
// Module: clock_doubler
//
// Description:
//   Generates a clock signal at approximately twice the input frequency using
//   an XOR-based edge detection technique. This creates pulses on both rising
//   and falling edges of the input clock.
//
// Theory of Operation:
//   The clock doubler XORs the input clock with a delayed version of itself.
//   When the clock transitions (either direction), there's a brief period where
//   clk and clk_delayed differ, producing a pulse.
//
//   Timing diagram:
//   clk:         ____/‾‾‾‾\____/‾‾‾‾\____
//   clk_delayed: ______/‾‾‾‾\____/‾‾‾‾\__
//   clk_2x:      ____/\__/\__/\__/\__/\__  (pulses at each edge)
//
// Implementation:
//   Uses a chain of inverters (or buffers) to create the delay. The delay
//   determines the pulse width of the doubled clock.
//
// Important Notes:
//   - Output duty cycle is NOT 50% - it produces narrow pulses
//   - Pulse width depends on inverter chain delay (technology dependent)
//   - For ASIC: adjust DELAY_STAGES based on gate delays
//   - Jitter will be present due to delay variation
//   - Use for DDS phase accumulator clocking, not for synchronous logic
//
// Usage:
//   - Enable via clk_2x_enable input
//   - When disabled, clk_out = clk_in (bypass mode)
//   - phase_increment_out allows monitoring the FM frequency
//
// Author: Based on iCEstick-hacks FM transmitter project
// Target: GF180MCU ASIC (architecture independent)
// License: MIT
//-----------------------------------------------------------------------------

module clock_doubler #(
    parameter DELAY_STAGES = 8    // Number of inverter stages for delay
                                  // Adjust based on technology
                                  // More stages = wider pulse width
)(
    input  wire clk_in,           // Input clock (~100 MHz)
    input  wire enable,           // Enable clock doubling
    output wire clk_out           // Output clock (2x when enabled, 1x when disabled)
);

    //-------------------------------------------------------------------------
    // Delay Chain
    //-------------------------------------------------------------------------
    // Create delayed version of clock using inverter chain
    // Each inverter adds gate delay (technology dependent)
    //
    // For GF180MCU (180nm), typical inverter delay ~0.1-0.2ns
    // 8 stages ≈ 0.8-1.6ns delay
    // This creates ~1ns pulse width at each clock edge

    (* keep = "true" *)  // Prevent optimization from removing delay chain
    wire [DELAY_STAGES:0] delay_chain;

    assign delay_chain[0] = clk_in;

    // Generate delay chain using inverters
    // Using NOT gates in pairs to maintain polarity
    genvar i;
    generate
        for (i = 0; i < DELAY_STAGES; i = i + 1) begin : delay_stage
            // Each stage is an inverter (adds delay)
            // Using (* keep *) to prevent optimization
            (* keep = "true" *)
            wire delayed;
            assign delayed = ~delay_chain[i];
            assign delay_chain[i+1] = ~delayed;  // Double invert to maintain polarity
        end
    endgenerate

    wire clk_delayed = delay_chain[DELAY_STAGES];

    //-------------------------------------------------------------------------
    // XOR-based Edge Detection
    //-------------------------------------------------------------------------
    // XOR produces a pulse whenever clk_in and clk_delayed differ
    // This happens briefly after each clock edge

    wire clk_doubled = clk_in ^ clk_delayed;

    //-------------------------------------------------------------------------
    // Output Multiplexer
    //-------------------------------------------------------------------------
    // Select between doubled clock and original clock

    assign clk_out = enable ? clk_doubled : clk_in;

endmodule


//-----------------------------------------------------------------------------
// Alternative: Latch-based Clock Doubler (more reliable duty cycle)
//-----------------------------------------------------------------------------
// This alternative uses latches to create a more stable doubled clock
// with better duty cycle, but requires more careful timing analysis.
//
// Note: Uncomment and use if XOR method proves unstable
//-----------------------------------------------------------------------------

/*
module clock_doubler_latch (
    input  wire clk_in,
    input  wire enable,
    output wire clk_out
);

    // Generate inverted clock
    wire clk_inv = ~clk_in;

    // XOR rising edges of both clocks
    // This effectively doubles the frequency with ~50% duty cycle
    // But requires both clock edges to be used

    reg toggle_a = 0;
    reg toggle_b = 0;

    always @(posedge clk_in) toggle_a <= ~toggle_a;
    always @(posedge clk_inv) toggle_b <= ~toggle_b;

    wire clk_doubled = toggle_a ^ toggle_b;

    assign clk_out = enable ? clk_doubled : clk_in;

endmodule
*/

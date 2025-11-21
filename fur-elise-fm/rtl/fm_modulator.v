//-----------------------------------------------------------------------------
// Module: fm_modulator
//
// Description:
//   Direct Digital Synthesis (DDS) based FM modulator. Uses a 32-bit phase
//   accumulator to generate an output signal at a frequency determined by
//   the phase increment input. The MSB of the accumulator provides a
//   square wave output at the desired frequency.
//
// Theory of Operation:
//   - Each clock cycle, phase_increment is added to a 32-bit accumulator
//   - The accumulator wraps around (overflows) naturally
//   - The MSB toggles at frequency = (phase_increment / 2^32) * clk_freq
//   - Output jitter is approximately 1 clock cycle (1/clk_freq seconds)
//
// Frequency Formula:
//   phase_increment = (desired_freq_hz / clock_freq_hz) * 2^32
//
// Example (100 MHz clock, 25 MHz output):
//   phase_increment = (25,000,000 / 100,000,000) * 4,294,967,296
//                   = 0.25 * 4,294,967,296
//                   = 1,073,741,824 (0x40000000)
//
// Design Notes:
//   - Architecture independent (pure behavioral Verilog)
//   - No vendor-specific primitives
//   - Single clock domain
//   - Fully synchronous design
//   - Suitable for ASIC synthesis (GF180MCU target)
//
// Author: Based on iCEstick-hacks FM transmitter project
// Target: GF180MCU ASIC (architecture independent)
// License: MIT
//-----------------------------------------------------------------------------

module fm_modulator #(
    parameter ACCUMULATOR_WIDTH = 32    // Phase accumulator bit width
)(
    input  wire                           clk,
    input  wire                           rst_n,
    input  wire                           enable,
    input  wire [ACCUMULATOR_WIDTH-1:0]   phase_increment,
    output wire                           fm_out,
    output wire [ACCUMULATOR_WIDTH-1:0]   phase_out    // Debug output
);

    //-------------------------------------------------------------------------
    // Phase Accumulator Register
    //-------------------------------------------------------------------------
    // This is the heart of the DDS. Each clock cycle, we add the phase
    // increment to the accumulator. When it overflows, the MSB toggles.

    reg [ACCUMULATOR_WIDTH-1:0] phase_accumulator;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_accumulator <= {ACCUMULATOR_WIDTH{1'b0}};
        end else if (enable) begin
            // Add phase increment (wraps naturally on overflow)
            phase_accumulator <= phase_accumulator + phase_increment;
        end
        // When disabled, accumulator holds its value (carrier off)
    end

    //-------------------------------------------------------------------------
    // Output Generation
    //-------------------------------------------------------------------------
    // The MSB of the phase accumulator provides the FM output.
    // This creates a square wave at the desired frequency with jitter
    // of approximately one clock period.

    assign fm_out = phase_accumulator[ACCUMULATOR_WIDTH-1];

    // Debug output for simulation/verification
    assign phase_out = phase_accumulator;

endmodule


//-----------------------------------------------------------------------------
// Module: note_to_phase_increment
//
// Description:
//   Converts a note pitch (semitone offset from A4) to a phase increment
//   value for the FM modulator. Uses a lookup table for semitone frequency
//   ratios and scales by a configurable base increment.
//
// Approach:
//   Since we don't know the clock frequency at design time, we use relative
//   frequency encoding. The base_phase_increment parameter sets the center
//   frequency, and note offsets scale this up or down.
//
//   For FM transmission, we modulate around a carrier:
//   phase_inc = base_increment + (note_offset * deviation_per_semitone)
//
// Note Frequency Ratios (12-TET, Equal Temperament):
//   Each semitone is a factor of 2^(1/12) ≈ 1.05946 higher
//
//   For small deviations, we approximate:
//   freq(note) ≈ center_freq * (1 + note_offset * 0.05946)
//
// Design Notes:
//   - Uses multiplication for frequency scaling
//   - Can be pipelined if timing is critical
//   - REST note (0x80) outputs zero increment (silence)
//
// Author: Based on iCEstick-hacks FM transmitter project
// Target: GF180MCU ASIC (architecture independent)
// License: MIT
//-----------------------------------------------------------------------------

module note_to_phase_increment #(
    parameter ACCUMULATOR_WIDTH = 32
)(
    input  wire                           clk,
    input  wire                           rst_n,
    input  wire signed [7:0]              note_pitch,      // Semitones from A4
    input  wire [ACCUMULATOR_WIDTH-1:0]   base_increment,  // Center freq increment
    input  wire [ACCUMULATOR_WIDTH-1:0]   deviation_step,  // Freq step per semitone
    output reg  [ACCUMULATOR_WIDTH-1:0]   phase_increment,
    output reg                            is_rest
);

    //-------------------------------------------------------------------------
    // REST Detection
    //-------------------------------------------------------------------------
    localparam signed [7:0] REST_VALUE = 8'h80;

    wire note_is_rest = (note_pitch == REST_VALUE);

    //-------------------------------------------------------------------------
    // Frequency Calculation
    //-------------------------------------------------------------------------
    // For FM modulation, we add/subtract from the carrier frequency
    // based on the note pitch.
    //
    // phase_increment = base_increment + (note_pitch * deviation_step)
    //
    // This gives us FM audio tones around the carrier frequency.

    wire signed [39:0] deviation;
    wire signed [39:0] signed_increment;

    // Calculate deviation: note_pitch * deviation_step
    // note_pitch is signed (-128 to +127 semitones from A4)
    assign deviation = $signed(note_pitch) * $signed({1'b0, deviation_step});

    // Add to base increment
    assign signed_increment = $signed({1'b0, base_increment}) + deviation;

    //-------------------------------------------------------------------------
    // Output Register (single cycle latency)
    //-------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_increment <= {ACCUMULATOR_WIDTH{1'b0}};
            is_rest <= 1'b1;
        end else begin
            is_rest <= note_is_rest;

            if (note_is_rest) begin
                // REST: output carrier frequency only (no modulation)
                // Or could output zero for silence - design choice
                phase_increment <= base_increment;
            end else begin
                // Normal note: apply frequency deviation
                // Clamp to positive values (can't have negative frequency)
                if (signed_increment[39]) begin
                    // Negative result - clamp to zero
                    phase_increment <= {ACCUMULATOR_WIDTH{1'b0}};
                end else begin
                    phase_increment <= signed_increment[ACCUMULATOR_WIDTH-1:0];
                end
            end
        end
    end

endmodule

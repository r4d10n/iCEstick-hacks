//-----------------------------------------------------------------------------
// Module: audio_tone_generator
//
// Description:
//   Generates audio-frequency square wave tones corresponding to musical notes.
//   Unlike the FM modulator (which generates RF frequencies), this module
//   outputs actual audio frequencies (20 Hz - 20 kHz range) suitable for:
//   - Direct connection to a speaker/buzzer
//   - Audio amplifier input
//   - Debugging/verification of note sequence
//
// Theory of Operation:
//   Uses a phase accumulator similar to FM modulator, but with phase increments
//   calculated for audio frequencies (e.g., A4 = 440 Hz).
//
//   For a note with frequency f_note:
//     phase_increment = (f_note / clk_freq) × 2^32
//
//   The MSB toggles at the note frequency, creating a square wave tone.
//
// Note Frequency Table (A4 = 440 Hz, Equal Temperament):
//   Semitone offset from A4 → frequency:
//     f = 440 × 2^(semitone/12)
//
//   | Semitone | Note | Frequency (Hz) | Phase Inc (100MHz) |
//   |----------|------|----------------|---------------------|
//   | -9       | C4   | 261.63         | 11,244              |
//   | -5       | E4   | 329.63         | 14,168              |
//   | -2       | G4   | 392.00         | 16,848              |
//   | 0        | A4   | 440.00         | 18,912              |
//   | +2       | B4   | 493.88         | 21,228              |
//   | +3       | C5   | 523.25         | 22,490              |
//   | +7       | E5   | 659.26         | 28,336              |
//
// Design Notes:
//   - Architecture independent (pure behavioral Verilog)
//   - Uses lookup table for note frequencies (12-TET)
//   - REST produces silence (output held low)
//   - Volume control via PWM duty cycle (optional)
//
// Author: Based on iCEstick-hacks FM transmitter project
// Target: GF180MCU ASIC (architecture independent)
// License: MIT
//-----------------------------------------------------------------------------

module audio_tone_generator #(
    parameter CLK_FREQ_HZ = 100_000_000,  // Input clock frequency
    parameter ACCUMULATOR_WIDTH = 32      // Phase accumulator width
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    enable,
    input  wire signed [7:0]       note_pitch,    // Semitones from A4
    input  wire                    note_valid,
    output wire                    audio_out,     // Square wave audio output
    output wire                    audio_pwm      // PWM audio (for filtering)
);

    //-------------------------------------------------------------------------
    // Constants
    //-------------------------------------------------------------------------
    localparam signed [7:0] REST_VALUE = 8'h80;

    // Base frequency for A4 (440 Hz)
    // Phase increment = (440 / CLK_FREQ_HZ) * 2^32
    // For 100 MHz: (440 / 100_000_000) * 4_294_967_296 = 18,897
    localparam [31:0] A4_PHASE_INCREMENT = (440 * 64'd4_294_967_296) / CLK_FREQ_HZ;

    //-------------------------------------------------------------------------
    // Note Frequency Lookup Table
    //-------------------------------------------------------------------------
    // Pre-calculated multipliers for semitone offsets
    // Multiplier = 2^(semitone/12) * 65536 (fixed-point 16.16)
    //
    // This avoids runtime exponential calculation

    function [31:0] semitone_multiplier;
        input signed [7:0] semitone;
        begin
            // Lookup table for semitone multipliers (×65536 fixed point)
            // Only cover the range we need for Für Elise (-9 to +12)
            case (semitone)
                -8'd12: semitone_multiplier = 32768;   // 0.5×
                -8'd11: semitone_multiplier = 34716;   // 2^(-11/12)
                -8'd10: semitone_multiplier = 36781;   // 2^(-10/12)
                -8'd9:  semitone_multiplier = 38968;   // C4: 2^(-9/12) = 0.5946
                -8'd8:  semitone_multiplier = 41285;   // C#4
                -8'd7:  semitone_multiplier = 43740;   // D4
                -8'd6:  semitone_multiplier = 46341;   // D#4
                -8'd5:  semitone_multiplier = 49097;   // E4
                -8'd4:  semitone_multiplier = 52016;   // F4
                -8'd3:  semitone_multiplier = 55109;   // F#4
                -8'd2:  semitone_multiplier = 58386;   // G4
                -8'd1:  semitone_multiplier = 61858;   // G#4
                8'd0:   semitone_multiplier = 65536;   // A4: 1.0×
                8'd1:   semitone_multiplier = 69433;   // A#4
                8'd2:   semitone_multiplier = 73562;   // B4
                8'd3:   semitone_multiplier = 77936;   // C5
                8'd4:   semitone_multiplier = 82570;   // C#5
                8'd5:   semitone_multiplier = 87480;   // D5
                8'd6:   semitone_multiplier = 92682;   // D#5
                8'd7:   semitone_multiplier = 98193;   // E5
                8'd8:   semitone_multiplier = 104032;  // F5
                8'd9:   semitone_multiplier = 110218;  // F#5
                8'd10:  semitone_multiplier = 116772;  // G5
                8'd11:  semitone_multiplier = 123715;  // G#5
                8'd12:  semitone_multiplier = 131072;  // A5: 2.0×
                default: semitone_multiplier = 65536;  // Default to A4
            endcase
        end
    endfunction

    //-------------------------------------------------------------------------
    // Phase Increment Calculation
    //-------------------------------------------------------------------------
    wire is_rest = (note_pitch == REST_VALUE);

    // Get multiplier for current note
    wire [31:0] multiplier = semitone_multiplier(note_pitch);

    // Calculate phase increment: A4_increment × multiplier / 65536
    wire [63:0] phase_product = A4_PHASE_INCREMENT * multiplier;
    wire [31:0] note_phase_increment = phase_product[47:16];  // Divide by 65536

    //-------------------------------------------------------------------------
    // Phase Accumulator
    //-------------------------------------------------------------------------
    reg [ACCUMULATOR_WIDTH-1:0] phase_accumulator;
    reg [31:0] current_phase_increment;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            phase_accumulator <= {ACCUMULATOR_WIDTH{1'b0}};
            current_phase_increment <= {32{1'b0}};
        end else if (enable && note_valid) begin
            // Update phase increment when note changes
            if (!is_rest) begin
                current_phase_increment <= note_phase_increment;
            end else begin
                current_phase_increment <= {32{1'b0}};
            end

            // Accumulate phase
            phase_accumulator <= phase_accumulator + current_phase_increment;
        end else if (!enable) begin
            // Hold when disabled
            phase_accumulator <= {ACCUMULATOR_WIDTH{1'b0}};
        end
    end

    //-------------------------------------------------------------------------
    // Output Generation
    //-------------------------------------------------------------------------
    // Square wave output (MSB of accumulator)
    assign audio_out = enable && note_valid && !is_rest ? phase_accumulator[ACCUMULATOR_WIDTH-1] : 1'b0;

    // PWM output (can be low-pass filtered for smoother audio)
    // Uses upper 8 bits for 256-level PWM
    // This creates a more sine-like waveform when filtered
    assign audio_pwm = audio_out;  // For now, same as square wave
                                   // Could implement true PWM here

endmodule

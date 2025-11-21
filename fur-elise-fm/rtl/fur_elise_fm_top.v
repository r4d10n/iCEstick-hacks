//-----------------------------------------------------------------------------
// Module: fur_elise_fm_top
//
// Description:
//   Top-level module for the Für Elise FM transmitter. Integrates the melody
//   ROM, sequencer, frequency converter, and FM modulator to create a
//   self-contained musical FM transmitter.
//
// Design Overview:
//   This design generates an FM-modulated signal that plays Beethoven's
//   "Für Elise" melody. The output can be received on an FM radio tuned
//   to a frequency determined by the input clock and BASE_PHASE_INCREMENT.
//
// Architecture:
//
//   +-------------+     +------------+     +------------------+
//   | melody_rom  |---->| sequencer  |---->| note_to_phase_   |
//   | (82 notes)  |     | (timing)   |     | increment        |
//   +-------------+     +------------+     +------------------+
//                                                  |
//                                                  v
//                                          +-------------+
//                                          | fm_modulator|---> fm_out
//                                          | (32-bit DDS)|
//                                          +-------------+
//
// Frequency Calculation:
//   Since there is NO PLL, the output frequency is determined by:
//
//     center_freq = (BASE_PHASE_INCREMENT / 2^32) × clk_freq
//
//   Example configurations:
//
//   | Clock (MHz) | BASE_PHASE_INCREMENT | Center Freq (MHz) |
//   |-------------|----------------------|-------------------|
//   | 100         | 0x40000000           | 25.0              |
//   | 50          | 0x40000000           | 12.5              |
//   | 10          | 0x40000000           | 2.5               |
//   | 100         | 0x20000000           | 12.5              |
//   | 100         | 0x80000000           | 50.0              |
//
//   Musical notes are FM-modulated around this center frequency.
//   DEVIATION_PER_SEMITONE controls how much frequency changes per note.
//
// Target Technology:
//   - GlobalFoundries GF180MCU (180nm ASIC)
//   - Architecture independent (no vendor primitives)
//   - Pure synthesizable Verilog
//
// Author: Based on iCEstick-hacks FM transmitter project
// Target: GF180MCU ASIC (architecture independent)
// License: MIT
//-----------------------------------------------------------------------------

module fur_elise_fm_top #(
    //-------------------------------------------------------------------------
    // Timing Parameters
    //-------------------------------------------------------------------------
    // CLOCKS_PER_16TH: Number of clock cycles per 16th note
    // This controls the tempo of the melody.
    //
    // Formula: CLOCKS_PER_16TH = clk_freq / (BPM / 60 * 4)
    //
    // Examples:
    //   100 MHz, 120 BPM: 100M / (120/60*4) = 100M / 8 = 12,500,000
    //   50 MHz,  120 BPM: 50M / 8 = 6,250,000
    //   10 MHz,  120 BPM: 10M / 8 = 1,250,000
    //
    parameter CLOCKS_PER_16TH = 12_500_000,

    //-------------------------------------------------------------------------
    // FM Modulation Parameters
    //-------------------------------------------------------------------------
    // BASE_PHASE_INCREMENT: Phase increment for center (carrier) frequency
    // Formula: (center_freq / clk_freq) * 2^32
    //
    // Example: For center_freq = clk_freq/4 (quarter of clock):
    //   BASE_PHASE_INCREMENT = 0.25 * 2^32 = 0x40000000
    //
    parameter [31:0] BASE_PHASE_INCREMENT = 32'h40000000,

    // DEVIATION_PER_SEMITONE: Frequency shift per semitone
    // This determines how much the frequency changes for each musical note.
    // Higher values = wider FM deviation = easier to hear notes
    //
    // For typical FM radio (75 kHz deviation), with 12 semitones per octave:
    //   deviation = 75000 / 12 ≈ 6250 Hz per semitone
    //
    // Phase increment per semitone = (6250 / clk_freq) * 2^32
    // For 100 MHz clock: (6250 / 100M) * 2^32 ≈ 268,435
    //
    // For larger deviations (easier to distinguish notes):
    //   100 kHz per semitone with 100 MHz clock:
    //   (100000 / 100M) * 2^32 = 4,294,967 ≈ 0x00418937
    //
    parameter [31:0] DEVIATION_PER_SEMITONE = 32'h00418937,

    //-------------------------------------------------------------------------
    // Melody Parameters
    //-------------------------------------------------------------------------
    parameter MELODY_LENGTH = 82,    // Number of notes in Für Elise excerpt
    parameter ADDR_WIDTH    = 7      // log2(MELODY_LENGTH), rounded up
)(
    //-------------------------------------------------------------------------
    // Clock and Reset
    //-------------------------------------------------------------------------
    input  wire         clk,         // System clock
    input  wire         rst_n,       // Active-low asynchronous reset

    //-------------------------------------------------------------------------
    // Control Inputs
    //-------------------------------------------------------------------------
    input  wire         enable,      // Enable melody playback
    input  wire         loop,        // Loop melody continuously

    //-------------------------------------------------------------------------
    // FM Output
    //-------------------------------------------------------------------------
    output wire         fm_out,      // FM modulated output (connect to GPIO)

    //-------------------------------------------------------------------------
    // Status Outputs
    //-------------------------------------------------------------------------
    output wire         playing,     // Melody is currently playing
    output wire         melody_end,  // Pulse when melody completes
    output wire [ADDR_WIDTH-1:0] note_index  // Current note index (debug)
);

    //=========================================================================
    // Internal Signals
    //=========================================================================

    // Melody ROM interface
    wire [ADDR_WIDTH-1:0] rom_addr;
    wire [15:0]           rom_data;

    // Sequencer to note converter
    wire signed [7:0]     current_pitch;
    wire                  pitch_valid;

    // Note converter to modulator
    wire [31:0]           phase_increment;
    wire                  is_rest;

    // FM modulator internal
    wire [31:0]           phase_accumulator;

    //=========================================================================
    // Module Instances
    //=========================================================================

    //-------------------------------------------------------------------------
    // Melody ROM
    // Stores the Für Elise note sequence
    //-------------------------------------------------------------------------
    melody_rom #(
        .MELODY_LENGTH(MELODY_LENGTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_melody_rom (
        .clk    (clk),
        .addr   (rom_addr),
        .data   (rom_data)
    );

    //-------------------------------------------------------------------------
    // Melody Sequencer
    // Controls timing and steps through the melody
    //-------------------------------------------------------------------------
    melody_sequencer #(
        .CLOCKS_PER_16TH(CLOCKS_PER_16TH),
        .MELODY_LENGTH(MELODY_LENGTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_sequencer (
        .clk        (clk),
        .rst_n      (rst_n),
        .enable     (enable),
        .loop       (loop),
        .note_data  (rom_data),
        .note_addr  (rom_addr),
        .note_pitch (current_pitch),
        .note_valid (pitch_valid),
        .playing    (playing),
        .melody_end (melody_end)
    );

    //-------------------------------------------------------------------------
    // Note to Phase Increment Converter
    // Converts musical pitch to DDS phase increment
    //-------------------------------------------------------------------------
    note_to_phase_increment #(
        .ACCUMULATOR_WIDTH(32)
    ) u_note_to_freq (
        .clk             (clk),
        .rst_n           (rst_n),
        .note_pitch      (current_pitch),
        .base_increment  (BASE_PHASE_INCREMENT),
        .deviation_step  (DEVIATION_PER_SEMITONE),
        .phase_increment (phase_increment),
        .is_rest         (is_rest)
    );

    //-------------------------------------------------------------------------
    // FM Modulator
    // DDS-based frequency synthesizer
    //-------------------------------------------------------------------------
    fm_modulator #(
        .ACCUMULATOR_WIDTH(32)
    ) u_fm_mod (
        .clk             (clk),
        .rst_n           (rst_n),
        .enable          (enable & pitch_valid),
        .phase_increment (phase_increment),
        .fm_out          (fm_out),
        .phase_out       (phase_accumulator)
    );

    //=========================================================================
    // Debug Outputs
    //=========================================================================
    assign note_index = rom_addr;

endmodule


//-----------------------------------------------------------------------------
// Helper Module: fur_elise_fm_params
//
// Description:
//   Convenience module with pre-calculated parameters for common clock
//   frequencies. Not synthesized - just for documentation/reference.
//-----------------------------------------------------------------------------

/*
// Parameter lookup table for common configurations:
//
// +--------+-----------------+-------------------+---------------------+
// | Clock  | CLOCKS_PER_16TH | BASE_PHASE_INC    | DEVIATION_PER_SEMI  |
// | (MHz)  | (120 BPM)       | (clk/4 center)    | (~100kHz/semitone)  |
// +--------+-----------------+-------------------+---------------------+
// | 10     | 1,250,000       | 0x40000000        | 0x028F5C29          |
// | 20     | 2,500,000       | 0x40000000        | 0x0147AE14          |
// | 50     | 6,250,000       | 0x40000000        | 0x00831461          |
// | 100    | 12,500,000      | 0x40000000        | 0x00418937          |
// | 200    | 25,000,000      | 0x40000000        | 0x0020C49C          |
// +--------+-----------------+-------------------+---------------------+
//
// For different tempos, scale CLOCKS_PER_16TH:
//   60 BPM:  multiply by 2
//   90 BPM:  multiply by 4/3
//   120 BPM: use table value
//   180 BPM: multiply by 2/3
//   240 BPM: divide by 2
//
// For different center frequencies, adjust BASE_PHASE_INCREMENT:
//   center_freq = clk/2:  BASE_PHASE_INC = 0x80000000
//   center_freq = clk/4:  BASE_PHASE_INC = 0x40000000
//   center_freq = clk/8:  BASE_PHASE_INC = 0x20000000
//   center_freq = clk/16: BASE_PHASE_INC = 0x10000000
//
// Formula for any frequency:
//   BASE_PHASE_INCREMENT = (center_freq_hz / clk_freq_hz) * 0x100000000
*/

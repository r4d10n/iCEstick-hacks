//-----------------------------------------------------------------------------
// Module: fur_elise_fm_top
//
// Description:
//   Top-level module for the Für Elise FM transmitter with configurable
//   options via 5 hardware jumper pins. Includes both FM RF output and
//   audio-frequency PWM output for direct speaker connection.
//
// Architecture:
//
//   +-------------+     +------------+     +------------------+
//   | melody_rom  |---->| sequencer  |---->| note_to_phase_   |
//   | (82 notes)  |     | (timing)   |     | increment        |
//   +-------------+     +------------+     +------------------+
//                              |                   |
//                              |                   v
//                              |           +-------------+
//                              |           | fm_modulator|---> fm_out
//                              |           | (RF DDS)    |
//                              |           +-------------+
//                              |
//                              +---------> +---------------+
//                                          | audio_tone_   |---> audio_out
//                                          | generator     |
//                                          +---------------+
//
// Configuration Pins (Active High, directly readable from jumpers/DIP switch):
//
//   +------+------------------+-------------------------------------------+
//   | Pin  | Function         | Description                               |
//   +------+------------------+-------------------------------------------+
//   | [0]  | Loop Enable      | 0 = Play once and stop                    |
//   |      |                  | 1 = Loop continuously                     |
//   +------+------------------+-------------------------------------------+
//   | [2:1]| Tempo Select     | 00 = Slow     (60 BPM,  ~40 sec melody)   |
//   |      |                  | 01 = Normal   (120 BPM, ~20 sec melody)   |
//   |      |                  | 10 = Fast     (180 BPM, ~13 sec melody)   |
//   |      |                  | 11 = Allegro  (240 BPM, ~10 sec melody)   |
//   +------+------------------+-------------------------------------------+
//   | [3]  | Audio Enable     | 0 = Audio output disabled                 |
//   |      |                  | 1 = Audio output enabled (speaker/buzzer) |
//   +------+------------------+-------------------------------------------+
//   | [4]  | FM Enable        | 0 = FM output disabled                    |
//   |      |                  | 1 = FM output enabled (RF transmission)   |
//   +------+------------------+-------------------------------------------+
//
// Default Configuration (all jumpers open/low):
//   - Single play (no loop)
//   - Slow tempo (60 BPM)
//   - Audio disabled
//   - FM disabled
//   - Use 'enable' pin to start playback
//
// Recommended Test Configuration:
//   - cfg[4:0] = 5'b01010 → Loop, Normal tempo, Audio enabled, FM disabled
//   - cfg[4:0] = 5'b10011 → Loop, Normal tempo, Audio disabled, FM enabled
//   - cfg[4:0] = 5'b11011 → Loop, Normal tempo, Both outputs enabled
//
// Frequency Notes:
//   - FM output: ~clk/4 carrier with note modulation (MHz range)
//   - Audio output: Actual note frequencies (261-659 Hz for Für Elise)
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
    // Clock Frequency (needed for audio tone generation)
    //-------------------------------------------------------------------------
    parameter CLK_FREQ_HZ = 100_000_000,

    //-------------------------------------------------------------------------
    // Timing Parameters (base values, modified by tempo select)
    //-------------------------------------------------------------------------
    // Base clocks per 16th note at 120 BPM
    // Formula: CLOCKS_PER_16TH_BASE = clk_freq / (120 / 60 * 4) = clk_freq / 8
    parameter CLOCKS_PER_16TH_BASE = CLK_FREQ_HZ / 8,

    //-------------------------------------------------------------------------
    // FM Modulation Parameters
    //-------------------------------------------------------------------------
    parameter [31:0] BASE_PHASE_INCREMENT = 32'h40000000,
    parameter [31:0] DEVIATION_PER_SEMITONE = 32'h00418937,

    //-------------------------------------------------------------------------
    // Melody Parameters
    //-------------------------------------------------------------------------
    parameter MELODY_LENGTH = 82,
    parameter ADDR_WIDTH    = 7
)(
    //-------------------------------------------------------------------------
    // Clock and Reset
    //-------------------------------------------------------------------------
    input  wire         clk,         // System clock
    input  wire         rst_n,       // Active-low asynchronous reset

    //-------------------------------------------------------------------------
    // Configuration Pins (directly from jumpers/DIP switch)
    //-------------------------------------------------------------------------
    input  wire [4:0]   cfg,         // Configuration jumpers
                                     // [0]   = Loop enable
                                     // [2:1] = Tempo select (00=60, 01=120, 10=180, 11=240 BPM)
                                     // [3]   = Audio output enable
                                     // [4]   = FM output enable

    //-------------------------------------------------------------------------
    // Control Input
    //-------------------------------------------------------------------------
    input  wire         enable,      // Enable/start melody playback

    //-------------------------------------------------------------------------
    // Outputs
    //-------------------------------------------------------------------------
    output wire         fm_out,      // FM modulated RF output (GPIO)
    output wire         audio_out,   // Audio frequency output (GPIO to speaker)

    //-------------------------------------------------------------------------
    // Status Outputs
    //-------------------------------------------------------------------------
    output wire         playing,     // Melody is currently playing
    output wire         melody_end,  // Pulse when melody completes
    output wire [ADDR_WIDTH-1:0] note_index  // Current note index (debug)
);

    //=========================================================================
    // Configuration Decoding
    //=========================================================================

    // Extract configuration bits
    wire cfg_loop_enable  = cfg[0];
    wire [1:0] cfg_tempo  = cfg[2:1];
    wire cfg_audio_enable = cfg[3];
    wire cfg_fm_enable    = cfg[4];

    //-------------------------------------------------------------------------
    // Tempo Selection
    //-------------------------------------------------------------------------
    // Decode tempo configuration to clocks per 16th note
    //
    // Tempo | BPM | Multiplier | Clocks per 16th (100MHz) |
    // ------|-----|------------|---------------------------|
    // 00    | 60  | 2.0x       | 25,000,000               |
    // 01    | 120 | 1.0x       | 12,500,000               |
    // 10    | 180 | 0.667x     | 8,333,333                |
    // 11    | 240 | 0.5x       | 6,250,000                |

    reg [31:0] clocks_per_16th;

    always @(*) begin
        case (cfg_tempo)
            2'b00: clocks_per_16th = CLOCKS_PER_16TH_BASE * 2;       // 60 BPM (slow)
            2'b01: clocks_per_16th = CLOCKS_PER_16TH_BASE;           // 120 BPM (normal)
            2'b10: clocks_per_16th = (CLOCKS_PER_16TH_BASE * 2) / 3; // 180 BPM (fast)
            2'b11: clocks_per_16th = CLOCKS_PER_16TH_BASE / 2;       // 240 BPM (allegro)
        endcase
    end

    //=========================================================================
    // Internal Signals
    //=========================================================================

    // Melody ROM interface
    wire [ADDR_WIDTH-1:0] rom_addr;
    wire [15:0]           rom_data;

    // Sequencer outputs
    wire signed [7:0]     current_pitch;
    wire                  pitch_valid;
    wire                  sequencer_playing;
    wire                  sequencer_melody_end;

    // FM modulator signals
    wire [31:0]           phase_increment;
    wire                  is_rest;
    wire [31:0]           phase_accumulator;
    wire                  fm_raw_out;

    // Audio generator signals
    wire                  audio_raw_out;

    //=========================================================================
    // Module Instances
    //=========================================================================

    //-------------------------------------------------------------------------
    // Melody ROM
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
    // Melody Sequencer (with runtime-configurable tempo)
    //-------------------------------------------------------------------------
    melody_sequencer #(
        .CLOCKS_PER_16TH(CLOCKS_PER_16TH_BASE),  // Default fallback
        .MELODY_LENGTH(MELODY_LENGTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_sequencer (
        .clk         (clk),
        .rst_n       (rst_n),
        .enable      (enable),
        .loop        (cfg_loop_enable),
        .tempo_clocks(clocks_per_16th),  // Runtime tempo from config pins
        .note_data   (rom_data),
        .note_addr   (rom_addr),
        .note_pitch  (current_pitch),
        .note_valid  (pitch_valid),
        .playing     (sequencer_playing),
        .melody_end  (sequencer_melody_end)
    );

    //-------------------------------------------------------------------------
    // Note to Phase Increment Converter (for FM)
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
    // FM Modulator (RF output)
    //-------------------------------------------------------------------------
    fm_modulator #(
        .ACCUMULATOR_WIDTH(32)
    ) u_fm_mod (
        .clk             (clk),
        .rst_n           (rst_n),
        .enable          (enable & pitch_valid & cfg_fm_enable),
        .phase_increment (phase_increment),
        .fm_out          (fm_raw_out),
        .phase_out       (phase_accumulator)
    );

    //-------------------------------------------------------------------------
    // Audio Tone Generator (speaker output)
    //-------------------------------------------------------------------------
    audio_tone_generator #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .ACCUMULATOR_WIDTH(32)
    ) u_audio_gen (
        .clk        (clk),
        .rst_n      (rst_n),
        .enable     (enable & cfg_audio_enable),
        .note_pitch (current_pitch),
        .note_valid (pitch_valid),
        .audio_out  (audio_raw_out),
        .audio_pwm  ()  // Not used in this version
    );

    //=========================================================================
    // Output Gating
    //=========================================================================

    // FM output: gated by configuration
    assign fm_out = cfg_fm_enable ? fm_raw_out : 1'b0;

    // Audio output: gated by configuration
    assign audio_out = cfg_audio_enable ? audio_raw_out : 1'b0;

    //=========================================================================
    // Status Outputs
    //=========================================================================
    assign playing    = sequencer_playing;
    assign melody_end = sequencer_melody_end;
    assign note_index = rom_addr;

endmodule


//=============================================================================
// Configuration Reference (for documentation)
//=============================================================================
/*
 JUMPER CONFIGURATION QUICK REFERENCE
 =====================================

 cfg[4:0] | Loop | Tempo      | Audio | FM  | Use Case
 ---------|------|------------|-------|-----|----------------------------------
 5'b00000 | No   | 60 BPM     | Off   | Off | Default (outputs disabled)
 5'b00001 | Yes  | 60 BPM     | Off   | Off | Loop mode test (no output)
 5'b00010 | No   | 120 BPM    | Off   | Off | Normal tempo test
 5'b01000 | No   | 60 BPM     | On    | Off | Audio only, slow
 5'b01001 | Yes  | 60 BPM     | On    | Off | Audio only, slow, looping
 5'b01010 | No   | 120 BPM    | On    | Off | Audio only, normal tempo
 5'b01011 | Yes  | 120 BPM    | On    | Off | *** RECOMMENDED: Audio test ***
 5'b10000 | No   | 60 BPM     | Off   | On  | FM only, slow
 5'b10011 | Yes  | 120 BPM    | Off   | On  | *** RECOMMENDED: FM test ***
 5'b11010 | No   | 120 BPM    | On    | On  | Both outputs, normal tempo
 5'b11011 | Yes  | 120 BPM    | On    | On  | *** RECOMMENDED: Full demo ***
 5'b11111 | Yes  | 240 BPM    | On    | On  | Both outputs, fast (allegro)

 PHYSICAL JUMPER LAYOUT (suggested):
 ===================================

     J1    J2    J3    J4    J5
    +---+ +---+ +---+ +---+ +---+
    |   | |   | |   | |   | |   |
    | L | | T | | T | | A | | F |
    | O | | E | | E | | U | | M |
    | O | | M | | M | | D | |   |
    | P | | P | | P | | I | | E |
    |   | | O | | O | | O | | N |
    |   | | 0 | | 1 | |   | |   |
    +---+ +---+ +---+ +---+ +---+
    cfg[0] cfg[1] cfg[2] cfg[3] cfg[4]

 Jumper installed = Logic 1 (high)
 Jumper removed   = Logic 0 (low, via pull-down resistor)

 TEMPO TABLE:
 ============
 cfg[2:1] | BPM | Quarter Note | Full Melody Duration
 ---------|-----|--------------|----------------------
    00    | 60  | 1.0 sec      | ~40 seconds
    01    | 120 | 0.5 sec      | ~20 seconds
    10    | 180 | 0.33 sec     | ~13 seconds
    11    | 240 | 0.25 sec     | ~10 seconds

 ASIC PIN ASSIGNMENT SUGGESTION:
 ===============================
 Pin 1:  clk         - Clock input
 Pin 2:  rst_n       - Reset (active low)
 Pin 3:  enable      - Start playback
 Pin 4:  cfg[0]      - Loop enable jumper
 Pin 5:  cfg[1]      - Tempo bit 0
 Pin 6:  cfg[2]      - Tempo bit 1
 Pin 7:  cfg[3]      - Audio enable jumper
 Pin 8:  cfg[4]      - FM enable jumper
 Pin 9:  fm_out      - FM RF output
 Pin 10: audio_out   - Audio output (to speaker)
 Pin 11: playing     - Status LED
 Pin 12: melody_end  - End pulse output

*/

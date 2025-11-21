//-----------------------------------------------------------------------------
// Module: fur_elise_fm_top
//
// Description:
//   Top-level module for the Für Elise FM transmitter with PWM audio input
//   capability and optional clock doubling.
//
// Features:
//   - Plays built-in Für Elise melody via FM
//   - Accepts external PWM audio input for FM transmission
//   - Optional clock doubling (XOR-based) for higher FM carrier frequency
//   - Audio frequency output for direct speaker connection
//   - Phase increment output for debugging/monitoring
//
// Operating Modes:
//   1. Melody Mode (pwm_in tied low or floating):
//      - Plays Für Elise from internal ROM
//      - FM output modulated with musical notes
//
//   2. PWM Input Mode (pwm_in connected to external source):
//      - External PWM audio is decoded and transmitted via FM
//      - Melody playback continues on audio_out
//
// Clock Doubling:
//   - Enabled via clk_2x_enable jumper
//   - Uses XOR-based edge detection to double clock frequency
//   - Doubles FM carrier frequency (e.g., 100MHz → ~200MHz effective)
//   - Useful for reaching higher carrier frequencies without PLL
//
// Ports:
//   clk           - Input clock (~100 MHz expected)
//   rst_n         - Active-low reset
//   enable        - Enable playback
//   loop          - Loop melody continuously
//   clk_2x_enable - Enable clock doubling (jumper)
//   pwm_in        - External PWM audio input
//   fm_out        - FM modulated RF output
//   audio_out     - Audio frequency output (speaker)
//   phase_inc_out - Current phase increment (32-bit, for debugging)
//   playing       - Melody currently playing
//   melody_end    - Pulse at end of melody
//
// Author: Based on iCEstick-hacks FM transmitter project
// Target: GF180MCU ASIC (architecture independent)
// License: MIT
//-----------------------------------------------------------------------------

module fur_elise_fm_top #(
    //-------------------------------------------------------------------------
    // Clock Parameters
    //-------------------------------------------------------------------------
    parameter CLK_FREQ_HZ = 100_000_000,

    //-------------------------------------------------------------------------
    // Timing Parameters
    //-------------------------------------------------------------------------
    // Base clocks per 16th note at 120 BPM
    parameter CLOCKS_PER_16TH = CLK_FREQ_HZ / 8,  // 12,500,000 for 100MHz

    //-------------------------------------------------------------------------
    // FM Modulation Parameters
    //-------------------------------------------------------------------------
    // Center frequency = (BASE_PHASE_INCREMENT / 2^32) * CLK_FREQ
    // For clk/4: BASE_PHASE_INCREMENT = 0x40000000 → 25 MHz with 100 MHz clock
    parameter [31:0] BASE_PHASE_INCREMENT = 32'h40000000,

    // Deviation per semitone (for melody mode)
    parameter [31:0] DEVIATION_PER_SEMITONE = 32'h00418937,

    // PWM input deviation scaling
    // Full scale PWM → ±75 kHz deviation
    // Phase inc per sample unit = (75000 / CLK_FREQ) * 2^32 / 32768
    parameter [31:0] PWM_DEVIATION_SCALE = 32'h00009A5E,

    //-------------------------------------------------------------------------
    // PWM Input Parameters
    //-------------------------------------------------------------------------
    parameter PWM_FREQ_HZ = 50_000,  // Expected PWM frequency

    //-------------------------------------------------------------------------
    // Melody Parameters
    //-------------------------------------------------------------------------
    parameter MELODY_LENGTH = 82,
    parameter ADDR_WIDTH    = 7
)(
    //-------------------------------------------------------------------------
    // Clock and Reset
    //-------------------------------------------------------------------------
    input  wire         clk,             // System clock (~100 MHz)
    input  wire         rst_n,           // Active-low asynchronous reset

    //-------------------------------------------------------------------------
    // Control Inputs
    //-------------------------------------------------------------------------
    input  wire         enable,          // Enable playback
    input  wire         loop,            // Loop melody continuously
    input  wire         clk_2x_enable,   // Enable clock doubling (jumper)

    //-------------------------------------------------------------------------
    // PWM Audio Input
    //-------------------------------------------------------------------------
    input  wire         pwm_in,          // External PWM audio input

    //-------------------------------------------------------------------------
    // Outputs
    //-------------------------------------------------------------------------
    output wire         fm_out,          // FM modulated RF output
    output wire         audio_out,       // Audio frequency output (speaker)
    output wire [31:0]  phase_inc_out,   // Phase increment (debug/monitoring)

    //-------------------------------------------------------------------------
    // Status Outputs
    //-------------------------------------------------------------------------
    output wire         playing,         // Melody currently playing
    output wire         melody_end,      // Pulse at end of melody
    output wire [ADDR_WIDTH-1:0] note_index  // Current note index (debug)
);

    //=========================================================================
    // Clock Doubling
    //=========================================================================

    wire clk_fast;  // Potentially doubled clock

    clock_doubler #(
        .DELAY_STAGES(8)
    ) u_clk_doubler (
        .clk_in  (clk),
        .enable  (clk_2x_enable),
        .clk_out (clk_fast)
    );

    //=========================================================================
    // PWM Input Decoder
    //=========================================================================

    wire signed [15:0] pwm_sample;
    wire pwm_sample_valid;
    wire [15:0] pwm_debug;

    pwm_input_decoder #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .PWM_FREQ_HZ(PWM_FREQ_HZ),
        .SAMPLE_BITS(16)
    ) u_pwm_decoder (
        .clk         (clk),
        .rst_n       (rst_n),
        .enable      (enable),
        .pwm_in      (pwm_in),
        .sample_out  (pwm_sample),
        .sample_valid(pwm_sample_valid),
        .debug_count (pwm_debug)
    );

    //=========================================================================
    // Melody ROM and Sequencer
    //=========================================================================

    wire [ADDR_WIDTH-1:0] rom_addr;
    wire [15:0]           rom_data;
    wire signed [7:0]     current_pitch;
    wire                  pitch_valid;
    wire                  sequencer_playing;
    wire                  sequencer_melody_end;

    melody_rom #(
        .MELODY_LENGTH(MELODY_LENGTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_melody_rom (
        .clk    (clk),
        .addr   (rom_addr),
        .data   (rom_data)
    );

    melody_sequencer #(
        .CLOCKS_PER_16TH(CLOCKS_PER_16TH),
        .MELODY_LENGTH(MELODY_LENGTH),
        .ADDR_WIDTH(ADDR_WIDTH)
    ) u_sequencer (
        .clk         (clk),
        .rst_n       (rst_n),
        .enable      (enable),
        .loop        (loop),
        .tempo_clocks(32'd0),  // Use default tempo
        .note_data   (rom_data),
        .note_addr   (rom_addr),
        .note_pitch  (current_pitch),
        .note_valid  (pitch_valid),
        .playing     (sequencer_playing),
        .melody_end  (sequencer_melody_end)
    );

    //=========================================================================
    // Note to Phase Increment (for melody)
    //=========================================================================

    wire [31:0] melody_phase_increment;
    wire        melody_is_rest;

    note_to_phase_increment #(
        .ACCUMULATOR_WIDTH(32)
    ) u_note_to_freq (
        .clk             (clk),
        .rst_n           (rst_n),
        .note_pitch      (current_pitch),
        .base_increment  (BASE_PHASE_INCREMENT),
        .deviation_step  (DEVIATION_PER_SEMITONE),
        .phase_increment (melody_phase_increment),
        .is_rest         (melody_is_rest)
    );

    //=========================================================================
    // PWM to Phase Increment Conversion
    //=========================================================================
    // Convert PWM sample to FM deviation
    // phase_increment = BASE_PHASE_INCREMENT + (pwm_sample * PWM_DEVIATION_SCALE)

    reg [31:0] pwm_phase_increment;
    reg pwm_active;

    // Detect if PWM input is active (has valid samples)
    reg [7:0] pwm_timeout_counter;
    localparam PWM_TIMEOUT = 255;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pwm_timeout_counter <= 0;
            pwm_active <= 1'b0;
        end else begin
            if (pwm_sample_valid) begin
                pwm_timeout_counter <= PWM_TIMEOUT;
                pwm_active <= 1'b1;
            end else if (pwm_timeout_counter > 0) begin
                pwm_timeout_counter <= pwm_timeout_counter - 1;
            end else begin
                pwm_active <= 1'b0;
            end
        end
    end

    // Calculate PWM-based phase increment
    wire signed [47:0] pwm_deviation;
    assign pwm_deviation = $signed(pwm_sample) * $signed({1'b0, PWM_DEVIATION_SCALE});

    wire [31:0] pwm_phase_calc;
    assign pwm_phase_calc = BASE_PHASE_INCREMENT + pwm_deviation[47:16];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pwm_phase_increment <= BASE_PHASE_INCREMENT;
        end else if (pwm_sample_valid) begin
            pwm_phase_increment <= pwm_phase_calc;
        end
    end

    //=========================================================================
    // Phase Increment Selection
    //=========================================================================
    // Use PWM input when active, otherwise use melody

    wire [31:0] selected_phase_increment;
    assign selected_phase_increment = pwm_active ? pwm_phase_increment : melody_phase_increment;

    // Output phase increment for debugging/monitoring
    assign phase_inc_out = selected_phase_increment;

    //=========================================================================
    // FM Modulator (using fast clock)
    //=========================================================================

    wire fm_raw_out;

    fm_modulator #(
        .ACCUMULATOR_WIDTH(32)
    ) u_fm_mod (
        .clk             (clk_fast),          // Use doubled clock when enabled
        .rst_n           (rst_n),
        .enable          (enable & (pitch_valid | pwm_active)),
        .phase_increment (selected_phase_increment),
        .fm_out          (fm_raw_out),
        .phase_out       ()
    );

    assign fm_out = fm_raw_out;

    //=========================================================================
    // Audio Tone Generator (for speaker output)
    //=========================================================================
    // Always plays melody regardless of PWM input

    audio_tone_generator #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .ACCUMULATOR_WIDTH(32)
    ) u_audio_gen (
        .clk        (clk),
        .rst_n      (rst_n),
        .enable     (enable),
        .note_pitch (current_pitch),
        .note_valid (pitch_valid),
        .audio_out  (audio_out),
        .audio_pwm  ()
    );

    //=========================================================================
    // Status Outputs
    //=========================================================================

    assign playing    = sequencer_playing;
    assign melody_end = sequencer_melody_end;
    assign note_index = rom_addr;

endmodule

/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

//-----------------------------------------------------------------------------
// Module: tt_um_fur_elise_fm
//
// Description:
//   Simplified wrapper for Für Elise FM transmitter for Vahya Mini ECP5.
//   Plays Beethoven's "Für Elise" melody via FM modulation.
//
//   VAHYA MINI CONFIGURATION:
//   - Standalone mode: automatically plays on power-up
//   - Loops continuously
//   - Only fm_out (C10) and audio_out (D13) are used
//   - All ui_in, uo_out[2-7], and uio_* pins are present but unused
//
// Essential Pins:
//   clk        = 26 MHz clock (J14 on Vahya Mini)
//   rst_n      = Reset (N6 on Vahya Mini)
//   ena        = Enable (P1 on Vahya Mini, can tie high)
//   uo_out[0]  = fm_out (C10) - FM modulated RF output
//   uo_out[1]  = audio_out (D13) - Audio frequency output
//
// Unused Pins (internally assigned but not connected):
//   ui_in[7:0]   - All inputs tied to defaults
//   uo_out[7:2]  - Status outputs (unused)
//   uio[7:0]     - Bidirectional pins (unused)
//
//-----------------------------------------------------------------------------

module tt_um_fur_elise_fm (
    input  wire [7:0] ui_in,    // Dedicated inputs (unused, tied to defaults)
    output wire [7:0] uo_out,   // Dedicated outputs (only [1:0] used)
    input  wire [7:0] uio_in,   // IOs: Input path (unused)
    output wire [7:0] uio_out,  // IOs: Output path (unused)
    output wire [7:0] uio_oe,   // IOs: Enable path (unused)
    input  wire       ena,      // Enable signal
    input  wire       clk,      // 26 MHz clock
    input  wire       rst_n     // Reset (active low)
);

    //=========================================================================
    // Standalone Configuration
    //=========================================================================
    // For Vahya Mini: enable on power-up, loop continuously, no external inputs
    wire enable      = ena;          // Always enabled when powered
    wire loop        = 1'b1;         // Loop melody continuously
    wire clk_2x_en   = 1'b0;         // No clock doubling (26 MHz is sufficient)
    wire pwm_in      = 1'b0;         // No external PWM input

    //=========================================================================
    // Internal Signals
    //=========================================================================
    wire        fm_out;
    wire        audio_out;
    wire [31:0] phase_inc_out;
    wire        playing;
    wire        melody_end;
    wire [6:0]  note_index;

    //=========================================================================
    // Für Elise FM Transmitter Core
    //=========================================================================
    fur_elise_fm_top #(
        .CLK_FREQ_HZ(26_000_000),           // Vahya Mini clock is 26 MHz
        .CLOCKS_PER_16TH(26_000_000 / 8),   // 120 BPM (26M / 8 clocks per 1/16th note)
        .MELODY_LENGTH(82),
        .PWM_FREQ_HZ(50_000)
    ) u_fur_elise (
        .clk           (clk),
        .rst_n         (rst_n),
        .enable        (enable),
        .loop          (loop),
        .clk_2x_enable (clk_2x_en),
        .pwm_in        (pwm_in),
        .fm_out        (fm_out),
        .audio_out     (audio_out),
        .phase_inc_out (phase_inc_out),
        .playing       (playing),
        .melody_end    (melody_end),
        .note_index    (note_index)
    );

    //=========================================================================
    // Output Mapping
    //=========================================================================
    // ESSENTIAL OUTPUTS (Connect to board)
    assign uo_out[0] = fm_out;       // C10: FM output to antenna/RF
    assign uo_out[1] = audio_out;    // D13: Audio output to speaker

    // UNUSED OUTPUTS (Do not connect - for internal signals only)
    assign uo_out[2] = playing;      // Not connected
    assign uo_out[3] = melody_end;   // Not connected
    assign uo_out[7:4] = note_index[3:0]; // Not connected

    // UNUSED BIDIRECTIONAL IOs (Do not connect)
    assign uio_out = phase_inc_out[31:24];  // Not connected
    assign uio_oe  = 8'hFF;  // All outputs (but not connected)

    // Suppress unused input warnings
    wire _unused = &{ui_in, uio_in, note_index[6:4], 1'b0};

endmodule

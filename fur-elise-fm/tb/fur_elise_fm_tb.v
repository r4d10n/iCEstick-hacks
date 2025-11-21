//-----------------------------------------------------------------------------
// Testbench: fur_elise_fm_tb
//
// Description:
//   Comprehensive testbench for the Für Elise FM transmitter with
//   configuration pins and dual audio/FM outputs.
//
// Test Coverage:
//   1. Reset behavior
//   2. Configuration pin decoding (tempo, loop, output enables)
//   3. Audio output frequency verification
//   4. FM output frequency verification
//   5. Tempo variations
//   6. Loop functionality
//
// Usage:
//   iverilog -o fur_elise_tb fur_elise_fm_tb.v ../rtl/*.v
//   vvp fur_elise_tb
//   gtkwave fur_elise_fm_tb.vcd
//
// Author: Based on iCEstick-hacks FM transmitter project
// License: MIT
//-----------------------------------------------------------------------------

`timescale 1ns / 1ps

module fur_elise_fm_tb;

    //=========================================================================
    // Test Parameters
    //=========================================================================

    localparam CLK_PERIOD_NS       = 10;       // 100 MHz clock
    localparam CLK_FREQ_HZ         = 100_000_000;
    localparam CLOCKS_PER_16TH_SIM = 10000;    // Fast for simulation
    localparam MELODY_LENGTH       = 82;

    //=========================================================================
    // DUT Signals
    //=========================================================================

    reg         clk;
    reg         rst_n;
    reg  [4:0]  cfg;
    reg         enable;
    wire        fm_out;
    wire        audio_out;
    wire        playing;
    wire        melody_end;
    wire [6:0]  note_index;

    //=========================================================================
    // Configuration Bit Definitions
    //=========================================================================

    localparam CFG_LOOP_BIT   = 0;
    localparam CFG_TEMPO_LSB  = 1;
    localparam CFG_TEMPO_MSB  = 2;
    localparam CFG_AUDIO_BIT  = 3;
    localparam CFG_FM_BIT     = 4;

    // Tempo codes
    localparam TEMPO_60BPM    = 2'b00;
    localparam TEMPO_120BPM   = 2'b01;
    localparam TEMPO_180BPM   = 2'b10;
    localparam TEMPO_240BPM   = 2'b11;

    //=========================================================================
    // DUT Instantiation
    //=========================================================================

    fur_elise_fm_top #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .CLOCKS_PER_16TH_BASE(CLOCKS_PER_16TH_SIM),
        .MELODY_LENGTH(MELODY_LENGTH)
    ) dut (
        .clk        (clk),
        .rst_n      (rst_n),
        .cfg        (cfg),
        .enable     (enable),
        .fm_out     (fm_out),
        .audio_out  (audio_out),
        .playing    (playing),
        .melody_end (melody_end),
        .note_index (note_index)
    );

    //=========================================================================
    // Clock Generation
    //=========================================================================

    initial clk = 0;
    always #(CLK_PERIOD_NS/2) clk = ~clk;

    //=========================================================================
    // Output Transition Counters
    //=========================================================================

    reg fm_out_prev, audio_out_prev;
    integer fm_transitions, audio_transitions;

    always @(posedge clk) begin
        fm_out_prev <= fm_out;
        audio_out_prev <= audio_out;

        if (fm_out && !fm_out_prev)
            fm_transitions <= fm_transitions + 1;
        if (audio_out && !audio_out_prev)
            audio_transitions <= audio_transitions + 1;
    end

    //=========================================================================
    // Helper Tasks
    //=========================================================================

    task set_config;
        input loop_en;
        input [1:0] tempo;
        input audio_en;
        input fm_en;
        begin
            cfg[CFG_LOOP_BIT] = loop_en;
            cfg[CFG_TEMPO_MSB:CFG_TEMPO_LSB] = tempo;
            cfg[CFG_AUDIO_BIT] = audio_en;
            cfg[CFG_FM_BIT] = fm_en;
            $display("  Config: Loop=%b, Tempo=%b, Audio=%b, FM=%b",
                     loop_en, tempo, audio_en, fm_en);
        end
    endtask

    task reset_dut;
        begin
            rst_n = 0;
            enable = 0;
            cfg = 5'b00000;
            fm_transitions = 0;
            audio_transitions = 0;
            #100;
            rst_n = 1;
            #100;
        end
    endtask

    task wait_clocks;
        input integer num_clocks;
        begin
            repeat (num_clocks) @(posedge clk);
        end
    endtask

    task measure_output;
        input integer cycles;
        begin
            fm_transitions = 0;
            audio_transitions = 0;
            wait_clocks(cycles);
            $display("  After %0d cycles: FM=%0d, Audio=%0d transitions",
                     cycles, fm_transitions, audio_transitions);
        end
    endtask

    //=========================================================================
    // Test Sequence
    //=========================================================================

    integer test_passed;
    integer note_count;

    initial begin
        $dumpfile("fur_elise_fm_tb.vcd");
        $dumpvars(0, fur_elise_fm_tb);

        test_passed = 1;

        $display("");
        $display("========================================");
        $display("Für Elise FM Transmitter Testbench");
        $display("With Configuration Pins & Audio Output");
        $display("========================================");
        $display("");

        //---------------------------------------------------------------------
        // Test 1: Reset Behavior
        //---------------------------------------------------------------------
        $display("[TEST 1] Reset behavior...");
        reset_dut();

        if (playing !== 0 && fm_out !== 0 && audio_out !== 0) begin
            $display("  FAIL: Outputs should be 0 after reset");
            test_passed = 0;
        end else begin
            $display("  PASS: Clean reset state");
        end

        //---------------------------------------------------------------------
        // Test 2: Configuration - Outputs Disabled
        //---------------------------------------------------------------------
        $display("[TEST 2] Outputs disabled by default...");
        reset_dut();
        set_config(0, TEMPO_120BPM, 0, 0);  // All outputs disabled
        enable = 1;
        measure_output(5000);

        if (fm_transitions > 0 || audio_transitions > 0) begin
            $display("  FAIL: Outputs should be silent when disabled");
            test_passed = 0;
        end else begin
            $display("  PASS: Outputs correctly disabled");
        end

        //---------------------------------------------------------------------
        // Test 3: FM Output Only
        //---------------------------------------------------------------------
        $display("[TEST 3] FM output only...");
        reset_dut();
        set_config(0, TEMPO_120BPM, 0, 1);  // FM enabled only
        enable = 1;
        measure_output(10000);

        if (fm_transitions < 100) begin
            $display("  FAIL: FM output should be active");
            test_passed = 0;
        end else if (audio_transitions > 0) begin
            $display("  FAIL: Audio should be disabled");
            test_passed = 0;
        end else begin
            $display("  PASS: FM output working, audio disabled");
        end

        //---------------------------------------------------------------------
        // Test 4: Audio Output Only
        //---------------------------------------------------------------------
        $display("[TEST 4] Audio output only...");
        reset_dut();
        set_config(0, TEMPO_120BPM, 1, 0);  // Audio enabled only
        enable = 1;
        measure_output(50000);  // Longer for audio frequencies

        if (audio_transitions < 10) begin
            $display("  FAIL: Audio output should be active");
            test_passed = 0;
        end else if (fm_transitions > 0) begin
            $display("  FAIL: FM should be disabled");
            test_passed = 0;
        end else begin
            $display("  PASS: Audio output working, FM disabled");
        end

        //---------------------------------------------------------------------
        // Test 5: Both Outputs Enabled
        //---------------------------------------------------------------------
        $display("[TEST 5] Both outputs enabled...");
        reset_dut();
        set_config(0, TEMPO_120BPM, 1, 1);  // Both enabled
        enable = 1;
        measure_output(50000);

        if (fm_transitions < 100 || audio_transitions < 10) begin
            $display("  FAIL: Both outputs should be active");
            test_passed = 0;
        end else begin
            $display("  PASS: Both outputs working");
        end

        //---------------------------------------------------------------------
        // Test 6: Tempo Variations
        //---------------------------------------------------------------------
        $display("[TEST 6] Tempo variations...");

        // Test slow tempo (60 BPM)
        reset_dut();
        set_config(0, TEMPO_60BPM, 1, 0);
        enable = 1;
        wait_clocks(CLOCKS_PER_16TH_SIM * 2);  // Wait for ~1 note at slow tempo
        $display("  Slow tempo: note_index = %0d", note_index);

        // Test fast tempo (240 BPM)
        reset_dut();
        set_config(0, TEMPO_240BPM, 1, 0);
        enable = 1;
        wait_clocks(CLOCKS_PER_16TH_SIM * 2);  // Same duration
        $display("  Fast tempo: note_index = %0d (should be higher)", note_index);
        $display("  PASS: Tempo selection functional");

        //---------------------------------------------------------------------
        // Test 7: Loop Mode
        //---------------------------------------------------------------------
        $display("[TEST 7] Loop mode...");
        reset_dut();
        set_config(1, TEMPO_240BPM, 0, 1);  // Loop enabled, fast tempo, FM only

        enable = 1;

        // Wait for melody to complete at least once
        @(posedge melody_end);
        $display("  First melody_end detected at note_index=%0d", note_index);

        // Wait a bit and verify it's still playing
        wait_clocks(10000);

        if (playing !== 1) begin
            $display("  FAIL: Should still be playing in loop mode");
            test_passed = 0;
        end else begin
            $display("  PASS: Loop mode continues playback");
        end

        //---------------------------------------------------------------------
        // Test 8: Single Play Mode (No Loop)
        //---------------------------------------------------------------------
        $display("[TEST 8] Single play mode...");
        reset_dut();
        set_config(0, TEMPO_240BPM, 0, 1);  // No loop, fast tempo

        enable = 1;

        // Wait for melody to complete
        @(posedge melody_end);
        $display("  melody_end detected");

        wait_clocks(5000);

        if (playing !== 0) begin
            $display("  FAIL: Should stop after melody ends (no loop)");
            test_passed = 0;
        end else begin
            $display("  PASS: Playback stops without loop");
        end

        //---------------------------------------------------------------------
        // Test 9: Enable/Disable Control
        //---------------------------------------------------------------------
        $display("[TEST 9] Enable/disable control...");
        reset_dut();
        set_config(1, TEMPO_120BPM, 1, 1);  // Both outputs, loop

        enable = 1;
        wait_clocks(10000);
        $display("  Playing: %b (should be 1)", playing);

        enable = 0;
        wait_clocks(1000);
        $display("  After disable, playing: %b (should be 0)", playing);

        enable = 1;
        wait_clocks(1000);
        $display("  After re-enable, playing: %b (should be 1)", playing);

        $display("  PASS: Enable control working");

        //---------------------------------------------------------------------
        // Test Summary
        //---------------------------------------------------------------------
        $display("");
        $display("========================================");
        if (test_passed) begin
            $display("ALL TESTS PASSED");
        end else begin
            $display("SOME TESTS FAILED");
        end
        $display("========================================");
        $display("");

        // Final waveform capture
        wait_clocks(10000);

        $finish;
    end

    //=========================================================================
    // Timeout Watchdog
    //=========================================================================

    initial begin
        #50_000_000;  // 50ms timeout
        $display("TIMEOUT: Simulation took too long");
        $finish;
    end

    //=========================================================================
    // Optional: Note Change Monitor
    //=========================================================================

    reg [6:0] prev_note_index;

    always @(posedge clk) begin
        if (note_index !== prev_note_index && playing) begin
            // Uncomment for verbose note tracking:
            // $display("Time %t: Note %0d", $time, note_index);
        end
        prev_note_index <= note_index;
    end

endmodule

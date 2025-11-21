/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none
`timescale 1ns / 1ps

//-----------------------------------------------------------------------------
// Testbench: tb
//
// Description:
//   TinyTapeout testbench for Für Elise FM transmitter.
//
// Usage:
//   iverilog -o tb tb.v ../src/*.v
//   vvp tb
//   gtkwave tb.vcd
//-----------------------------------------------------------------------------

module tb;

    //=========================================================================
    // Test Parameters
    //=========================================================================
    localparam CLK_PERIOD_NS = 20;  // 50 MHz clock

    //=========================================================================
    // DUT Signals
    //=========================================================================
    reg         clk;
    reg         rst_n;
    reg         ena;
    reg  [7:0]  ui_in;
    wire [7:0]  uo_out;
    reg  [7:0]  uio_in;
    wire [7:0]  uio_out;
    wire [7:0]  uio_oe;

    //=========================================================================
    // DUT Instantiation
    //=========================================================================
    tt_um_fur_elise_fm dut (
        .ui_in   (ui_in),
        .uo_out  (uo_out),
        .uio_in  (uio_in),
        .uio_out (uio_out),
        .uio_oe  (uio_oe),
        .ena     (ena),
        .clk     (clk),
        .rst_n   (rst_n)
    );

    //=========================================================================
    // Clock Generation
    //=========================================================================
    initial clk = 0;
    always #(CLK_PERIOD_NS/2) clk = ~clk;

    //=========================================================================
    // Signal Aliases for Readability
    //=========================================================================
    wire fm_out     = uo_out[0];
    wire audio_out  = uo_out[1];
    wire playing    = uo_out[2];
    wire melody_end = uo_out[3];
    wire [3:0] note_idx = uo_out[7:4];
    wire [7:0] phase_msb = uio_out;

    //=========================================================================
    // Output Monitoring
    //=========================================================================
    reg fm_out_prev;
    integer fm_transitions;

    always @(posedge clk) begin
        fm_out_prev <= fm_out;
        if (fm_out && !fm_out_prev)
            fm_transitions <= fm_transitions + 1;
    end

    //=========================================================================
    // Helper Tasks
    //=========================================================================
    task reset_dut;
        begin
            rst_n = 0;
            ena = 0;
            ui_in = 8'h00;
            uio_in = 8'h00;
            fm_transitions = 0;
            #100;
            rst_n = 1;
            ena = 1;
            #100;
        end
    endtask

    task wait_clocks;
        input integer num_clocks;
        begin
            repeat (num_clocks) @(posedge clk);
        end
    endtask

    //=========================================================================
    // Test Sequence
    //=========================================================================
    integer test_passed;

    initial begin
        $dumpfile("tb.vcd");
        $dumpvars(0, tb);

        test_passed = 1;

        $display("");
        $display("================================================");
        $display("TinyTapeout Fur Elise FM Testbench");
        $display("================================================");
        $display("");

        //---------------------------------------------------------------------
        // Test 1: Reset Behavior
        //---------------------------------------------------------------------
        $display("[TEST 1] Reset behavior...");
        reset_dut();

        if (playing !== 0) begin
            $display("  FAIL: playing should be 0 after reset (enable=0)");
            test_passed = 0;
        end else begin
            $display("  PASS: Clean reset state");
        end

        //---------------------------------------------------------------------
        // Test 2: Enable Playback
        //---------------------------------------------------------------------
        $display("[TEST 2] Enable playback...");
        reset_dut();
        ui_in[0] = 1;  // enable
        ui_in[1] = 1;  // loop

        wait_clocks(5000);

        if (!playing) begin
            $display("  FAIL: Should be playing melody");
            test_passed = 0;
        end else begin
            $display("  PASS: Melody playback active");
            $display("  Phase MSB: 0x%02X", phase_msb);
        end

        //---------------------------------------------------------------------
        // Test 3: FM Output Activity
        //---------------------------------------------------------------------
        $display("[TEST 3] FM output activity...");
        fm_transitions = 0;
        wait_clocks(10000);

        if (fm_transitions > 0) begin
            $display("  PASS: FM output toggling (%0d transitions)", fm_transitions);
        end else begin
            $display("  FAIL: No FM output transitions");
            test_passed = 0;
        end

        //---------------------------------------------------------------------
        // Test 4: Clock Doubling
        //---------------------------------------------------------------------
        $display("[TEST 4] Clock doubling...");
        reset_dut();
        ui_in[0] = 1;  // enable
        ui_in[2] = 1;  // clk_2x_enable

        fm_transitions = 0;
        wait_clocks(10000);
        $display("  FM transitions with 2x clock: %0d", fm_transitions);

        //---------------------------------------------------------------------
        // Test 5: Audio Output
        //---------------------------------------------------------------------
        $display("[TEST 5] Audio output...");
        reset_dut();
        ui_in[0] = 1;  // enable

        begin : audio_test
            integer audio_transitions;
            reg audio_prev;
            audio_transitions = 0;
            audio_prev = 0;

            repeat (50000) begin
                @(posedge clk);
                if (audio_out && !audio_prev)
                    audio_transitions = audio_transitions + 1;
                audio_prev = audio_out;
            end

            if (audio_transitions > 0) begin
                $display("  PASS: Audio output active (%0d transitions)", audio_transitions);
            end else begin
                $display("  WARN: No audio transitions detected");
            end
        end

        //---------------------------------------------------------------------
        // Test 6: Loop Mode
        //---------------------------------------------------------------------
        $display("[TEST 6] Loop mode...");
        reset_dut();
        ui_in[0] = 1;  // enable
        ui_in[1] = 1;  // loop

        @(posedge melody_end);
        $display("  First melody_end detected");

        wait_clocks(5000);

        if (!playing) begin
            $display("  FAIL: Should still be playing in loop mode");
            test_passed = 0;
        end else begin
            $display("  PASS: Loop mode continues playback");
        end

        //---------------------------------------------------------------------
        // Test Summary
        //---------------------------------------------------------------------
        $display("");
        $display("================================================");
        if (test_passed) begin
            $display("ALL TESTS PASSED");
        end else begin
            $display("SOME TESTS FAILED");
        end
        $display("================================================");
        $display("");

        wait_clocks(1000);
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

endmodule

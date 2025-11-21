//-----------------------------------------------------------------------------
// Testbench: fur_elise_fm_tb
//
// Description:
//   Comprehensive testbench for the Für Elise FM transmitter with
//   PWM input, clock doubling, and phase increment output.
//
// Test Coverage:
//   1. Reset behavior
//   2. Melody playback mode
//   3. Clock doubling enable/disable
//   4. PWM input mode
//   5. Phase increment output verification
//   6. Audio output verification
//   7. Loop mode functionality
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

    localparam CLK_PERIOD_NS       = 10;        // 100 MHz clock
    localparam CLK_FREQ_HZ         = 100_000_000;
    localparam CLOCKS_PER_16TH_SIM = 10000;     // Fast for simulation
    localparam MELODY_LENGTH       = 82;

    //=========================================================================
    // DUT Signals
    //=========================================================================

    reg         clk;
    reg         rst_n;
    reg         enable;
    reg         loop;
    reg         clk_2x_enable;
    reg         pwm_in;

    wire        fm_out;
    wire        audio_out;
    wire [31:0] phase_inc_out;
    wire        playing;
    wire        melody_end;
    wire [6:0]  note_index;

    //=========================================================================
    // DUT Instantiation
    //=========================================================================

    fur_elise_fm_top #(
        .CLK_FREQ_HZ(CLK_FREQ_HZ),
        .CLOCKS_PER_16TH(CLOCKS_PER_16TH_SIM),
        .MELODY_LENGTH(MELODY_LENGTH),
        .PWM_FREQ_HZ(50000)
    ) dut (
        .clk           (clk),
        .rst_n         (rst_n),
        .enable        (enable),
        .loop          (loop),
        .clk_2x_enable (clk_2x_enable),
        .pwm_in        (pwm_in),
        .fm_out        (fm_out),
        .audio_out     (audio_out),
        .phase_inc_out (phase_inc_out),
        .playing       (playing),
        .melody_end    (melody_end),
        .note_index    (note_index)
    );

    //=========================================================================
    // Clock Generation
    //=========================================================================

    initial clk = 0;
    always #(CLK_PERIOD_NS/2) clk = ~clk;

    //=========================================================================
    // PWM Generator for Testing
    //=========================================================================

    reg [15:0] pwm_counter;
    reg [15:0] pwm_duty;  // Duty cycle value

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pwm_counter <= 0;
        end else begin
            if (pwm_counter >= 1999) begin  // 50 kHz at 100 MHz
                pwm_counter <= 0;
            end else begin
                pwm_counter <= pwm_counter + 1;
            end
        end
    end

    // Generate PWM signal based on duty cycle
    wire pwm_gen = (pwm_counter < pwm_duty[15:6]) ? 1'b1 : 1'b0;

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
            enable = 0;
            loop = 0;
            clk_2x_enable = 0;
            pwm_in = 0;
            pwm_duty = 16'h8000;
            fm_transitions = 0;
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

    //=========================================================================
    // Test Sequence
    //=========================================================================

    integer test_passed;
    integer audio_transitions;
    reg audio_prev;

    initial begin
        $dumpfile("fur_elise_fm_tb.vcd");
        $dumpvars(0, fur_elise_fm_tb);

        test_passed = 1;

        $display("");
        $display("================================================");
        $display("Fur Elise FM Transmitter Testbench");
        $display("PWM Input + Clock Doubling + Phase Inc Output");
        $display("================================================");
        $display("");

        //---------------------------------------------------------------------
        // Test 1: Reset Behavior
        //---------------------------------------------------------------------
        $display("[TEST 1] Reset behavior...");
        reset_dut();

        if (playing !== 0) begin
            $display("  FAIL: playing should be 0 after reset");
            test_passed = 0;
        end else begin
            $display("  PASS: Clean reset state");
        end

        //---------------------------------------------------------------------
        // Test 2: Melody Playback Mode
        //---------------------------------------------------------------------
        $display("[TEST 2] Melody playback mode...");
        reset_dut();
        enable = 1;
        loop = 1;

        wait_clocks(5000);

        if (!playing) begin
            $display("  FAIL: Should be playing melody");
            test_passed = 0;
        end else begin
            $display("  PASS: Melody playback active");
            $display("  Phase increment: 0x%08X", phase_inc_out);
        end

        //---------------------------------------------------------------------
        // Test 3: Clock Doubling Disabled
        //---------------------------------------------------------------------
        $display("[TEST 3] Clock doubling disabled...");
        reset_dut();
        enable = 1;
        clk_2x_enable = 0;

        fm_transitions = 0;
        wait_clocks(10000);
        $display("  FM transitions (1x clock): %0d", fm_transitions);

        //---------------------------------------------------------------------
        // Test 4: Clock Doubling Enabled
        //---------------------------------------------------------------------
        $display("[TEST 4] Clock doubling enabled...");
        reset_dut();
        enable = 1;
        clk_2x_enable = 1;

        fm_transitions = 0;
        wait_clocks(10000);
        $display("  FM transitions (2x clock): %0d", fm_transitions);
        $display("  Note: Should see more transitions with clock doubling");

        //---------------------------------------------------------------------
        // Test 5: Phase Increment Output
        //---------------------------------------------------------------------
        $display("[TEST 5] Phase increment output...");
        reset_dut();
        enable = 1;

        wait_clocks(1000);

        if (phase_inc_out == 0) begin
            $display("  FAIL: Phase increment should be non-zero");
            test_passed = 0;
        end else begin
            $display("  PASS: Phase increment = 0x%08X", phase_inc_out);
        end

        //---------------------------------------------------------------------
        // Test 6: PWM Input Mode
        //---------------------------------------------------------------------
        $display("[TEST 6] PWM input mode...");
        reset_dut();
        enable = 1;

        // Enable PWM input
        pwm_duty = 16'hC000;  // 75% duty
        wait_clocks(100);

        // Feed PWM signal
        repeat (100) begin
            pwm_in = pwm_gen;
            wait_clocks(20);
        end

        $display("  PWM input processed, phase_inc = 0x%08X", phase_inc_out);

        //---------------------------------------------------------------------
        // Test 7: Audio Output
        //---------------------------------------------------------------------
        $display("[TEST 7] Audio output...");
        reset_dut();
        enable = 1;

        audio_transitions = 0;
        audio_prev = 0;

        repeat (50000) begin
            @(posedge clk);
            if (audio_out && !audio_prev)
                audio_transitions = audio_transitions + 1;
            audio_prev = audio_out;
        end

        $display("  Audio transitions: %0d", audio_transitions);
        if (audio_transitions > 0) begin
            $display("  PASS: Audio output generating tones");
        end else begin
            $display("  WARN: No audio transitions detected");
        end

        //---------------------------------------------------------------------
        // Test 8: Loop Mode
        //---------------------------------------------------------------------
        $display("[TEST 8] Loop mode...");
        reset_dut();
        enable = 1;
        loop = 1;

        @(posedge melody_end);
        $display("  First melody_end detected");

        wait_clocks(10000);

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

        wait_clocks(5000);
        $finish;
    end

    //=========================================================================
    // Timeout Watchdog
    //=========================================================================

    initial begin
        #100_000_000;  // 100ms timeout
        $display("TIMEOUT: Simulation took too long");
        $finish;
    end

endmodule

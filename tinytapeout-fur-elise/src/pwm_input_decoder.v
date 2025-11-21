//-----------------------------------------------------------------------------
// Module: pwm_input_decoder
//
// Description:
//   Decodes a PWM (Pulse Width Modulation) input signal into a digital sample
//   value. The PWM duty cycle is converted to a signed 16-bit audio sample.
//
// Theory of Operation:
//   PWM encodes amplitude as pulse width:
//   - 0% duty cycle   → minimum value (-32768)
//   - 50% duty cycle  → zero (0)
//   - 100% duty cycle → maximum value (+32767)
//
//   The decoder counts clock cycles while PWM is high during each PWM period,
//   then converts this count to a signed sample value.
//
// PWM Input Specification:
//   - Expected PWM frequency: 20 kHz - 100 kHz typical
//   - Higher PWM frequency = better audio quality but lower resolution
//   - For 100 MHz clock and 50 kHz PWM: 2000 counts per period = ~11 bit resolution
//
// Usage:
//   - Connect external PWM audio source to pwm_in
//   - sample_out provides 16-bit signed audio sample
//   - sample_valid pulses when new sample is ready
//
// Author: Based on iCEstick-hacks FM transmitter project
// Target: GF180MCU ASIC (architecture independent)
// License: MIT
//-----------------------------------------------------------------------------

module pwm_input_decoder #(
    parameter CLK_FREQ_HZ = 100_000_000,   // System clock frequency
    parameter PWM_FREQ_HZ = 50_000,         // Expected PWM frequency
    parameter SAMPLE_BITS = 16              // Output sample width
)(
    input  wire                      clk,
    input  wire                      rst_n,
    input  wire                      enable,
    input  wire                      pwm_in,        // PWM input signal
    output reg  signed [SAMPLE_BITS-1:0] sample_out,   // Decoded audio sample
    output reg                       sample_valid,  // New sample ready
    output wire [15:0]               debug_count    // Debug: PWM high count
);

    //-------------------------------------------------------------------------
    // Constants
    //-------------------------------------------------------------------------
    // Maximum count per PWM period
    localparam MAX_COUNT = CLK_FREQ_HZ / PWM_FREQ_HZ;  // e.g., 100M/50k = 2000
    localparam COUNT_WIDTH = $clog2(MAX_COUNT + 1);

    // Timeout for edge detection (if no edges, assume DC input)
    localparam TIMEOUT_COUNT = MAX_COUNT * 2;

    //-------------------------------------------------------------------------
    // Input Synchronization
    //-------------------------------------------------------------------------
    reg pwm_sync1, pwm_sync2, pwm_sync3;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            pwm_sync1 <= 1'b0;
            pwm_sync2 <= 1'b0;
            pwm_sync3 <= 1'b0;
        end else begin
            pwm_sync1 <= pwm_in;
            pwm_sync2 <= pwm_sync1;
            pwm_sync3 <= pwm_sync2;
        end
    end

    wire pwm_rising  = pwm_sync2 & ~pwm_sync3;
    wire pwm_falling = ~pwm_sync2 & pwm_sync3;
    wire pwm_level   = pwm_sync2;

    //-------------------------------------------------------------------------
    // PWM Period and High-Time Counters
    //-------------------------------------------------------------------------
    reg [COUNT_WIDTH:0] period_counter;   // Total period count
    reg [COUNT_WIDTH:0] high_counter;     // High time count
    reg [COUNT_WIDTH:0] captured_high;    // Captured high count
    reg [COUNT_WIDTH:0] captured_period;  // Captured period count
    reg measuring;                         // Currently measuring

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            period_counter <= 0;
            high_counter <= 0;
            captured_high <= 0;
            captured_period <= MAX_COUNT;  // Default to expected period
            measuring <= 1'b0;
            sample_valid <= 1'b0;
        end else if (!enable) begin
            period_counter <= 0;
            high_counter <= 0;
            measuring <= 1'b0;
            sample_valid <= 1'b0;
        end else begin
            sample_valid <= 1'b0;  // Default

            // Increment period counter
            if (period_counter < TIMEOUT_COUNT) begin
                period_counter <= period_counter + 1;
            end

            // Count high time
            if (pwm_level && period_counter < TIMEOUT_COUNT) begin
                high_counter <= high_counter + 1;
            end

            // Detect rising edge - start of new period
            if (pwm_rising) begin
                if (measuring) begin
                    // End of period - capture measurements
                    captured_high <= high_counter;
                    captured_period <= period_counter;
                    sample_valid <= 1'b1;
                end
                // Start new period
                period_counter <= 0;
                high_counter <= 0;
                measuring <= 1'b1;
            end

            // Timeout - no edges detected, assume DC
            if (period_counter >= TIMEOUT_COUNT) begin
                if (pwm_level) begin
                    // Constant high - maximum value
                    captured_high <= MAX_COUNT;
                    captured_period <= MAX_COUNT;
                end else begin
                    // Constant low - minimum value
                    captured_high <= 0;
                    captured_period <= MAX_COUNT;
                end
                sample_valid <= measuring;  // Only pulse if we were measuring
                measuring <= 1'b0;
            end
        end
    end

    //-------------------------------------------------------------------------
    // Duty Cycle to Sample Conversion
    //-------------------------------------------------------------------------
    // Convert duty cycle (0-100%) to signed sample (-32768 to +32767)
    //
    // duty_ratio = captured_high / captured_period  (0.0 to 1.0)
    // sample = (duty_ratio - 0.5) * 65535
    //        = (captured_high * 65536 / captured_period) - 32768
    //
    // Using fixed-point arithmetic to avoid division:
    // sample = (captured_high << 16) / captured_period - 32768

    wire [COUNT_WIDTH+16:0] scaled_high = {captured_high, 16'b0};  // high << 16
    wire [COUNT_WIDTH+16:0] duty_scaled;

    // Simple division approximation (shift-based for synthesis)
    // For accurate division, use iterative divider or lookup table
    // Here we use the fact that period is relatively constant

    // Approximate: assume period ≈ MAX_COUNT for simplicity
    // duty_scaled ≈ (captured_high << 16) >> log2(MAX_COUNT)
    // For MAX_COUNT = 2000, log2(2000) ≈ 11

    localparam PERIOD_SHIFT = $clog2(MAX_COUNT);

    wire [31:0] duty_approx = scaled_high >> PERIOD_SHIFT;

    // Convert to signed: subtract 32768 (0x8000)
    wire signed [SAMPLE_BITS-1:0] sample_calc = duty_approx[SAMPLE_BITS-1:0] - 16'sd32768;

    // Register the output
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sample_out <= 16'sd0;
        end else if (sample_valid) begin
            sample_out <= sample_calc;
        end
    end

    // Debug output
    assign debug_count = captured_high[15:0];

endmodule

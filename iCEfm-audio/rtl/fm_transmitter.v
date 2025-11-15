// FM Transmitter Core Module
// Direct Digital Synthesis (DDS) based FM modulator
//
// This module implements a phase accumulator-based FM transmitter
// Based on the principle described by Mike Field (Hamsterworks)
//
// The output is a jittery pulse train with configurable center frequency
// and modulation. The upper bit of a 32-bit phase accumulator creates
// the output signal that toggles at the desired frequency.
//
// Author: Based on iCEstick-hacks FM transmitter project
// License: MIT

module fm_transmitter #(
    parameter CLOCK_FREQ_MHZ = 255      // High-speed clock frequency in MHz
)(
    input  wire         clk,            // High-speed clock (e.g., 240-320 MHz)
    input  wire         rst,
    input  wire  [15:0] audio_sample,   // 16-bit signed audio sample
    input  wire  [31:0] center_freq_inc,// Center frequency phase increment
    input  wire  [31:0] deviation_scale,// Frequency deviation scaling factor
    input  wire         sample_valid,   // Audio sample valid strobe
    output wire         antenna,        // FM output signal
    output wire         sample_request  // Request next audio sample
);

    // 32-bit phase accumulator for DDS
    reg [31:0] phase_accumulator = 32'd0;

    // Current modulation value (scaled audio sample)
    reg [31:0] modulation = 32'd0;

    // Phase increment calculation
    // phase_inc = center_freq + (audio_sample * deviation_scale)
    wire [31:0] signed_audio = {{16{audio_sample[15]}}, audio_sample};
    wire [63:0] deviation_product = $signed(signed_audio) * $signed(deviation_scale);
    wire [31:0] deviation = deviation_product[47:16];  // Take middle 32 bits
    wire [31:0] phase_increment = center_freq_inc + deviation;

    // Output is the MSB of the phase accumulator
    assign antenna = phase_accumulator[31];

    // Sample rate divider - request new sample every N clocks
    // For 255 MHz clock and 48 kHz audio: 255_000_000 / 48_000 = 5312.5
    // Using 5313 for close approximation
    localparam SAMPLE_PERIOD = CLOCK_FREQ_MHZ * 1_000_000 / 48000;
    reg [$clog2(SAMPLE_PERIOD+1)-1:0] sample_counter = 0;

    assign sample_request = (sample_counter == 0);

    always @(posedge clk) begin
        if (rst) begin
            phase_accumulator <= 32'd0;
            modulation <= 32'd0;
            sample_counter <= 0;
        end else begin
            // Update phase accumulator every clock cycle
            phase_accumulator <= phase_accumulator + phase_increment;

            // Sample counter for audio rate
            if (sample_counter == SAMPLE_PERIOD - 1) begin
                sample_counter <= 0;
            end else begin
                sample_counter <= sample_counter + 1;
            end

            // Update modulation when new sample arrives
            if (sample_valid) begin
                modulation <= deviation;
            end
        end
    end

endmodule

// FM Audio Transmitter - Top Level Module
//
// UART-based FM transmitter for streaming audio
// Compatible with iCE40-HX8K, iCE40-UP5K, and ECP5 FPGAs
//
// Protocol:
//   Configuration mode (first 9 bytes received):
//     Byte 0:    Command (0xC0 = Configure)
//     Bytes 1-4: Center frequency phase increment (32-bit, little-endian)
//     Bytes 5-8: Deviation scale factor (32-bit, little-endian)
//
//   Audio streaming mode (after configuration):
//     Bytes arrive in pairs (16-bit samples, little-endian)
//     High byte first, then low byte
//
// Example frequency calculations (for 255 MHz clock):
//   phase_inc = (desired_freq_Hz / 255_000_000) * 2^32
//
//   For 91.0 MHz: phase_inc = 1,538,160,066
//   For 100.0 MHz: phase_inc = 1,688,849,860
//   For 108.0 MHz: phase_inc = 1,823,958,409
//
// Deviation calculation:
//   For ±75 kHz deviation with 16-bit audio:
//   deviation_scale = (75_000 / 255_000_000) * 2^32 / 32768 = 39,406
//
// Author: Based on iCEstick-hacks FM transmitter project
// License: MIT

module fm_audio_top #(
    parameter INPUT_FREQ_MHZ = 12,      // Board clock frequency
    parameter OUTPUT_FREQ_MHZ = 255,    // PLL output frequency
    parameter BAUD_RATE = 115200        // UART baud rate
)(
    input  wire clk_in,         // Board clock input
    input  wire rst_n,          // Active-low reset
    input  wire uart_rx,        // UART receive pin
    output wire antenna,        // FM antenna output
    output wire led_locked,     // PLL lock indicator
    output wire led_configured, // Configuration complete indicator
    output wire led_active      // Audio streaming indicator
);

    //--------------------------------------------------------------------
    // Clock and Reset
    //--------------------------------------------------------------------
    wire clk_high;              // High-speed clock from PLL
    wire pll_locked;
    wire rst = ~rst_n;

    pll_wrapper #(
        .INPUT_FREQ_MHZ(INPUT_FREQ_MHZ),
        .OUTPUT_FREQ_MHZ(OUTPUT_FREQ_MHZ)
    ) pll (
        .clk_in(clk_in),
        .clk_out(clk_high),
        .locked(pll_locked)
    );

    assign led_locked = pll_locked;

    //--------------------------------------------------------------------
    // UART Receiver
    //--------------------------------------------------------------------
    wire [7:0] uart_data;
    wire uart_valid;

    uart_rx #(
        .CLOCK_FREQ(INPUT_FREQ_MHZ * 1_000_000),
        .BAUD_RATE(BAUD_RATE)
    ) uart (
        .clk(clk_in),
        .rst(rst),
        .rx(uart_rx),
        .data_out(uart_data),
        .data_valid(uart_valid),
        .busy()
    );

    //--------------------------------------------------------------------
    // Configuration State Machine
    //--------------------------------------------------------------------
    localparam STATE_CONFIG = 2'd0;
    localparam STATE_AUDIO_HIGH = 2'd1;
    localparam STATE_AUDIO_LOW = 2'd2;

    reg [1:0] state = STATE_CONFIG;
    reg [3:0] config_byte_count = 0;
    reg [31:0] center_freq_inc = 32'd1538160066;  // Default: 91.0 MHz
    reg [31:0] deviation_scale = 32'd39406;       // Default: ±75 kHz
    reg [7:0] audio_high_byte = 0;
    reg configured = 0;

    // Audio sample buffer
    reg [15:0] audio_sample = 16'd0;
    reg audio_sample_valid = 1'b0;

    // FIFO for audio samples
    wire [15:0] fifo_rd_data;
    wire fifo_empty;
    wire fifo_full;
    wire [8:0] fifo_count;

    fifo #(
        .DATA_WIDTH(16),
        .DEPTH(512)
    ) audio_fifo (
        .clk(clk_in),
        .rst(rst),
        .wr_data(audio_sample),
        .wr_en(audio_sample_valid),
        .full(fifo_full),
        .rd_data(fifo_rd_data),
        .rd_en(sample_request_sync),
        .empty(fifo_empty),
        .count(fifo_count)
    );

    assign led_configured = configured;
    assign led_active = !fifo_empty;

    // UART receiver state machine
    always @(posedge clk_in) begin
        if (rst) begin
            state <= STATE_CONFIG;
            config_byte_count <= 0;
            configured <= 0;
            audio_sample_valid <= 0;
        end else begin
            audio_sample_valid <= 0;  // Default: pulse for one cycle

            if (uart_valid) begin
                case (state)
                    STATE_CONFIG: begin
                        // Configuration bytes
                        case (config_byte_count)
                            4'd0: begin
                                // Command byte (should be 0xC0 for configure)
                                if (uart_data == 8'hC0) begin
                                    config_byte_count <= config_byte_count + 1;
                                end
                            end
                            // Center frequency (bytes 1-4, little-endian)
                            4'd1: center_freq_inc[7:0] <= uart_data;
                            4'd2: center_freq_inc[15:8] <= uart_data;
                            4'd3: center_freq_inc[23:16] <= uart_data;
                            4'd4: begin
                                center_freq_inc[31:24] <= uart_data;
                                config_byte_count <= config_byte_count + 1;
                            end
                            // Deviation scale (bytes 5-8, little-endian)
                            4'd5: deviation_scale[7:0] <= uart_data;
                            4'd6: deviation_scale[15:8] <= uart_data;
                            4'd7: deviation_scale[23:16] <= uart_data;
                            4'd8: begin
                                deviation_scale[31:24] <= uart_data;
                                configured <= 1;
                                state <= STATE_AUDIO_HIGH;
                                config_byte_count <= 0;
                            end
                            default: config_byte_count <= config_byte_count + 1;
                        endcase

                        // Allow reconfiguration or skip to audio mode
                        if (config_byte_count > 0 && config_byte_count < 9) begin
                            config_byte_count <= config_byte_count + 1;
                        end
                    end

                    STATE_AUDIO_HIGH: begin
                        // Receive high byte of 16-bit sample
                        audio_high_byte <= uart_data;
                        state <= STATE_AUDIO_LOW;
                    end

                    STATE_AUDIO_LOW: begin
                        // Receive low byte and form complete sample
                        audio_sample <= {audio_high_byte, uart_data};
                        audio_sample_valid <= 1'b1;
                        state <= STATE_AUDIO_HIGH;
                    end

                    default: state <= STATE_CONFIG;
                endcase
            end
        end
    end

    //--------------------------------------------------------------------
    // Clock Domain Crossing for Sample Request
    //--------------------------------------------------------------------
    wire sample_request;
    reg sample_request_r1 = 0;
    reg sample_request_r2 = 0;
    reg sample_request_sync = 0;

    // Synchronize sample request from high-speed to low-speed domain
    always @(posedge clk_in) begin
        sample_request_r1 <= sample_request;
        sample_request_r2 <= sample_request_r1;
        sample_request_sync <= sample_request_r2 & ~sample_request_r1;
    end

    //--------------------------------------------------------------------
    // Clock Domain Crossing for Audio Data
    //--------------------------------------------------------------------
    reg [15:0] fifo_data_sync1 = 0;
    reg [15:0] fifo_data_sync2 = 0;
    reg fifo_empty_sync1 = 1;
    reg fifo_empty_sync2 = 1;

    always @(posedge clk_high) begin
        fifo_data_sync1 <= fifo_rd_data;
        fifo_data_sync2 <= fifo_data_sync1;
        fifo_empty_sync1 <= fifo_empty;
        fifo_empty_sync2 <= fifo_empty_sync1;
    end

    //--------------------------------------------------------------------
    // FM Transmitter Core
    //--------------------------------------------------------------------
    wire [15:0] current_audio = fifo_empty_sync2 ? 16'd0 : fifo_data_sync2;

    fm_transmitter #(
        .CLOCK_FREQ_MHZ(OUTPUT_FREQ_MHZ)
    ) fm_tx (
        .clk(clk_high),
        .rst(rst | ~pll_locked),
        .audio_sample(current_audio),
        .center_freq_inc(center_freq_inc),
        .deviation_scale(deviation_scale),
        .sample_valid(1'b1),
        .antenna(antenna),
        .sample_request(sample_request)
    );

endmodule

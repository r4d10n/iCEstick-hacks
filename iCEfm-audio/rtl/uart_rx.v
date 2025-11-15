// UART Receiver Module
// Configurable baud rate via clock divider
// 8 data bits, 1 stop bit, no parity
//
// Author: Based on iCEstick-hacks FM transmitter project
// License: MIT

module uart_rx #(
    parameter CLOCK_FREQ = 12_000_000,  // Input clock frequency
    parameter BAUD_RATE = 115200         // UART baud rate
)(
    input  wire       clk,
    input  wire       rst,
    input  wire       rx,
    output reg  [7:0] data_out,
    output reg        data_valid,
    output wire       busy
);

    localparam CYCLES_PER_BIT = CLOCK_FREQ / BAUD_RATE;
    localparam HALF_CYCLES = CYCLES_PER_BIT / 2;

    // State machine
    localparam IDLE  = 3'd0;
    localparam START = 3'd1;
    localparam DATA  = 3'd2;
    localparam STOP  = 3'd3;

    reg [2:0] state = IDLE;
    reg [15:0] cycle_counter = 0;
    reg [2:0] bit_counter = 0;
    reg [7:0] shift_reg = 0;

    assign busy = (state != IDLE);

    // Synchronize RX input to avoid metastability
    reg rx_sync1 = 1'b1;
    reg rx_sync2 = 1'b1;

    always @(posedge clk) begin
        if (rst) begin
            rx_sync1 <= 1'b1;
            rx_sync2 <= 1'b1;
        end else begin
            rx_sync1 <= rx;
            rx_sync2 <= rx_sync1;
        end
    end

    // Main state machine
    always @(posedge clk) begin
        if (rst) begin
            state <= IDLE;
            cycle_counter <= 0;
            bit_counter <= 0;
            data_out <= 8'd0;
            data_valid <= 1'b0;
            shift_reg <= 8'd0;
        end else begin
            data_valid <= 1'b0;  // Default: pulse for one cycle

            case (state)
                IDLE: begin
                    cycle_counter <= 0;
                    bit_counter <= 0;
                    if (rx_sync2 == 1'b0) begin  // Start bit detected
                        state <= START;
                    end
                end

                START: begin
                    if (cycle_counter == HALF_CYCLES - 1) begin
                        // Sample in the middle of start bit
                        if (rx_sync2 == 1'b0) begin
                            cycle_counter <= 0;
                            state <= DATA;
                        end else begin
                            // False start, go back to idle
                            state <= IDLE;
                        end
                    end else begin
                        cycle_counter <= cycle_counter + 1;
                    end
                end

                DATA: begin
                    if (cycle_counter == CYCLES_PER_BIT - 1) begin
                        cycle_counter <= 0;
                        shift_reg <= {rx_sync2, shift_reg[7:1]};  // LSB first

                        if (bit_counter == 7) begin
                            state <= STOP;
                        end else begin
                            bit_counter <= bit_counter + 1;
                        end
                    end else begin
                        cycle_counter <= cycle_counter + 1;
                    end
                end

                STOP: begin
                    if (cycle_counter == CYCLES_PER_BIT - 1) begin
                        if (rx_sync2 == 1'b1) begin  // Valid stop bit
                            data_out <= shift_reg;
                            data_valid <= 1'b1;
                        end
                        state <= IDLE;
                    end else begin
                        cycle_counter <= cycle_counter + 1;
                    end
                end

                default: begin
                    state <= IDLE;
                end
            endcase
        end
    end

endmodule

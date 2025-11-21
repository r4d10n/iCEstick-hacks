//-----------------------------------------------------------------------------
// Module: melody_sequencer
//
// Description:
//   Controls playback of the melody stored in the ROM. Manages timing for
//   note durations and sequences through the melody. Supports looping and
//   enable/disable control.
//
// Features:
//   - Configurable base note duration (tempo control)
//   - Duration decoding (16th, 8th, quarter, half, whole notes)
//   - Loop mode for continuous playback
//   - Play/pause control via enable input
//   - End-of-melody detection
//
// Timing Calculation:
//   Base duration is set by CLOCKS_PER_16TH parameter.
//   Other durations are multiples:
//     16th note = 1 × base
//     8th note  = 2 × base
//     Quarter   = 4 × base
//     Half      = 8 × base
//     Whole     = 16 × base
//
// Example (100 MHz clock, 120 BPM tempo):
//   Quarter note = 60/120 = 0.5 seconds = 50,000,000 clocks
//   16th note = 0.5/4 = 0.125 seconds = 12,500,000 clocks
//   CLOCKS_PER_16TH = 12,500,000
//
// Design Notes:
//   - Architecture independent (pure behavioral Verilog)
//   - Single clock domain
//   - Fully synchronous with async reset
//   - Suitable for ASIC synthesis (GF180MCU target)
//
// Author: Based on iCEstick-hacks FM transmitter project
// Target: GF180MCU ASIC (architecture independent)
// License: MIT
//-----------------------------------------------------------------------------

module melody_sequencer #(
    parameter CLOCKS_PER_16TH = 12_500_000,  // Default clock cycles per 16th note
    parameter MELODY_LENGTH   = 82,          // Number of notes in melody
    parameter ADDR_WIDTH      = 7            // log2(max melody length)
)(
    input  wire                    clk,
    input  wire                    rst_n,
    input  wire                    enable,      // Enable playback
    input  wire                    loop,        // Loop at end of melody
    input  wire [31:0]             tempo_clocks,// Runtime tempo (clocks per 16th)
                                               // If 0, uses CLOCKS_PER_16TH parameter
    input  wire [15:0]             note_data,   // Data from melody ROM
    output reg  [ADDR_WIDTH-1:0]   note_addr,   // Address to melody ROM
    output reg  signed [7:0]       note_pitch,  // Current note pitch
    output reg                     note_valid,  // Note pitch is valid
    output reg                     playing,     // Melody is currently playing
    output wire                    melody_end   // Pulse at end of melody
);

    //-------------------------------------------------------------------------
    // State Machine States
    //-------------------------------------------------------------------------
    localparam STATE_IDLE     = 2'd0;  // Waiting for enable
    localparam STATE_FETCH    = 2'd1;  // Fetching note from ROM
    localparam STATE_PLAY     = 2'd2;  // Playing current note
    localparam STATE_NEXT     = 2'd3;  // Advancing to next note

    reg [1:0] state;
    reg [1:0] state_next;

    //-------------------------------------------------------------------------
    // Duration Decoding
    //-------------------------------------------------------------------------
    // Duration codes from ROM:
    //   0 = 16th,  1 = 8th,  2 = quarter,  3 = half,  4 = whole
    //   5 = dotted 8th (1.5x 8th)

    localparam [5:0] DUR_16TH    = 6'd0;
    localparam [5:0] DUR_8TH     = 6'd1;
    localparam [5:0] DUR_QUARTER = 6'd2;
    localparam [5:0] DUR_HALF    = 6'd3;
    localparam [5:0] DUR_WHOLE   = 6'd4;
    localparam [5:0] DUR_DOT8TH  = 6'd5;

    // Duration multipliers (relative to 16th note)
    function [4:0] duration_multiplier;
        input [5:0] dur_code;
        begin
            case (dur_code)
                DUR_16TH:    duration_multiplier = 5'd1;   // 1x
                DUR_8TH:     duration_multiplier = 5'd2;   // 2x
                DUR_QUARTER: duration_multiplier = 5'd4;   // 4x
                DUR_HALF:    duration_multiplier = 5'd8;   // 8x
                DUR_WHOLE:   duration_multiplier = 5'd16;  // 16x
                DUR_DOT8TH:  duration_multiplier = 5'd3;   // 1.5x 8th = 3x 16th
                default:     duration_multiplier = 5'd2;   // Default to 8th
            endcase
        end
    endfunction

    //-------------------------------------------------------------------------
    // Timing Counter
    //-------------------------------------------------------------------------
    // Counts clock cycles for note duration

    reg [31:0] duration_counter;
    wire [31:0] target_duration;
    wire duration_done;

    // Extract duration code from note data
    wire [5:0] note_duration = note_data[5:0];
    wire [4:0] dur_mult = duration_multiplier(note_duration);

    // Calculate target duration in clock cycles
    // Use runtime tempo if provided, otherwise use parameter default
    wire [31:0] active_tempo = (tempo_clocks != 32'd0) ? tempo_clocks : CLOCKS_PER_16TH;
    assign target_duration = active_tempo * dur_mult;

    // Duration complete when counter reaches target
    assign duration_done = (duration_counter >= target_duration - 1);

    //-------------------------------------------------------------------------
    // Note Address Counter
    //-------------------------------------------------------------------------
    reg melody_finished;
    assign melody_end = melody_finished;

    //-------------------------------------------------------------------------
    // State Machine - Sequential
    //-------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= STATE_IDLE;
        end else begin
            state <= state_next;
        end
    end

    //-------------------------------------------------------------------------
    // State Machine - Combinational
    //-------------------------------------------------------------------------
    always @(*) begin
        state_next = state;

        case (state)
            STATE_IDLE: begin
                if (enable) begin
                    state_next = STATE_FETCH;
                end
            end

            STATE_FETCH: begin
                // ROM has 1-cycle latency, wait for data
                state_next = STATE_PLAY;
            end

            STATE_PLAY: begin
                if (!enable) begin
                    state_next = STATE_IDLE;
                end else if (duration_done) begin
                    state_next = STATE_NEXT;
                end
            end

            STATE_NEXT: begin
                if (note_addr >= MELODY_LENGTH - 1) begin
                    if (loop) begin
                        state_next = STATE_FETCH;  // Loop back to start
                    end else begin
                        state_next = STATE_IDLE;   // Stop at end
                    end
                end else begin
                    state_next = STATE_FETCH;      // Next note
                end
            end

            default: begin
                state_next = STATE_IDLE;
            end
        endcase
    end

    //-------------------------------------------------------------------------
    // Datapath - Sequential
    //-------------------------------------------------------------------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            note_addr        <= {ADDR_WIDTH{1'b0}};
            note_pitch       <= 8'h80;  // REST
            note_valid       <= 1'b0;
            playing          <= 1'b0;
            melody_finished  <= 1'b0;
            duration_counter <= 32'd0;
        end else begin
            // Default: clear one-cycle pulses
            melody_finished <= 1'b0;

            case (state)
                STATE_IDLE: begin
                    playing <= 1'b0;
                    note_valid <= 1'b0;
                    duration_counter <= 32'd0;

                    if (enable) begin
                        // Starting playback, reset to beginning
                        note_addr <= {ADDR_WIDTH{1'b0}};
                    end
                end

                STATE_FETCH: begin
                    // Waiting for ROM data (1 cycle latency)
                    // ROM address is already set
                    playing <= 1'b1;
                    note_valid <= 1'b0;
                    duration_counter <= 32'd0;
                end

                STATE_PLAY: begin
                    // Latch note data from ROM
                    note_pitch <= note_data[15:8];
                    note_valid <= 1'b1;
                    playing <= 1'b1;

                    // Count duration
                    if (!duration_done) begin
                        duration_counter <= duration_counter + 1;
                    end
                end

                STATE_NEXT: begin
                    // Advance to next note
                    note_valid <= 1'b0;
                    duration_counter <= 32'd0;

                    if (note_addr >= MELODY_LENGTH - 1) begin
                        if (loop) begin
                            note_addr <= {ADDR_WIDTH{1'b0}};  // Restart
                        end else begin
                            melody_finished <= 1'b1;
                        end
                    end else begin
                        note_addr <= note_addr + 1;
                    end
                end

                default: begin
                    note_addr <= {ADDR_WIDTH{1'b0}};
                    note_valid <= 1'b0;
                    playing <= 1'b0;
                end
            endcase
        end
    end

endmodule

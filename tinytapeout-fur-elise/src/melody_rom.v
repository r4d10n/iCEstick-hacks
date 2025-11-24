//-----------------------------------------------------------------------------
// Module: melody_rom
//
// Description:
//   Read-only memory containing Beethoven's "Für Elise" melody encoded as
//   note data. Each entry contains a note pitch (as semitone offset from A4)
//   and duration code.
//
// Design Notes:
//   - Architecture independent (no vendor primitives)
//   - Synthesizes to LUT-based ROM
//   - Notes encoded as signed offset from A4 (440 Hz)
//   - Duration encoded as power-of-2 multiplier
//
// Encoding Format:
//   [15:8] = Note pitch (signed, semitones from A4, 0x80 = REST)
//   [7:6]  = Reserved
//   [5:0]  = Duration code (0=16th, 1=8th, 2=quarter, 3=half, 4=whole, etc.)
//
// Note Reference (semitones from A4):
//   C4  = -9    D4  = -7    E4  = -5    F4  = -4
//   G4  = -2    G#4 = -1    A4  =  0    A#4 = +1
//   B4  = +2    C5  = +3    D5  = +5    D#5 = +6
//   E5  = +7    F5  = +8    G5  = +10   A5  = +12
//
// Author: Based on iCEstick-hacks FM transmitter project
// Target: GF180MCU ASIC (architecture independent)
// License: MIT
//-----------------------------------------------------------------------------

module melody_rom #(
    parameter MELODY_LENGTH = 128,           // Number of notes in melody
    parameter ADDR_WIDTH    = 7              // log2(MELODY_LENGTH)
)(
    input  wire                    clk,
    input  wire [ADDR_WIDTH-1:0]   addr,
    output reg  [15:0]             data
);

    //-------------------------------------------------------------------------
    // Note Definitions (semitones from A4 = 440 Hz)
    //-------------------------------------------------------------------------
    localparam signed [7:0] REST = 8'h80;    // Special: silence
    localparam signed [7:0] C4   = -8'd9;
    localparam signed [7:0] D4   = -8'd7;
    localparam signed [7:0] E4   = -8'd5;
    localparam signed [7:0] F4   = -8'd4;
    localparam signed [7:0] G4   = -8'd2;
    localparam signed [7:0] Gs4  = -8'd1;    // G#4
    localparam signed [7:0] A4   =  8'd0;
    localparam signed [7:0] As4  =  8'd1;    // A#4
    localparam signed [7:0] B4   =  8'd2;
    localparam signed [7:0] C5   =  8'd3;
    localparam signed [7:0] D5   =  8'd5;
    localparam signed [7:0] Ds5  =  8'd6;    // D#5
    localparam signed [7:0] E5   =  8'd7;
    localparam signed [7:0] F5   =  8'd8;
    localparam signed [7:0] G5   =  8'd10;
    localparam signed [7:0] A5   =  8'd12;

    //-------------------------------------------------------------------------
    // Duration Definitions
    //-------------------------------------------------------------------------
    localparam [5:0] DUR_16TH    = 6'd0;     // Sixteenth note
    localparam [5:0] DUR_8TH     = 6'd1;     // Eighth note
    localparam [5:0] DUR_QUARTER = 6'd2;     // Quarter note
    localparam [5:0] DUR_HALF    = 6'd3;     // Half note
    localparam [5:0] DUR_WHOLE   = 6'd4;     // Whole note
    localparam [5:0] DUR_DOT8TH  = 6'd5;     // Dotted eighth (1.5x eighth)

    //-------------------------------------------------------------------------
    // Helper function to encode note
    //-------------------------------------------------------------------------
    function [15:0] note;
        input signed [7:0] pitch;
        input [5:0] duration;
        begin
            note = {pitch, 2'b00, duration};
        end
    endfunction

    //-------------------------------------------------------------------------
    // Melody ROM - Für Elise (Opening Theme)
    // The famous A-section repeated, with some of B-section
    //-------------------------------------------------------------------------
    always @(posedge clk) begin
        case (addr)
            //=================================================================
            // A Section - First phrase (bars 1-4)
            // E5 D#5 E5 D#5 E5 B4 D5 C5 A4
            //=================================================================
            7'd0:  data <= note(E5,   DUR_8TH);      // E5
            7'd1:  data <= note(Ds5,  DUR_8TH);      // D#5
            7'd2:  data <= note(E5,   DUR_8TH);      // E5
            7'd3:  data <= note(Ds5,  DUR_8TH);      // D#5
            7'd4:  data <= note(E5,   DUR_8TH);      // E5
            7'd5:  data <= note(B4,   DUR_8TH);      // B4
            7'd6:  data <= note(D5,   DUR_8TH);      // D5
            7'd7:  data <= note(C5,   DUR_8TH);      // C5
            7'd8:  data <= note(A4,   DUR_QUARTER);  // A4 (longer)
            7'd9:  data <= note(REST, DUR_8TH);      // Rest

            //=================================================================
            // A Section - Second phrase (bars 5-8)
            // C4 E4 A4 B4 (rest) E4 G#4 B4 C5
            //=================================================================
            7'd10: data <= note(C4,   DUR_8TH);      // C4
            7'd11: data <= note(E4,   DUR_8TH);      // E4
            7'd12: data <= note(A4,   DUR_8TH);      // A4
            7'd13: data <= note(B4,   DUR_QUARTER);  // B4 (longer)
            7'd14: data <= note(REST, DUR_8TH);      // Rest
            7'd15: data <= note(E4,   DUR_8TH);      // E4
            7'd16: data <= note(Gs4,  DUR_8TH);      // G#4
            7'd17: data <= note(B4,   DUR_8TH);      // B4
            7'd18: data <= note(C5,   DUR_QUARTER);  // C5 (longer)
            7'd19: data <= note(REST, DUR_8TH);      // Rest

            //=================================================================
            // A Section - Third phrase (bars 9-12) - repeat of first
            // E4 E5 D#5 E5 D#5 E5 B4 D5 C5 A4
            //=================================================================
            7'd20: data <= note(E4,   DUR_8TH);      // E4
            7'd21: data <= note(E5,   DUR_8TH);      // E5
            7'd22: data <= note(Ds5,  DUR_8TH);      // D#5
            7'd23: data <= note(E5,   DUR_8TH);      // E5
            7'd24: data <= note(Ds5,  DUR_8TH);      // D#5
            7'd25: data <= note(E5,   DUR_8TH);      // E5
            7'd26: data <= note(B4,   DUR_8TH);      // B4
            7'd27: data <= note(D5,   DUR_8TH);      // D5
            7'd28: data <= note(C5,   DUR_8TH);      // C5
            7'd29: data <= note(A4,   DUR_QUARTER);  // A4 (longer)
            7'd30: data <= note(REST, DUR_8TH);      // Rest

            //=================================================================
            // A Section - Fourth phrase (bars 13-16)
            // C4 E4 A4 B4 (rest) E4 C5 B4 A4
            //=================================================================
            7'd31: data <= note(C4,   DUR_8TH);      // C4
            7'd32: data <= note(E4,   DUR_8TH);      // E4
            7'd33: data <= note(A4,   DUR_8TH);      // A4
            7'd34: data <= note(B4,   DUR_QUARTER);  // B4 (longer)
            7'd35: data <= note(REST, DUR_8TH);      // Rest
            7'd36: data <= note(E4,   DUR_8TH);      // E4
            7'd37: data <= note(C5,   DUR_8TH);      // C5
            7'd38: data <= note(B4,   DUR_8TH);      // B4
            7'd39: data <= note(A4,   DUR_HALF);     // A4 (end of A section)
            7'd40: data <= note(REST, DUR_QUARTER);  // Rest

            //=================================================================
            // A Section Repeat - First phrase again
            //=================================================================
            7'd41: data <= note(E5,   DUR_8TH);      // E5
            7'd42: data <= note(Ds5,  DUR_8TH);      // D#5
            7'd43: data <= note(E5,   DUR_8TH);      // E5
            7'd44: data <= note(Ds5,  DUR_8TH);      // D#5
            7'd45: data <= note(E5,   DUR_8TH);      // E5
            7'd46: data <= note(B4,   DUR_8TH);      // B4
            7'd47: data <= note(D5,   DUR_8TH);      // D5
            7'd48: data <= note(C5,   DUR_8TH);      // C5
            7'd49: data <= note(A4,   DUR_QUARTER);  // A4
            7'd50: data <= note(REST, DUR_8TH);      // Rest

            //=================================================================
            // A Section Repeat - Second phrase
            //=================================================================
            7'd51: data <= note(C4,   DUR_8TH);      // C4
            7'd52: data <= note(E4,   DUR_8TH);      // E4
            7'd53: data <= note(A4,   DUR_8TH);      // A4
            7'd54: data <= note(B4,   DUR_QUARTER);  // B4
            7'd55: data <= note(REST, DUR_8TH);      // Rest
            7'd56: data <= note(E4,   DUR_8TH);      // E4
            7'd57: data <= note(Gs4,  DUR_8TH);      // G#4
            7'd58: data <= note(B4,   DUR_8TH);      // B4
            7'd59: data <= note(C5,   DUR_QUARTER);  // C5
            7'd60: data <= note(REST, DUR_8TH);      // Rest

            //=================================================================
            // A Section Repeat - Third phrase
            //=================================================================
            7'd61: data <= note(E4,   DUR_8TH);      // E4
            7'd62: data <= note(E5,   DUR_8TH);      // E5
            7'd63: data <= note(Ds5,  DUR_8TH);      // D#5
            7'd64: data <= note(E5,   DUR_8TH);      // E5
            7'd65: data <= note(Ds5,  DUR_8TH);      // D#5
            7'd66: data <= note(E5,   DUR_8TH);      // E5
            7'd67: data <= note(B4,   DUR_8TH);      // B4
            7'd68: data <= note(D5,   DUR_8TH);      // D5
            7'd69: data <= note(C5,   DUR_8TH);      // C5
            7'd70: data <= note(A4,   DUR_QUARTER);  // A4
            7'd71: data <= note(REST, DUR_8TH);      // Rest

            //=================================================================
            // A Section Repeat - Fourth phrase (ending)
            //=================================================================
            7'd72: data <= note(C4,   DUR_8TH);      // C4
            7'd73: data <= note(E4,   DUR_8TH);      // E4
            7'd74: data <= note(A4,   DUR_8TH);      // A4
            7'd75: data <= note(B4,   DUR_QUARTER);  // B4
            7'd76: data <= note(REST, DUR_8TH);      // Rest
            7'd77: data <= note(E4,   DUR_8TH);      // E4
            7'd78: data <= note(C5,   DUR_8TH);      // C5
            7'd79: data <= note(B4,   DUR_8TH);      // B4
            7'd80: data <= note(A4,   DUR_WHOLE);    // A4 (final note)

            //=================================================================
            // End marker and padding
            //=================================================================
            7'd81: data <= note(REST, DUR_WHOLE);    // Final rest

            // Padding with rests for remaining addresses
            default: data <= note(REST, DUR_QUARTER);
        endcase
    end

    //-------------------------------------------------------------------------
    // Melody length output for sequencer
    //-------------------------------------------------------------------------
    // The actual melody ends at address 81 (82 notes total)

endmodule

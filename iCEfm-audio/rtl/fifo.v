// Simple Synchronous FIFO Buffer
// Circular buffer for audio sample buffering
//
// Author: Based on iCEstick-hacks FM transmitter project
// License: MIT

module fifo #(
    parameter DATA_WIDTH = 16,
    parameter DEPTH = 256,
    parameter ADDR_WIDTH = $clog2(DEPTH)
)(
    input  wire                     clk,
    input  wire                     rst,

    // Write interface
    input  wire [DATA_WIDTH-1:0]    wr_data,
    input  wire                     wr_en,
    output wire                     full,

    // Read interface
    output reg  [DATA_WIDTH-1:0]    rd_data,
    input  wire                     rd_en,
    output wire                     empty,

    // Status
    output wire [ADDR_WIDTH:0]      count
);

    // Memory array
    reg [DATA_WIDTH-1:0] mem [0:DEPTH-1];

    // Read and write pointers
    reg [ADDR_WIDTH:0] wr_ptr = 0;  // Extra bit to distinguish full/empty
    reg [ADDR_WIDTH:0] rd_ptr = 0;

    // Status signals
    assign empty = (wr_ptr == rd_ptr);
    assign full = (wr_ptr[ADDR_WIDTH] != rd_ptr[ADDR_WIDTH]) &&
                  (wr_ptr[ADDR_WIDTH-1:0] == rd_ptr[ADDR_WIDTH-1:0]);
    assign count = wr_ptr - rd_ptr;

    // Write logic
    always @(posedge clk) begin
        if (rst) begin
            wr_ptr <= 0;
        end else if (wr_en && !full) begin
            mem[wr_ptr[ADDR_WIDTH-1:0]] <= wr_data;
            wr_ptr <= wr_ptr + 1;
        end
    end

    // Read logic
    always @(posedge clk) begin
        if (rst) begin
            rd_ptr <= 0;
            rd_data <= 0;
        end else if (rd_en && !empty) begin
            rd_data <= mem[rd_ptr[ADDR_WIDTH-1:0]];
            rd_ptr <= rd_ptr + 1;
        end
    end

endmodule

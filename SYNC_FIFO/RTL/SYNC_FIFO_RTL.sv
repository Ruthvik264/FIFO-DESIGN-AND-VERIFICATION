`timescale 1ns / 1ps

// Synchronous FIFO: one clock, parameterized width/depth.
// DEPTH must be a power of 2 (pointers wrap by simply truncating).
// Read data is REGISTERED: rd_data is valid one clock after rd_en.
// Writes while full and reads while empty are ignored (no data is lost or corrupted).

module sync_fifo #(
    parameter DATA_W = 8,
    parameter DEPTH  = 8
) (
    input  logic              clk,
    input  logic              rst_n,     // synchronous, active low
    input  logic              wr_en,
    input  logic [DATA_W-1:0] wr_data,
    input  logic              rd_en,
    output logic [DATA_W-1:0] rd_data,
    output logic              full,
    output logic              empty
);

    localparam ADDR_W = $clog2(DEPTH);

    logic [DATA_W-1:0] mem [0:DEPTH-1];

    // Pointers are ADDR_W+1 bits: lower ADDR_W bits index the memory,
    // the extra MSB toggles each time the pointer wraps around.
    logic [ADDR_W:0] wptr, rptr;

    // An operation only happens if the FIFO can accept / provide data.
    logic do_wr, do_rd;
    assign do_wr = wr_en && !full;
    assign do_rd = rd_en && !empty;

    // Flags
    assign empty = (wptr == rptr);
    assign full  = (wptr[ADDR_W]     != rptr[ADDR_W]) &&
                   (wptr[ADDR_W-1:0] == rptr[ADDR_W-1:0]);

    // Pointer update
    always_ff @(posedge clk) begin
        if (!rst_n) begin
            wptr <= '0;
            rptr <= '0;
        end else begin
            if (do_wr) wptr <= wptr + 1'b1;
            if (do_rd) rptr <= rptr + 1'b1;
        end
    end

    // Memory write and registered read
    always_ff @(posedge clk) begin
        if (do_wr) mem[wptr[ADDR_W-1:0]] <= wr_data;
        if (do_rd) rd_data <= mem[rptr[ADDR_W-1:0]];
    end

endmodule

`timescale 1ns / 1ps
// Asynchronous FIFO (two independent clocks)
//   - DEPTH must be a power of 2 and >= 4.
//   - Binary pointers (ADDR_W+1 bits) address the memory; their Gray-coded copies cross clock domains.
//   - Each Gray pointer goes through a 2-flop synchronizer into the other domain.
//   - wfull is generated in the write domain, rempty in the read domain, both REGISTERED
//     and computed from the NEXT pointer value.
//   - Read data is registered: rdata is valid one rclk after an accepted read (same as sync_fifo).
//   - Hold both resets low for at least 3 cycles of the slower clock.

module async_fifo #(
    parameter DATA_W = 8,
    parameter DEPTH  = 8
) (
    // write domain
    input  logic              wclk,
    input  logic              wrst_n,
    input  logic              winc,
    input  logic [DATA_W-1:0] wdata,
    output logic              wfull,
    // read domain
    input  logic              rclk,
    input  logic              rrst_n,
    input  logic              rinc,
    output logic [DATA_W-1:0] rdata,
    output logic              rempty
);

    localparam ADDR_W = $clog2(DEPTH);

    logic [DATA_W-1:0] mem [0:DEPTH-1];

    // ---------------- signal declarations ----------------
    // write domain
    logic [ADDR_W:0] wbin, wgray, wbin_next, wgray_next;
    logic            do_wr, wfull_val;
    // read domain
    logic [ADDR_W:0] rbin, rgray, rbin_next, rgray_next;
    logic            do_rd, rempty_val;
    // synchronizers (ASYNC_REG tells Vivado these are a CDC chain: keep them adjacent)
    (* ASYNC_REG = "TRUE" *) logic [ADDR_W:0] rgray_w1, rgray_w2;   // rgray -> wclk domain
    (* ASYNC_REG = "TRUE" *) logic [ADDR_W:0] wgray_r1, wgray_r2;   // wgray -> rclk domain

    // ================= WRITE DOMAIN (wclk) =================
    assign do_wr     = winc && !wfull;
    assign wbin_next = wbin + {{ADDR_W{1'b0}}, do_wr};
    assign wgray_next = (wbin_next >> 1) ^ wbin_next;

    always_ff @(posedge wclk) begin
        if (!wrst_n) begin
            wbin  <= '0;
            wgray <= '0;
        end else begin
            wbin  <= wbin_next;
            wgray <= wgray_next;
        end
    end

    // memory write (address uses the lower ADDR_W bits of the binary pointer)
    always_ff @(posedge wclk) begin
        if (do_wr) mem[wbin[ADDR_W-1:0]] <= wdata;
    end

    // 2-flop synchronizer: read Gray pointer into the write domain
    always_ff @(posedge wclk) begin
        if (!wrst_n) begin
            rgray_w1 <= '0;
            rgray_w2 <= '0;
        end else begin
            rgray_w1 <= rgray;
            rgray_w2 <= rgray_w1;
        end
    end

    // FULL: next write Gray pointer equals the (synchronized) read Gray pointer
    //       with its top two bits inverted (= "exactly one lap ahead, same slot")
    assign wfull_val = (wgray_next == {~rgray_w2[ADDR_W:ADDR_W-1], rgray_w2[ADDR_W-2:0]});

    always_ff @(posedge wclk) begin
        if (!wrst_n) wfull <= 1'b0;
        else         wfull <= wfull_val;
    end

    // ================= READ DOMAIN (rclk) =================
    assign do_rd     = rinc && !rempty;
    assign rbin_next = rbin + {{ADDR_W{1'b0}}, do_rd};
    assign rgray_next = (rbin_next >> 1) ^ rbin_next;

    always_ff @(posedge rclk) begin
        if (!rrst_n) begin
            rbin  <= '0;
            rgray <= '0;
        end else begin
            rbin  <= rbin_next;
            rgray <= rgray_next;
        end
    end

    // registered memory read
    always_ff @(posedge rclk) begin
        if (do_rd) rdata <= mem[rbin[ADDR_W-1:0]];
    end

    // 2-flop synchronizer: write Gray pointer into the read domain
    always_ff @(posedge rclk) begin
        if (!rrst_n) begin
            wgray_r1 <= '0;
            wgray_r2 <= '0;
        end else begin
            wgray_r1 <= wgray;
            wgray_r2 <= wgray_r1;
        end
    end

    // EMPTY: next read Gray pointer equals the (synchronized) write Gray pointer
    assign rempty_val = (rgray_next == wgray_r2);

    always_ff @(posedge rclk) begin
        if (!rrst_n) rempty <= 1'b1;
        else         rempty <= rempty_val;
    end

endmodule

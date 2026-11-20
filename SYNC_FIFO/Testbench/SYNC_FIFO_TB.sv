`timescale 1ns/1ps

// Self-checking testbench for sync_fifo.
// Model: a SystemVerilog queue. It is updated from the INPUTS only (never from DUT flags),
// so it is an independent reference. Stimulus is driven on negedge to avoid races.

module sync_fifo_tb;

    localparam DATA_W = 8;
    localparam DEPTH  = 8;

    logic              clk = 0;
    logic              rst_n;
    logic              wr_en, rd_en;
    logic [DATA_W-1:0] wr_data, rd_data;
    logic              full, empty;

    sync_fifo #(.DATA_W(DATA_W), .DEPTH(DEPTH)) dut (.*);

    always #5 clk = ~clk;

    // ---------------- Scoreboard ----------------
    logic [DATA_W-1:0] exp_q [$];
    logic [DATA_W-1:0] exp_data;
    logic              rd_pending = 0;   // a read happened on the previous edge; check its data now

    int checks = 0, errors = 0;
    // corner-case counters (prove the interesting cases were actually hit)
    int full_cycles = 0, empty_cycles = 0;
    int blocked_wr = 0, blocked_rd = 0;
    int simul_full = 0, simul_empty = 0, simul_mid = 0;

    always @(posedge clk) begin
        bit do_wr_m, do_rd_m;
        if (!rst_n) begin
            exp_q.delete();
            rd_pending <= 0;
        end else begin
            // 1. data of the read issued on the previous edge (registered read => 1 cycle latency)
            if (rd_pending) begin
                if (rd_data !== exp_data) begin
                    errors++;
                    $error("[%0t] DATA mismatch: got %0h expected %0h", $time, rd_data, exp_data);
                end else checks++;
            end

            // 2. flags must match the model's occupancy (values before this edge)
            if (empty !== (exp_q.size() == 0)) begin
                errors++;
                $error("[%0t] EMPTY mismatch: dut=%b model_size=%0d", $time, empty, exp_q.size());
            end else checks++;
            if (full !== (exp_q.size() == DEPTH)) begin
                errors++;
                $error("[%0t] FULL mismatch: dut=%b model_size=%0d", $time, full, exp_q.size());
            end else checks++;

            // 3. decide what the model does this edge (from pre-edge occupancy)
            do_wr_m = wr_en && (exp_q.size() < DEPTH);
            do_rd_m = rd_en && (exp_q.size() > 0);

            // corner-case bookkeeping
            if (exp_q.size() == DEPTH) full_cycles++;
            if (exp_q.size() == 0)     empty_cycles++;
            if (wr_en && !do_wr_m)     blocked_wr++;
            if (rd_en && !do_rd_m)     blocked_rd++;
            if (wr_en && rd_en) begin
                if      (exp_q.size() == DEPTH) simul_full++;
                else if (exp_q.size() == 0)     simul_empty++;
                else                            simul_mid++;
            end

            // 4. update model
            rd_pending <= do_rd_m;
            if (do_rd_m) exp_data <= exp_q[0];      // oldest entry
            if (do_wr_m) exp_q.push_back(wr_data);
            if (do_rd_m) void'(exp_q.pop_front());
        end
    end

    // ---------------- Stimulus helpers ----------------
    task automatic push(input [DATA_W-1:0] d);
        @(negedge clk); wr_en = 1; wr_data = d;
        @(negedge clk); wr_en = 0;
    endtask

    task automatic pop();
        @(negedge clk); rd_en = 1;
        @(negedge clk); rd_en = 0;
    endtask

    task automatic push_pop(input [DATA_W-1:0] d);   // read and write in the SAME cycle
        @(negedge clk); wr_en = 1; rd_en = 1; wr_data = d;
        @(negedge clk); wr_en = 0; rd_en = 0;
    endtask

    int wp;

    initial begin
        wr_en = 0; rd_en = 0; wr_data = 0; rst_n = 0;
        repeat (3) @(negedge clk);
        rst_n = 1;
        repeat (2) @(negedge clk);

        // T1: fill completely, then keep writing while full (extra writes must be ignored)
        for (int i = 0; i < DEPTH; i++) push(8'h10 + i);
        push(8'hEE);
        push(8'hEF);

        // T2: drain completely; data must come out in the same order, with no 0xEE/0xEF
        for (int i = 0; i < DEPTH; i++) pop();
        repeat (3) @(negedge clk);

        // T3 (TODO): read while empty.
        //   Call pop() 3 times on the empty FIFO, then push(8'hA5), then pop().
        //   Expectation: the read pointer did not move during the empty reads, and A5 comes out.
        //   Think: which signal in the RTL stops rptr from moving?

        // T4 (TODO): simultaneous read and write in three different states.
        //   (a) mid-fill : push() a few values, then push_pop(...)
        //   (b) empty    : make sure the FIFO is empty, then push_pop(...)
        //   (c) full     : fill it, then push_pop(...)
        //   For each, predict BEFORE running what the occupancy becomes and why.
        //   After running, check simul_mid / simul_empty / simul_full in the report are all > 0.

        // T5: constrained-random, alternating write-heavy and read-heavy phases
        //     so the FIFO repeatedly hits both full and empty.
        for (int ph = 0; ph < 6; ph++) begin
            wp = (ph % 2 == 0) ? 80 : 20;
            repeat (300) begin
                @(negedge clk);
                wr_en   = ($urandom_range(99) < wp);
                rd_en   = ($urandom_range(99) < (100 - wp));
                wr_data = $urandom;
            end
        end
        @(negedge clk); wr_en = 0; rd_en = 0;
        repeat (3) @(negedge clk);

        // ---------------- Report ----------------
        $display("----------------------------------------");
        $display("checks=%0d errors=%0d", checks, errors);
        $display("full_cycles=%0d empty_cycles=%0d", full_cycles, empty_cycles);
        $display("blocked_wr=%0d blocked_rd=%0d", blocked_wr, blocked_rd);
        $display("simul_full=%0d simul_empty=%0d simul_mid=%0d", simul_full, simul_empty, simul_mid);
        if (errors == 0) $display("RESULT: PASS");
        else             $display("RESULT: FAIL");
        $display("----------------------------------------");
        $finish;
    end

endmodule

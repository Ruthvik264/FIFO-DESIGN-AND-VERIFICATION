`timescale 1ns/1ps

// ---------------------------------------------------------------------------
// One verification environment = one DUT + two independent clocks + a queue model.
// The top module instantiates three of them with different clock ratios:
//   write faster than read  -> FIFO tends to fill  (exercises wfull)
//   read faster than write  -> FIFO tends to empty (exercises rempty)
//   nearly equal clocks     -> phase relationship drifts continuously (exercises CDC timing)
//
// Why the model differs from the sync FIFO testbench:
//   wfull / rempty are CONSERVATIVE (they lag by the synchronizer delay), so the model cannot
//   predict them exactly. Instead the model follows what the DUT actually accepted and checks:
//     1. no overflow  : a write is never accepted while the model holds DEPTH entries
//     2. no underflow : a read is never accepted while the model is empty
//     3. data order   : every accepted read returns the oldest written value
//     4. liveness     : after traffic stops, the flags settle to the true state (empty, not full)
//   Writes/reads are decided from DUT flags sampled before the clock edge.
//   (The two always blocks can fire in the same time step when edges coincide; this is
//    harmless: it can only hide a bug for one cycle, never create a false error, because a
//    correct DUT never accepts a write at full or a read at empty.)
// ---------------------------------------------------------------------------
module async_fifo_env #(
    parameter real WPER     = 10.0,
    parameter real RPER     = 14.0,
    parameter int  DATA_W   = 8,
    parameter int  DEPTH    = 8,
    parameter real PHASE_NS = 4000.0
) (
    output logic done,
    output int   errors,
    output int   checks
);

    logic              wclk = 0, rclk = 0;
    logic              wrst_n = 0, rrst_n = 0;
    logic              winc = 0, rinc = 0;
    logic [DATA_W-1:0] wdata = 0, rdata;
    logic              wfull, rempty;

    async_fifo #(.DATA_W(DATA_W), .DEPTH(DEPTH)) dut (
        .wclk(wclk), .wrst_n(wrst_n), .winc(winc), .wdata(wdata), .wfull(wfull),
        .rclk(rclk), .rrst_n(rrst_n), .rinc(rinc), .rdata(rdata), .rempty(rempty)
    );

    always #(WPER/2.0) wclk = ~wclk;
    always #(RPER/2.0) rclk = ~rclk;

    // ---------------- model and counters ----------------
    logic [DATA_W-1:0] exp_q [$];
    logic [DATA_W-1:0] exp_data;
    logic              rd_pending = 0;

    int wr_cnt = 0, rd_cnt = 0, max_occ = 0;
    int full_cycles = 0, empty_cycles = 0, blocked_w = 0, blocked_r = 0;

    // write-side bookkeeping (wclk)
    always @(posedge wclk) begin
        if (wrst_n) begin
            if (winc && !wfull) begin
                if (exp_q.size() >= DEPTH) begin
                    errors++;
                    $error("[%m] OVERFLOW: write accepted while model holds %0d entries", exp_q.size());
                end else begin
                    exp_q.push_back(wdata);
                    checks++;
                end
                wr_cnt++;
            end
            if (winc && wfull) blocked_w++;
            if (wfull)         full_cycles++;
            if (exp_q.size() > max_occ) max_occ = exp_q.size();
        end
    end

    // read-side bookkeeping (rclk); rdata is registered => checked one rclk after the read
    always @(posedge rclk) begin
        if (!rrst_n) begin
            rd_pending <= 0;
        end else begin
            if (rd_pending) begin
                if (rdata !== exp_data) begin
                    errors++;
                    $error("[%m] DATA mismatch: got %0h expected %0h", rdata, exp_data);
                end else checks++;
            end
            rd_pending <= 0;
            if (rinc && !rempty) begin
                if (exp_q.size() == 0) begin
                    errors++;
                    $error("[%m] UNDERFLOW: read accepted while model is empty");
                end else begin
                    exp_data   <= exp_q.pop_front();
                    rd_pending <= 1;
                    checks++;
                end
                rd_cnt++;
            end
            if (rinc && rempty) blocked_r++;
            if (rempty)         empty_cycles++;
        end
    end

    // ---------------- stimulus ----------------
    int  wprob = 0, rprob = 0;
    logic stim_done = 0, drain = 0;

    function automatic int get_wp(input int ph);
        case (ph)
            0: return 100;   // write only  -> must reach full
            1: return 0;     // read only   -> must reach empty
            2: return 85;
            3: return 15;
            4: return 85;
            5: return 15;
            default: return 50;
        endcase
    endfunction

    function automatic int get_rp(input int ph);
        case (ph)
            0: return 0;
            1: return 100;
            2: return 15;
            3: return 85;
            4: return 15;
            5: return 85;
            default: return 50;
        endcase
    endfunction

    // each side drives its own inputs on its own clock's negedge
    always @(negedge wclk) begin
        if (wrst_n && !stim_done) begin
            winc  = ($urandom_range(99) < wprob);
            wdata = $urandom;
        end else begin
            winc = 0;
        end
    end

    always @(negedge rclk) begin
        if (rrst_n && !stim_done) rinc = ($urandom_range(99) < rprob);
        else                      rinc = drain;
    end

    initial begin
        done = 0; errors = 0; checks = 0;
        exp_q.delete();

        // reset: hold both low for ~8 cycles of the slower clock, release each on its own negedge
        #(8.0 * ((WPER > RPER) ? WPER : RPER));
        @(negedge wclk); wrst_n = 1;
        @(negedge rclk); rrst_n = 1;
        repeat (4) @(negedge rclk);

        // 8 traffic phases (write-only, read-only, then alternating heavy/light, then 50/50)
        for (int ph = 0; ph < 8; ph++) begin
            wprob = get_wp(ph);
            rprob = get_rp(ph);
            #(PHASE_NS);
        end

        // stop traffic, then drain whatever is left
        stim_done = 1;
        repeat (4) @(negedge rclk);
        drain = 1;
        for (int i = 0; i < 4000 && exp_q.size() > 0; i++) @(negedge rclk);
        drain = 0;
        repeat (20) @(negedge rclk);
        repeat (20) @(negedge wclk);

        // liveness: with no traffic, the (lagging) flags must settle to the true state
        if (exp_q.size() != 0) begin
            errors++; $error("[%m] model not empty after drain (%0d left)", exp_q.size());
        end else checks++;
        if (!rempty) begin
            errors++; $error("[%m] rempty did not settle to 1 after drain");
        end else checks++;
        if (wfull) begin
            errors++; $error("[%m] wfull did not settle to 0 after drain");
        end else checks++;

        $display("[W=%0.1fns R=%0.1fns] checks=%0d errors=%0d | writes=%0d reads=%0d max_occ=%0d | full_cycles=%0d empty_cycles=%0d blocked_w=%0d blocked_r=%0d",
                 WPER, RPER, checks, errors, wr_cnt, rd_cnt, max_occ,
                 full_cycles, empty_cycles, blocked_w, blocked_r);
        done = 1;
    end

endmodule


// ---------------------------------------------------------------------------
module async_fifo_tb;

    wire [2:0] done;
    int e0, e1, e2, c0, c1, c2;

    async_fifo_env #(.WPER(10.0), .RPER(14.0)) env0 (.done(done[0]), .errors(e0), .checks(c0));
    async_fifo_env #(.WPER(14.0), .RPER(10.0)) env1 (.done(done[1]), .errors(e1), .checks(c1));
    async_fifo_env #(.WPER(10.0), .RPER(10.3)) env2 (.done(done[2]), .errors(e2), .checks(c2));

    initial begin
        wait (done === 3'b111);
        $display("----------------------------------------");
        $display("TOTAL checks=%0d errors=%0d", c0 + c1 + c2, e0 + e1 + e2);
        if ((e0 + e1 + e2) == 0) $display("RESULT: PASS");
        else                     $display("RESULT: FAIL");
        $display("----------------------------------------");
        $finish;
    end

endmodule

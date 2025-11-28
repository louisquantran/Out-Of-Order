`timescale 1ns/1ps

module skid_buffer_tb;

    // Payload type for this test
    typedef logic [15:0] T_t;

    // Clock & reset
    logic clk = 0;
    logic reset;
    always #5 clk = ~clk;  // 100 MHz

    // DUT interface
    logic     valid_in;
    T_t       data_in;
    logic     ready_in;

    logic     ready_out;
    logic     valid_out;
    T_t       data_out;

    // DUT instantiation
    skid_buffer #(
        .T(T_t)
    ) dut (
        .clk       (clk),
        .reset     (reset),
        .valid_in  (valid_in),
        .data_in   (data_in),
        .ready_in  (ready_in),
        .ready_out (ready_out),
        .valid_out (valid_out),
        .data_out  (data_out)
    );

    // Simple scoreboard 
    T_t     expect_q[$];
    int     errors   = 0;
    longint produced = 0;
    longint consumed = 0;

    // Push expected data on upstream handshake
    always_ff @(posedge clk) if (!reset) begin
        if (valid_in && ready_in) begin
            expect_q.push_back(data_in);
            produced++;
        end
    end

    // Pop & compare on downstream handshake
    always_ff @(posedge clk) if (!reset) begin
        if (valid_out && ready_out) begin
            consumed++;
            if (expect_q.size() == 0) begin
                $error("Pop with empty expect_q @%0t", $time);
                errors++;
            end else begin
                automatic T_t exp = expect_q.pop_front();
                if (data_out !== exp) begin
                    $error("Data mismatch @%0t: got=%h exp=%h",
                           $time, data_out, exp);
                    errors++;
                end
            end
        end
    end

    // Reset & init
    initial begin
        reset     = 1'b1;
        valid_in  = 1'b0;
        data_in   = '0;
        ready_out = 1'b1;
        repeat (3) @(posedge clk);
        reset = 1'b0;
    end

    int sent;

    // Producer task: send N items with stable-on-stall 
    task automatic send_stream(input T_t start, input int N);
        T_t next = start;
        begin
            valid_in <= 1'b1;
            data_in  <= next;
            sent     = 0;
            while (sent < N) begin
                @(posedge clk);
                if (ready_in) begin
                    sent++;
                    next++;
                    data_in <= next;   // advance only when accepted
                end else begin
                    data_in <= data_in;  // hold value while stalled
                end
            end
            valid_in <= 1'b0;
        end
    endtask

    // Test sequences
    int  cycles;
    int  left;
    int  c;
    T_t  gen;

    initial begin : run
        @(negedge reset);
        @(posedge clk);

        // TEST 1: Pure pass-through (no backpressure)
        $display("\n[TEST1] pass-through burst, ready_out=1");
        ready_out = 1;
        send_stream(16'h0000, 8);

        // Let pipeline drain a bit
        repeat (5) @(posedge clk);

        // TEST 2: Single-cycle stall at the sink
        $display("\n[TEST2] single-cycle stall at sink");
        fork
            begin
                send_stream(16'h0100, 10);
            end
            begin
                @(posedge clk);
                ready_out = 0;  // stall one beat
                @(posedge clk);
                ready_out = 1;
            end
        join

        repeat (5) @(posedge clk);

        // TEST 3: Multi-cycle stall (should buffer at most 1 item)
        $display("\n[TEST3] multi-cycle stall (skid buffer fills + drains)");
        fork
            begin
                send_stream(16'h0200, 16);
            end
            begin
                repeat (2) @(posedge clk);
                repeat (5) begin
                    ready_out = 0;
                    @(posedge clk);
                end
                ready_out = 1;
            end
        join

        repeat (10) @(posedge clk);

        // TEST 4: Randomized stress
        $display("\n[TEST4] random stress");
        cycles = 200;
        left   = 60; // total items to send during stress

        fork
            // Producer side: probabilistic valid
            begin
                valid_in = 0;
                gen      = 16'h1000;
                for (c = 0; c < cycles; c++) begin
                    // 70% chance to drive valid if items remain
                    if (left > 0 && ($urandom_range(0, 9) < 7)) begin
                        valid_in <= 1;
                        data_in  <= gen;
                    end else begin
                        valid_in <= 0;
                    end

                    @(posedge clk);
                    if (valid_in && ready_in) begin
                        gen++;
                        left--;
                        if (left == 0) valid_in <= 0;
                    end
                end
                valid_in <= 0;
            end

            // Consumer side: random backpressure
            begin
                for (int k = 0; k < cycles; k++) begin
                    ready_out = $urandom_range(0, 1);
                    @(posedge clk);
                end
                ready_out = 1;
            end
        join

        // Drain a few cycles
        repeat (10) @(posedge clk);

        // Final checks
        if (expect_q.size() != 0) begin
            $error("Items remaining in expect_q: %0d", expect_q.size());
            errors++;
        end

        $display("\nProduced=%0d, Consumed=%0d", produced, consumed);
        if (errors == 0)
            $display("SKID_BUFFER TB: PASS");
        else
            $display("SKID_BUFFER TB: FAIL (errors=%0d)", errors);

        $finish;
    end

endmodule

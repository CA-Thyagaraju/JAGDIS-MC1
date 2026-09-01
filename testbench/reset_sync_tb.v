`timescale 1ns/1ps

module reset_sync_tb;

    reg clk;
    reg reset_n;

    wire reset_n_sync;

    integer errors;

    reset_sync dut (
        .clk          (clk),
        .reset_n      (reset_n),
        .reset_n_sync (reset_n_sync)
    );

    always #10 clk = ~clk;


    task fail;
        input [8*100-1:0] message;
        begin
            errors = errors + 1;
            $display("FAIL: %0s", message);
        end
    endtask


    initial begin

        clk    = 1'b0;
        reset_n = 1'b0;
        errors = 0;

        $dumpfile("output/reset_sync_tb.vcd");
        $dumpvars(0, reset_sync_tb);


        // ============================================================
        // TEST 1: RESET ASSERTION
        // ============================================================

        $display("");
        $display("TEST 1: Reset assertion");

        #1;

        if (reset_n_sync !== 1'b0)
            fail("reset_n_sync must be 0 while reset is asserted");


        // ============================================================
        // TEST 2: RESET REMAINS ASSERTED
        // ============================================================

        $display("");
        $display("TEST 2: Reset held low");

        repeat (3) begin
            @(posedge clk);
            #1;

            if (reset_n_sync !== 1'b0)
                fail("reset_n_sync must remain 0 while reset_n is low");
        end


        // ============================================================
        // TEST 3: FIRST CLOCK AFTER RESET RELEASE
        // ============================================================

        $display("");
        $display("TEST 3: First clock after reset release");

        reset_n = 1'b1;

        @(posedge clk);
        #1;

        if (reset_n_sync !== 1'b0)
            fail("reset_n_sync must remain 0 after first release clock");


        // ============================================================
        // TEST 4: SECOND CLOCK AFTER RESET RELEASE
        // ============================================================

        $display("");
        $display("TEST 4: Second clock after reset release");

        @(posedge clk);
        #1;

        if (reset_n_sync !== 1'b1)
            fail("reset_n_sync must become 1 after second release clock");


        // ============================================================
        // TEST 5: RESET SYNC REMAINS HIGH
        // ============================================================

        $display("");
        $display("TEST 5: Synchronized reset remains released");

        repeat (3) begin
            @(posedge clk);
            #1;

            if (reset_n_sync !== 1'b1)
                fail("reset_n_sync must remain 1 after reset release");
        end


        // ============================================================
        // TEST 6: ASYNCHRONOUS RESET RE-ASSERTION
        // ============================================================

        $display("");
        $display("TEST 6: Asynchronous reset re-assertion");

        reset_n = 1'b0;

        #1;

        if (reset_n_sync !== 1'b0)
            fail("reset_n_sync must clear immediately when reset_n goes low");


        // ============================================================
        // TEST 7: SECOND RELEASE SEQUENCE
        // ============================================================

        $display("");
        $display("TEST 7: Second reset release sequence");

        reset_n = 1'b1;

        @(posedge clk);
        #1;

        if (reset_n_sync !== 1'b0)
            fail("reset_n_sync must remain 0 after first clock of second release");

        @(posedge clk);
        #1;

        if (reset_n_sync !== 1'b1)
            fail("reset_n_sync must become 1 after second clock of second release");


        // ============================================================
        // FINAL RESULT
        // ============================================================

        $display("");

        if (errors == 0)
            $display("PASS: reset_sync unit verification");
        else
            $display(
                "FAIL: reset_sync unit verification: %0d checks failed",
                errors
            );

        $finish;

    end

endmodule
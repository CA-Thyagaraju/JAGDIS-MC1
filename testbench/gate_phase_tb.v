`timescale 1ns/1ps

module gate_phase_tb;

    reg clk;
    reg reset_n;

    reg request_high;
    reg request_low;

    wire gate_high;
    wire gate_low;

    integer errors;
    integer i;

    gate_phase #(
        .DEAD_TIME_CLKS(6'd25)
    ) dut (
        .clk          (clk),
        .reset_n      (reset_n),
        .request_high (request_high),
        .request_low  (request_low),
        .gate_high    (gate_high),
        .gate_low     (gate_low)
    );

    always #10 clk = ~clk;


    task fail;
        input [8*100-1:0] message;
        begin
            errors = errors + 1;
            $display("FAIL: %0s", message);
        end
    endtask


    task reset_dut;
        begin
            request_high = 1'b0;
            request_low  = 1'b0;

            reset_n = 1'b0;
            #1;

            if (gate_high !== 1'b0)
                fail("reset must force gate_high low");

            if (gate_low !== 1'b0)
                fail("reset must force gate_low low");

            repeat (3)
                @(posedge clk);

            reset_n = 1'b1;

            repeat (2) begin
                @(posedge clk);
                #1;
            end
        end
    endtask


    initial begin

        clk = 1'b0;
        reset_n = 1'b0;

        request_high = 1'b0;
        request_low  = 1'b0;

        errors = 0;

        $dumpfile("output/simulation_artifacts/gate_phase_tb.vcd");
        $dumpvars(0, gate_phase_tb);


        // ============================================================
        // TEST 1: RESET
        // ============================================================

        $display("");
        $display("TEST 1: Reset");

        reset_dut;

        if (gate_high !== 1'b0 || gate_low !== 1'b0)
            fail("both gates must be off after reset");


        // ============================================================
        // TEST 2: HIGH-SIDE REQUEST
        // ============================================================

        $display("");
        $display("TEST 2: High-side request");

        request_high = 1'b1;
        request_low  = 1'b0;

        @(posedge clk);
        #1;

        if (gate_high !== 1'b1)
            fail("high-side request must enable gate_high");

        if (gate_low !== 1'b0)
            fail("high-side request must keep gate_low off");


        // ============================================================
        // TEST 3: LOW-SIDE REQUEST WITH DEAD TIME
        // ============================================================

        $display("");
        $display("TEST 3: High-to-low dead time");

        // Request low while high is currently active.
        request_high = 1'b0;
        request_low  = 1'b1;

        @(posedge clk);
        #1;

        // Both must immediately turn off.
        if (gate_high !== 1'b0 || gate_low !== 1'b0)
            fail("high-to-low transition must first turn both gates off");

        // Exactly 24 additional clocks must still remain dead.
        for (i = 0; i < 24; i = i + 1) begin
            @(posedge clk);
            #1;

            if (gate_high !== 1'b0 || gate_low !== 1'b0)
                fail("gate enabled before 25-clock dead time expired");
        end

        // The 25th clock after entering dead time should enable low.
        @(posedge clk);
        #1;

        if (gate_high !== 1'b0 || gate_low !== 1'b1)
            fail("low-side gate did not enable after 25-clock dead time");


        // ============================================================
        // TEST 4: LOW-TO-HIGH DEAD TIME
        // ============================================================

        $display("");
        $display("TEST 4: Low-to-high dead time");

        request_high = 1'b1;
        request_low  = 1'b0;

        @(posedge clk);
        #1;

        if (gate_high !== 1'b0 || gate_low !== 1'b0)
            fail("low-to-high transition must first turn both gates off");

        for (i = 0; i < 24; i = i + 1) begin
            @(posedge clk);
            #1;

            if (gate_high !== 1'b0 || gate_low !== 1'b0)
                fail("gate enabled before 25-clock dead time expired");
        end

        @(posedge clk);
        #1;

        if (gate_high !== 1'b1 || gate_low !== 1'b0)
            fail("high-side gate did not enable after 25-clock dead time");


        // ============================================================
        // TEST 5: BOTH REQUESTS HIGH
        // ============================================================

        $display("");
        $display("TEST 5: Simultaneous high and low request");

        request_high = 1'b1;
        request_low  = 1'b1;

        @(posedge clk);
        #1;

        if (gate_high !== 1'b0 || gate_low !== 1'b0)
            fail("simultaneous high and low request must fail safe");


        // ============================================================
        // TEST 6: BOTH REQUESTS LOW
        // ============================================================

        $display("");
        $display("TEST 6: Both requests off");

        request_high = 1'b0;
        request_low  = 1'b0;

        @(posedge clk);
        #1;

        if (gate_high !== 1'b0 || gate_low !== 1'b0)
            fail("both gates must remain off when both requests are low");


        // ============================================================
        // TEST 7: LATEST REQUEST WINS DURING DEAD TIME
        // ============================================================

        $display("");
        $display("TEST 7: Latest request wins during dead time");

        // Start this test from a clean, known state.
        // TEST 5 intentionally starts a dead-time interval, so simply
        // turning both requests off in TEST 6 does not immediately clear it.
        reset_dut;
        
        // Establish high-side operation.
        request_high = 1'b1;
        request_low  = 1'b0;

        @(posedge clk);
        #1;

        if (gate_high !== 1'b1 || gate_low !== 1'b0)
            fail("failed to establish high-side operation");

        // Start high-to-low transition.
        request_high = 1'b0;
        request_low  = 1'b1;

        @(posedge clk);
        #1;

        if (gate_high !== 1'b0 || gate_low !== 1'b0)
            fail("dead time did not begin");

        // While dead time is active, reverse the request.
        request_high = 1'b1;
        request_low  = 1'b0;

        // Remain in dead time.
        for (i = 0; i < 24; i = i + 1) begin
            @(posedge clk);
            #1;

            if (gate_high !== 1'b0 || gate_low !== 1'b0)
                fail("gate enabled before dead time expired");
        end

        // Latest request should determine the final state.
        @(posedge clk);
        #1;

        if (gate_high !== 1'b1 || gate_low !== 1'b0)
            fail("latest request did not win after dead time");


        // ============================================================
        // TEST 8: RESET DURING DEAD TIME
        // ============================================================

        $display("");
        $display("TEST 8: Reset during dead time");

        // Establish high-side operation.
        request_high = 1'b1;
        request_low  = 1'b0;

        @(posedge clk);
        #1;

        if (gate_high !== 1'b1 || gate_low !== 1'b0)
            fail("failed to establish high-side operation");

        // Start transition into dead time.
        request_high = 1'b0;
        request_low  = 1'b1;

        @(posedge clk);
        #1;

        if (gate_high !== 1'b0 || gate_low !== 1'b0)
            fail("dead time did not begin before reset test");

        // Assert reset asynchronously.
        reset_n = 1'b0;
        #1;

        if (gate_high !== 1'b0 || gate_low !== 1'b0)
            fail("reset during dead time must keep both gates off");

        // Release reset.
        reset_n = 1'b1;

        repeat (2) begin
            @(posedge clk);
            #1;
        end

        if (gate_high !== 1'b0 || gate_low !== 1'b1)
            fail("post-reset low-side request was not handled correctly");


        // ============================================================
        // FINAL RESULT
        // ============================================================

        $display("");

        if (errors == 0)
            $display("PASS: gate_phase unit verification");
        else
            $display(
                "FAIL: gate_phase unit verification: %0d checks failed",
                errors
            );

        $finish;
    end

endmodule
`timescale 1ns/1ps

module fault_manager_tb;

    reg clk;
    reg reset_n;

    reg oc_fault;
    reg uv_fault;
    reg ot_fault;
    reg hall_fault;

    wire fault_condition;
    wire fault_latched;

    integer errors;


    fault_manager dut (
        .clk            (clk),
        .reset_n        (reset_n),
        .oc_fault       (oc_fault),
        .uv_fault       (uv_fault),
        .ot_fault       (ot_fault),
        .hall_fault     (hall_fault),
        .fault_condition(fault_condition),
        .fault_latched  (fault_latched)
    );


    always #10 clk = ~clk;


    task fail;
        input [8*100-1:0] message;
        begin
            errors = errors + 1;
            $display("FAIL: %0s", message);
        end
    endtask


    task clear_fault_inputs;
        begin
            oc_fault   = 1'b0;
            uv_fault   = 1'b0;
            ot_fault   = 1'b0;
            hall_fault = 1'b0;
        end
    endtask


    task reset_dut;
        begin
            clear_fault_inputs;

            reset_n = 1'b0;

            #1;

            if (fault_condition !== 1'b0)
                fail("fault_condition must be zero during reset");

            if (fault_latched !== 1'b0)
                fail("fault_latched must be zero during reset");

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

        oc_fault   = 1'b0;
        uv_fault   = 1'b0;
        ot_fault   = 1'b0;
        hall_fault = 1'b0;

        errors = 0;

        $dumpfile("output/fault_manager_tb.vcd");
        $dumpvars(0, fault_manager_tb);


        // ============================================================
        // TEST 1: RESET
        // ============================================================

        $display("");
        $display("TEST 1: Reset");

        reset_dut;

        if (fault_latched !== 1'b0)
            fail("fault_latched must be clear after reset");

        if (fault_condition !== 1'b0)
            fail("fault_condition must be clear with all faults inactive");


        // ============================================================
        // TEST 2: FAULT CONDITION OR LOGIC
        // ============================================================

        $display("");
        $display("TEST 2: Fault condition OR logic");

        reset_dut;


        // OC only
        oc_fault = 1'b1;
        #1;

        if (fault_condition !== 1'b1)
            fail("OC_FAULT must assert fault_condition");

        clear_fault_inputs;


        // UV only
        uv_fault = 1'b1;
        #1;

        if (fault_condition !== 1'b1)
            fail("UV_FAULT must assert fault_condition");

        clear_fault_inputs;


        // OT only
        ot_fault = 1'b1;
        #1;

        if (fault_condition !== 1'b1)
            fail("OT_FAULT must assert fault_condition");

        clear_fault_inputs;


        // Hall only
        hall_fault = 1'b1;
        #1;

        if (fault_condition !== 1'b1)
            fail("HALL_FAULT must assert fault_condition");

        clear_fault_inputs;


        // All faults together
        oc_fault   = 1'b1;
        uv_fault   = 1'b1;
        ot_fault   = 1'b1;
        hall_fault = 1'b1;
        #1;

        if (fault_condition !== 1'b1)
            fail("multiple simultaneous faults must assert fault_condition");

        clear_fault_inputs;

        #1;

        if (fault_condition !== 1'b0)
            fail("fault_condition must clear when all fault inputs clear");


        // ============================================================
        // TEST 3: OC FAULT LATCHING
        // ============================================================

        $display("");
        $display("TEST 3: Over-current fault latching");

        reset_dut;

        oc_fault = 1'b1;

        @(posedge clk);
        #1;

        if (fault_latched !== 1'b1)
            fail("OC_FAULT must latch fault_latched");

        oc_fault = 1'b0;

        #1;

        if (fault_condition !== 1'b0)
            fail("fault_condition must clear after OC_FAULT is removed");

        if (fault_latched !== 1'b1)
            fail("fault_latched must remain set after OC_FAULT clears");


        // ============================================================
        // TEST 4: UV FAULT LATCHING
        // ============================================================

        $display("");
        $display("TEST 4: Under-voltage fault latching");

        reset_dut;

        uv_fault = 1'b1;

        @(posedge clk);
        #1;

        if (fault_latched !== 1'b1)
            fail("UV_FAULT must latch fault_latched");


        // ============================================================
        // TEST 5: OT FAULT LATCHING
        // ============================================================

        $display("");
        $display("TEST 5: Over-temperature fault latching");

        reset_dut;

        ot_fault = 1'b1;

        @(posedge clk);
        #1;

        if (fault_latched !== 1'b1)
            fail("OT_FAULT must latch fault_latched");


        // ============================================================
        // TEST 6: HALL FAULT LATCHING
        // ============================================================

        $display("");
        $display("TEST 6: Hall fault latching");

        reset_dut;

        hall_fault = 1'b1;

        @(posedge clk);
        #1;

        if (fault_latched !== 1'b1)
            fail("HALL_FAULT must latch fault_latched");


        // ============================================================
        // TEST 7: LATCH PERSISTENCE
        // ============================================================

        $display("");
        $display("TEST 7: Fault latch persistence");

        reset_dut;

        oc_fault = 1'b1;

        @(posedge clk);
        #1;

        if (fault_latched !== 1'b1)
            fail("fault did not latch");

        clear_fault_inputs;

        repeat (10) begin
            @(posedge clk);
            #1;

            if (fault_latched !== 1'b1)
                fail("fault_latched must remain set after fault removal");
        end


        // ============================================================
        // TEST 8: RESET CLEARS LATCH
        // ============================================================

        $display("");
        $display("TEST 8: Reset clears fault latch");

        // At this point the latch should already be set.
        if (fault_latched !== 1'b1)
            fail("test setup failed to create latched fault");

        reset_n = 1'b0;

        #1;

        if (fault_latched !== 1'b0)
            fail("reset must immediately clear fault_latched");

        if (fault_condition !== 1'b0)
            fail("fault_condition must remain clear after reset");

        reset_n = 1'b1;

        repeat (2) begin
            @(posedge clk);
            #1;
        end

        if (fault_latched !== 1'b0)
            fail("fault_latched must remain clear after reset release");


        // ============================================================
        // FINAL RESULT
        // ============================================================

        $display("");

        if (errors == 0)
            $display("PASS: fault_manager unit verification");
        else
            $display(
                "FAIL: fault_manager unit verification: %0d checks failed",
                errors
            );

        $finish;

    end

endmodule
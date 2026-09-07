`timescale 1ns/1ps

module control_fsm_tb;

    reg clk;
    reg reset_n;

    reg enable;
    reg brake;
    reg hall_valid;
    reg pwm_boundary;
    reg fault_condition;
    reg fault_latched;

    wire run_enable;
    wire brake_active;
    wire run;

    integer errors;


    control_fsm dut (
        .clk           (clk),
        .reset_n       (reset_n),
        .enable        (enable),
        .brake         (brake),
        .hall_valid    (hall_valid),
        .pwm_boundary  (pwm_boundary),
        .fault_condition(fault_condition),
        .fault_latched (fault_latched),
        .run_enable    (run_enable),
        .brake_active  (brake_active),
        .run           (run)
    );


    always #10 clk = ~clk;


    task fail;
        input [8*100-1:0] message;
        begin
            errors = errors + 1;
            $display("FAIL: %0s", message);
        end
    endtask


    task clear_inputs;
        begin
            enable         = 1'b0;
            brake          = 1'b0;
            hall_valid     = 1'b0;
            pwm_boundary   = 1'b0;
            fault_condition = 1'b0;
            fault_latched  = 1'b0;
        end
    endtask


    task reset_dut;
        begin
            clear_inputs;

            reset_n = 1'b0;

            #1;

            if (dut.state !== 3'd0)
                fail("reset must place FSM in IDLE");

            if (run_enable !== 1'b0)
                fail("run_enable must be low during reset");

            if (brake_active !== 1'b0)
                fail("brake_active must be low during reset");

            if (run !== 1'b0)
                fail("run must be low during reset");

            repeat (3)
                @(posedge clk);

            reset_n = 1'b1;

            repeat (2) begin
                @(posedge clk);
                #1;
            end
        end
    endtask


    task clock_once;
        begin
            @(posedge clk);
            #1;
        end
    endtask


    initial begin

        clk = 1'b0;
        reset_n = 1'b0;

        enable          = 1'b0;
        brake           = 1'b0;
        hall_valid      = 1'b0;
        pwm_boundary    = 1'b0;
        fault_condition = 1'b0;
        fault_latched   = 1'b0;

        errors = 0;

        $dumpfile("output/simulation_artifacts/control_fsm_tb.vcd");
        $dumpvars(0, control_fsm_tb);


        // ============================================================
        // TEST 1: RESET / IDLE
        // ============================================================

        $display("");
        $display("TEST 1: Reset and IDLE");

        reset_dut;

        if (dut.state !== 3'd0)
            fail("FSM must start in IDLE");

        if (run_enable || brake_active || run)
            fail("all outputs must be inactive in IDLE");


        // ============================================================
        // TEST 2: IDLE -> STARTUP
        // ============================================================

        $display("");
        $display("TEST 2: IDLE to STARTUP");

        enable = 1'b1;

        clock_once;

        if (dut.state !== 3'd1)
            fail("ENABLE must move FSM from IDLE to STARTUP");

        if (run_enable)
            fail("STARTUP must not assert run_enable");

        if (run)
            fail("STARTUP must not assert run");

        if (brake_active)
            fail("STARTUP must not assert brake_active");


        // ============================================================
        // TEST 3: STARTUP WAIT FOR HALL + PWM BOUNDARY
        // ============================================================

        $display("");
        $display("TEST 3: STARTUP qualification");

        hall_valid   = 1'b1;
        pwm_boundary = 1'b0;

        clock_once;

        if (dut.state !== 3'd1)
            fail("STARTUP must wait when PWM boundary is absent");

        if (run)
            fail("RUN must not assert before PWM boundary");


        pwm_boundary = 1'b1;

        clock_once;

        if (dut.state !== 3'd2)
            fail("valid Hall plus PWM boundary must enter RUN");

        if (!run_enable)
            fail("RUN must assert run_enable");

        if (!run)
            fail("RUN output must assert in RUN state");

        if (brake_active)
            fail("brake_active must be low in RUN");

        pwm_boundary = 1'b0;


        // ============================================================
        // TEST 4: RUN HOLD
        // ============================================================

        $display("");
        $display("TEST 4: RUN hold");

        clock_once;

        if (dut.state !== 3'd2)
            fail("RUN must remain active while enable is asserted");

        if (!run_enable || !run)
            fail("RUN outputs must remain asserted");


        // ============================================================
        // TEST 5: ENABLE RELEASE -> IDLE
        // ============================================================

        $display("");
        $display("TEST 5: RUN to IDLE");

        enable = 1'b0;

        clock_once;

        if (dut.state !== 3'd0)
            fail("clearing ENABLE must return RUN to IDLE");

        if (run_enable)
            fail("run_enable must clear after leaving RUN");

        if (run)
            fail("run must clear after leaving RUN");


        // ============================================================
        // TEST 6: STARTUP CANCELLED BY ENABLE
        // ============================================================

        $display("");
        $display("TEST 6: STARTUP cancellation");

        reset_dut;

        enable = 1'b1;

        clock_once;

        if (dut.state !== 3'd1)
            fail("ENABLE must enter STARTUP");

        enable = 1'b0;

        clock_once;

        if (dut.state !== 3'd0)
            fail("clearing ENABLE during STARTUP must return to IDLE");


        // ============================================================
        // TEST 7: STARTUP -> BRAKE
        // ============================================================

        $display("");
        $display("TEST 7: STARTUP to BRAKE");

        reset_dut;

        enable = 1'b1;

        clock_once;

        brake = 1'b1;

        clock_once;

        if (dut.state !== 3'd3)
            fail("BRAKE must move STARTUP to BRAKE");

        if (!brake_active)
            fail("BRAKE state must assert brake_active");

        if (run_enable)
            fail("BRAKE state must clear run_enable");

        if (run)
            fail("BRAKE state must clear run");


        // ============================================================
        // TEST 8: BRAKE RELEASE WITH ENABLE
        // ============================================================

        $display("");
        $display("TEST 8: BRAKE release to STARTUP");

        brake = 1'b0;
        enable = 1'b1;

        clock_once;

        if (dut.state !== 3'd1)
            fail("releasing BRAKE with ENABLE must return to STARTUP");

        if (brake_active)
            fail("brake_active must clear after leaving BRAKE");

        if (run)
            fail("STARTUP must not assert run immediately");


        // ============================================================
        // TEST 9: BRAKE RELEASE WITHOUT ENABLE
        // ============================================================

        $display("");
        $display("TEST 9: BRAKE release to IDLE");

        reset_dut;

        enable = 1'b1;

        clock_once;

        brake = 1'b1;

        clock_once;

        if (dut.state !== 3'd3)
            fail("failed to enter BRAKE");

        enable = 1'b0;
        brake  = 1'b0;

        clock_once;

        if (dut.state !== 3'd0)
            fail("releasing BRAKE without ENABLE must enter IDLE");


        // ============================================================
        // TEST 10: FAULT CONDITION
        // ============================================================

        $display("");
        $display("TEST 10: Immediate FAULT transition");

        reset_dut;

        enable = 1'b1;

        clock_once;

        hall_valid   = 1'b1;
        pwm_boundary = 1'b1;

        clock_once;

        if (dut.state !== 3'd2)
            fail("failed to establish RUN before fault test");

        pwm_boundary = 1'b0;

        fault_condition = 1'b1;

        clock_once;

        if (dut.state !== 3'd4)
            fail("fault_condition must move FSM to FAULT");

        if (run_enable)
            fail("run_enable must clear in FAULT");

        if (run)
            fail("run must clear in FAULT");

        if (brake_active)
            fail("FAULT must not assert brake_active");


        // ============================================================
        // TEST 11: FAULT LATCHED
        // ============================================================

        $display("");
        $display("TEST 11: Latched fault forces FAULT");

        reset_dut;

        enable = 1'b1;

        clock_once;

        fault_latched = 1'b1;

        clock_once;

        if (dut.state !== 3'd4)
            fail("fault_latched must force FSM to FAULT");

        if (run_enable || run)
            fail("latched fault must prevent RUN");


        // ============================================================
        // TEST 12: FAULT IS STICKY
        // ============================================================

        $display("");
        $display("TEST 12: FAULT state is sticky");

        fault_latched   = 1'b0;
        fault_condition = 1'b0;
        enable          = 1'b0;

        repeat (5)
            clock_once;

        if (dut.state !== 3'd4)
            fail("FAULT state must remain sticky");

        if (run_enable || run)
            fail("FAULT state must keep drive disabled");


        // ============================================================
        // TEST 13: HALL INVALID BLOCKS STARTUP
        // ============================================================

        $display("");
        $display("TEST 13: Invalid Hall blocks STARTUP");

        reset_dut;

        enable = 1'b1;

        clock_once;

        if (dut.state !== 3'd1)
            fail("failed to enter STARTUP");

        hall_valid   = 1'b0;
        pwm_boundary = 1'b1;

        clock_once;

        if (dut.state !== 3'd1)
            fail("invalid Hall must prevent STARTUP from entering RUN");

        if (run)
            fail("invalid Hall must not permit RUN");


        // ============================================================
        // TEST 14: HALL VALID WITHOUT PWM BOUNDARY
        // ============================================================

        $display("");
        $display("TEST 14: Valid Hall without PWM boundary");

        hall_valid   = 1'b1;
        pwm_boundary = 1'b0;

        clock_once;

        if (dut.state !== 3'd1)
            fail("valid Hall alone must not enter RUN");

        if (run)
            fail("RUN must wait for PWM boundary");


        // ============================================================
        // TEST 15: BRAKE HAS PRIORITY OVER STARTUP RUN
        // ============================================================

        $display("");
        $display("TEST 15: Brake priority during STARTUP");

        reset_dut;

        enable       = 1'b1;
        hall_valid   = 1'b1;
        pwm_boundary = 1'b1;
        brake        = 1'b1;

        clock_once;

        if (dut.state !== 3'd1)
            fail("first ENABLE clock must enter STARTUP");

        clock_once;

        if (dut.state !== 3'd3)
            fail("BRAKE must take priority over RUN qualification");

        if (!brake_active)
            fail("BRAKE state must assert brake_active");

        if (run)
            fail("BRAKE must prevent RUN");


        // ============================================================
        // FINAL RESULT
        // ============================================================

        $display("");

        if (errors == 0)
            $display("PASS: control_fsm unit verification");
        else
            $display(
                "FAIL: control_fsm unit verification: %0d checks failed",
                errors
            );

        $finish;

    end

endmodule
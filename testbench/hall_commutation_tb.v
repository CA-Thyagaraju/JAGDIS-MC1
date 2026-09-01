`timescale 1ns/1ps

module hall_commutation_tb;

    reg clk;
    reg reset_n;

    reg hall_a;
    reg hall_b;
    reg hall_c;

    reg dir;
    reg pwm_boundary;

    wire [2:0] hall_sync;
    wire       hall_valid;
    wire [2:0] hall_active;
    wire       hall_fault;
    wire [5:0] phase_cmd;

    integer errors;
    integer i;

    hall_commutation dut (
        .clk          (clk),
        .reset_n      (reset_n),
        .hall_a       (hall_a),
        .hall_b       (hall_b),
        .hall_c       (hall_c),
        .dir          (dir),
        .pwm_boundary (pwm_boundary),
        .hall_sync    (hall_sync),
        .hall_valid   (hall_valid),
        .hall_active  (hall_active),
        .hall_fault   (hall_fault),
        .phase_cmd    (phase_cmd)
    );

    always #10 clk = ~clk;


    task fail;
        input [8*100-1:0] message;
        begin
            errors = errors + 1;
            $display("FAIL: %0s", message);
        end
    endtask


    task set_hall;
        input [2:0] hall_value;
        begin
            {hall_a, hall_b, hall_c} = hall_value;
        end
    endtask


    task reset_dut;
        begin
            hall_a       = 1'b0;
            hall_b       = 1'b0;
            hall_c       = 1'b0;
            dir          = 1'b0;
            pwm_boundary = 1'b0;

            reset_n = 1'b0;

            #1;

            if (hall_active !== 3'b000)
                fail("reset must clear hall_active");

            if (hall_fault !== 1'b0)
                fail("reset must clear hall_fault");

            if (phase_cmd !== 6'b000000)
                fail("reset must produce zero phase command");

            repeat (3)
                @(posedge clk);

            reset_n = 1'b1;

            repeat (3) begin
                @(posedge clk);
                #1;
            end
        end
    endtask


    task pulse_pwm_boundary;
        begin
            pwm_boundary = 1'b1;
            @(posedge clk);
            #1;
            pwm_boundary = 1'b0;
        end
    endtask

    task wait_for_pending;
        input [2:0] expected_hall;
        begin
            i = 0;

            while ((!dut.pending_valid ||
                    dut.hall_pending !== expected_hall) &&
                (i < 20)) begin
                @(posedge clk);
                #1;
                i = i + 1;
            end

            if (!dut.pending_valid ||
                dut.hall_pending !== expected_hall)
                fail("Hall state did not become pending");
        end
    endtask

    initial begin

        clk          = 1'b0;
        reset_n      = 1'b0;

        hall_a       = 1'b0;
        hall_b       = 1'b0;
        hall_c       = 1'b0;

        dir          = 1'b0;
        pwm_boundary = 1'b0;

        errors = 0;


        $dumpfile("output/hall_commutation_tb.vcd");
        $dumpvars(0, hall_commutation_tb);


        // ============================================================
        // TEST 1: RESET
        // ============================================================

        $display("");
        $display("TEST 1: Reset");

        reset_dut;

        if (hall_active !== 3'b000)
            fail("hall_active incorrect after reset");

        if (hall_fault !== 1'b0)
            fail("hall_fault incorrect after reset");

        if (phase_cmd !== 6'b000000)
            fail("phase_cmd incorrect after reset");


        // ============================================================
        // TEST 2: HALL VALIDITY
        // ============================================================

        $display("");
        $display("TEST 2: Hall validity");

        reset_dut;

        set_hall(3'b001);

        repeat (3) begin
            @(posedge clk);
            #1;
        end

        if (!hall_valid)
            fail("001 should be a valid Hall state");

        set_hall(3'b101);

        repeat (3) begin
            @(posedge clk);
            #1;
        end

        if (!hall_valid)
            fail("101 should be a valid Hall state");

        set_hall(3'b100);

        repeat (3) begin
            @(posedge clk);
            #1;
        end

        if (!hall_valid)
            fail("100 should be a valid Hall state");

        set_hall(3'b110);

        repeat (3) begin
            @(posedge clk);
            #1;
        end

        if (!hall_valid)
            fail("110 should be a valid Hall state");

        set_hall(3'b010);

        repeat (3) begin
            @(posedge clk);
            #1;
        end

        if (!hall_valid)
            fail("010 should be a valid Hall state");

        set_hall(3'b011);

        repeat (3) begin
            @(posedge clk);
            #1;
        end

        if (!hall_valid)
            fail("011 should be a valid Hall state");

        set_hall(3'b111);

        repeat (3) begin
            @(posedge clk);
            #1;
        end

        if (hall_valid)
            fail("111 must be an invalid Hall state");

        set_hall(3'b000);

        repeat (3) begin
            @(posedge clk);
            #1;
        end

        if (hall_valid)
            fail("000 must be an invalid Hall state");


        // ============================================================
        // TEST 3: FORWARD COMMUTATION
        // ============================================================

        $display("");
        $display("TEST 3: Forward Hall transition validation");

        reset_dut;

        dir = 1'b0;


        // Startup Hall = 001.
        // Because hall_active is 000 after reset, any valid Hall state
        // is allowed to establish the initial pending state.

        set_hall(3'b001);
        wait_for_pending(3'b001);

        if (hall_active !== 3'b000)
            fail("Hall active changed before PWM boundary");

        pulse_pwm_boundary;

        if (hall_active !== 3'b001)
            fail("001 was not activated at PWM boundary");


        // 001 -> 101

        set_hall(3'b101);
        wait_for_pending(3'b101);

        if (hall_active !== 3'b001)
            fail("hall_active changed before 001 -> 101 PWM boundary");

        pulse_pwm_boundary;

        if (hall_active !== 3'b101)
            fail("101 was not activated at PWM boundary");


        // 101 -> 100

        set_hall(3'b100);
        wait_for_pending(3'b100);

        if (hall_active !== 3'b101)
            fail("hall_active changed before 101 -> 100 PWM boundary");

        pulse_pwm_boundary;

        if (hall_active !== 3'b100)
            fail("100 was not activated at PWM boundary");


        // 100 -> 110

        set_hall(3'b110);
        wait_for_pending(3'b110);

        if (hall_active !== 3'b100)
            fail("hall_active changed before 100 -> 110 PWM boundary");

        pulse_pwm_boundary;

        if (hall_active !== 3'b110)
            fail("110 was not activated at PWM boundary");


        // 110 -> 010

        set_hall(3'b010);
        wait_for_pending(3'b010);

        if (hall_active !== 3'b110)
            fail("hall_active changed before 110 -> 010 PWM boundary");

        pulse_pwm_boundary;

        if (hall_active !== 3'b010)
            fail("010 was not activated at PWM boundary");


        // 010 -> 011

        set_hall(3'b011);
        wait_for_pending(3'b011);

        if (hall_active !== 3'b010)
            fail("hall_active changed before 010 -> 011 PWM boundary");

        pulse_pwm_boundary;

        if (hall_active !== 3'b011)
            fail("011 was not activated at PWM boundary");


        // 011 -> 001

        set_hall(3'b001);
        wait_for_pending(3'b001);

        if (hall_active !== 3'b011)
            fail("hall_active changed before 011 -> 001 PWM boundary");

        pulse_pwm_boundary;

        if (hall_active !== 3'b001)
            fail("001 wrap transition was not activated at PWM boundary");

        // ============================================================
        // TEST 4: PHASE LOOKUP
        // ============================================================

        $display("");
        $display("TEST 4: Hall-to-phase lookup");

        if (phase_cmd !== 6'b100100)
            fail("Hall 001 must command A+ B-");

        set_hall(3'b101);
        repeat (3) @(posedge clk);
        pulse_pwm_boundary;

        if (phase_cmd !== 6'b100001)
            fail("Hall 101 must command A+ C-");

        set_hall(3'b100);
        repeat (3) @(posedge clk);
        pulse_pwm_boundary;

        if (phase_cmd !== 6'b001001)
            fail("Hall 100 must command B+ C-");

        set_hall(3'b110);
        repeat (3) @(posedge clk);
        pulse_pwm_boundary;

        if (phase_cmd !== 6'b011000)
            fail("Hall 110 must command B+ A-");

        set_hall(3'b010);
        repeat (3) @(posedge clk);
        pulse_pwm_boundary;

        if (phase_cmd !== 6'b010010)
            fail("Hall 010 must command C+ A-");

        set_hall(3'b011);
        repeat (3) @(posedge clk);
        pulse_pwm_boundary;

        if (phase_cmd !== 6'b000110)
            fail("Hall 011 must command C+ B-");


        // ============================================================
        // TEST 5: INVALID TRANSITION REJECTION
        // ============================================================

        $display("");
        $display("TEST 5: Invalid Hall transition rejection");

        reset_dut;

        dir = 1'b0;

        set_hall(3'b001);
        repeat (3) @(posedge clk);
        pulse_pwm_boundary;

        if (hall_active !== 3'b001)
            fail("invalid-transition test failed to establish Hall 001");

        // 001 -> 100 is not a valid forward transition.
        set_hall(3'b100);
        repeat (3) @(posedge clk);

        if (dut.pending_valid)
            fail("invalid 001 -> 100 transition must not become pending");

        pulse_pwm_boundary;

        if (hall_active !== 3'b001)
            fail("invalid transition must not change hall_active");


        // ============================================================
        // TEST 6: REVERSE COMMUTATION
        // ============================================================

        $display("");
        $display("TEST 6: Reverse Hall transition validation");

        reset_dut;

        dir = 1'b1;


        // Establish 001.

        set_hall(3'b001);
        wait_for_pending(3'b001);
        pulse_pwm_boundary;

        if (hall_active !== 3'b001)
            fail("reverse test failed to establish Hall 001");


        // 001 -> 011

        set_hall(3'b011);
        wait_for_pending(3'b011);

        if (hall_active !== 3'b001)
            fail("hall_active changed before reverse 001 -> 011 boundary");

        pulse_pwm_boundary;

        if (hall_active !== 3'b011)
            fail("reverse 001 -> 011 transition failed");


        // 011 -> 010

        set_hall(3'b010);
        wait_for_pending(3'b010);

        pulse_pwm_boundary;

        if (hall_active !== 3'b010)
            fail("reverse 011 -> 010 transition failed");


        // 010 -> 110

        set_hall(3'b110);
        wait_for_pending(3'b110);

        pulse_pwm_boundary;

        if (hall_active !== 3'b110)
            fail("reverse 010 -> 110 transition failed");


        // 110 -> 100

        set_hall(3'b100);
        wait_for_pending(3'b100);

        pulse_pwm_boundary;

        if (hall_active !== 3'b100)
            fail("reverse 110 -> 100 transition failed");


        // 100 -> 101

        set_hall(3'b101);
        wait_for_pending(3'b101);

        pulse_pwm_boundary;

        if (hall_active !== 3'b101)
            fail("reverse 100 -> 101 transition failed");


        // 101 -> 001

        set_hall(3'b001);
        wait_for_pending(3'b001);

        pulse_pwm_boundary;

        if (hall_active !== 3'b001)
            fail("reverse 101 -> 001 wrap transition failed");

        // ============================================================
        // TEST 7: LATEST VALID HALL WINS
        // ============================================================

        $display("");
        $display("TEST 7: Latest-valid-Hall-wins");

        reset_dut;

        dir = 1'b0;


        // Establish Hall 001.

        set_hall(3'b001);
        wait_for_pending(3'b001);
        pulse_pwm_boundary;

        if (hall_active !== 3'b001)
            fail("latest-Hall test failed to establish Hall 001");


        // ------------------------------------------------------------
        // 001 -> 101
        // ------------------------------------------------------------

        set_hall(3'b101);
        wait_for_pending(3'b101);

        if (!dut.pending_valid ||
            dut.hall_pending !== 3'b101)
            fail("101 did not become pending");

        if (hall_active !== 3'b001)
            fail("hall_active changed before PWM boundary");


        // ------------------------------------------------------------
        // 101 -> 100 BEFORE PWM BOUNDARY
        //
        // The active state is STILL 001.
        //
        // Therefore 100 must be validated against the pending 101,
        // not against the active 001.
        // ------------------------------------------------------------

        set_hall(3'b100);
        wait_for_pending(3'b100);

        if (!dut.pending_valid ||
            dut.hall_pending !== 3'b100)
            fail("latest valid Hall state did not replace 101");

        if (hall_active !== 3'b001)
            fail("hall_active changed before latest-Hall PWM boundary");


        // ------------------------------------------------------------
        // PWM boundary
        //
        // Only the latest pending state, 100, should become active.
        // ------------------------------------------------------------

        pulse_pwm_boundary;

        if (hall_active !== 3'b100)
            fail("latest pending Hall state was not committed");

        if (phase_cmd !== 6'b001001)
            fail("Hall 100 must command B+ C-");

        // ============================================================
        // TEST 8: INVALID HALL GRACE PERIOD AND FAULT
        // ============================================================

        $display("");
        $display("TEST 8: Invalid Hall grace period and fault");

        reset_dut;

        dir = 1'b0;


        // ------------------------------------------------------------
        // Establish a valid operating state.
        // ------------------------------------------------------------

        set_hall(3'b001);
        wait_for_pending(3'b001);
        pulse_pwm_boundary;

        if (hall_active !== 3'b001)
            fail("invalid-Hall test failed to establish Hall 001");

        if (hall_fault)
            fail("hall_fault must be clear during valid operation");


        // ------------------------------------------------------------
        // Apply invalid Hall state 000.
        //
        // The first invalid PWM period must consume the grace period,
        // but must NOT assert hall_fault.
        // ------------------------------------------------------------

        set_hall(3'b000);


        // Wait for the synchronized Hall state to become invalid.

        i = 0;

        while (hall_valid && (i < 20)) begin
            @(posedge clk);
            #1;
            i = i + 1;
        end

        if (hall_valid)
            fail("000 did not become an invalid synchronized Hall state");


        // First PWM boundary: consume the grace period.
        pulse_pwm_boundary;

        if (!dut.grace_used)
            fail("first invalid Hall period did not consume grace");

        if (hall_fault)
            fail("first invalid Hall period must not assert hall_fault");

        if (hall_active !== 3'b001)
            fail("invalid Hall must not change hall_active");


        // ------------------------------------------------------------
        // The Hall input is STILL invalid.
        //
        // Wait for the NEXT PWM boundary.
        //
        // The second consecutive invalid period must assert hall_fault.
        // ------------------------------------------------------------

        // Second consecutive PWM boundary: assert Hall fault.
        pulse_pwm_boundary;
        if (!hall_fault)
            fail("second consecutive invalid Hall period must assert hall_fault");


        // The invalid Hall state must never become active.

        if (hall_active !== 3'b001)
            fail("Hall fault must preserve the last valid hall_active state");

        // ============================================================
        // FINAL RESULT
        // ============================================================

        $display("");

        if (errors == 0)
            $display("PASS: hall_commutation unit verification");

        else
            $display(
                "FAIL: hall_commutation unit verification: %0d checks failed",
                errors
            );

        $finish;
    end

endmodule
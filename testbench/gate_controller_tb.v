`timescale 1ns/1ps

module gate_controller_tb;

    reg clk;
    reg reset_n;
    reg run_enable;
    reg brake_active;
    reg pwm_raw;
    reg [5:0] phase_cmd;

    wire gh_a, gl_a;
    wire gh_b, gl_b;
    wire gh_c, gl_c;

    integer errors;
    integer i;

    gate_controller #(
        .DEAD_TIME_CLKS(6'd25)
    ) dut (
        .clk          (clk),
        .reset_n      (reset_n),
        .run_enable   (run_enable),
        .brake_active (brake_active),
        .pwm_raw      (pwm_raw),
        .phase_cmd    (phase_cmd),
        .gh_a         (gh_a),
        .gl_a         (gl_a),
        .gh_b         (gh_b),
        .gl_b         (gl_b),
        .gh_c         (gh_c),
        .gl_c         (gl_c)
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
            run_enable   = 1'b0;
            brake_active = 1'b0;
            pwm_raw      = 1'b0;
            phase_cmd    = 6'b000000;

            reset_n = 1'b0;
            #1;

            if ({gh_a,gl_a,gh_b,gl_b,gh_c,gl_c} !== 6'b000000)
                fail("reset must force all gates low");

            repeat (3)
                @(posedge clk);

            reset_n = 1'b1;

            repeat (2) begin
                @(posedge clk);
                #1;
            end
        end
    endtask


    task check_all_off;
        input [8*100-1:0] message;
        begin
            if ({gh_a,gl_a,gh_b,gl_b,gh_c,gl_c} !== 6'b000000)
                fail(message);
        end
    endtask


    task check_no_shoot_through;
        begin
            if (gh_a && gl_a)
                fail("phase A high and low gates must never overlap");

            if (gh_b && gl_b)
                fail("phase B high and low gates must never overlap");

            if (gh_c && gl_c)
                fail("phase C high and low gates must never overlap");
        end
    endtask


    initial begin

        clk = 1'b0;
        reset_n = 1'b0;

        run_enable   = 1'b0;
        brake_active = 1'b0;
        pwm_raw      = 1'b0;
        phase_cmd    = 6'b000000;

        errors = 0;

        $dumpfile("output/gate_controller_tb.vcd");
        $dumpvars(0, gate_controller_tb);


        // ============================================================
        // TEST 1: RESET
        // ============================================================

        $display("");
        $display("TEST 1: Reset");

        reset_dut;

        check_all_off("reset must leave all gates off");


        // ============================================================
        // TEST 2: DISABLED CONTROLLER
        // ============================================================

        $display("");
        $display("TEST 2: Run disabled");

        phase_cmd  = 6'b100100;
        pwm_raw    = 1'b1;
        run_enable = 1'b0;

        @(posedge clk);
        #1;

        check_all_off("run_enable=0 must disable all gates");


        // ============================================================
        // TEST 3: FORWARD PHASE COMMANDS
        // ============================================================

        $display("");
        $display("TEST 3: Six-step phase command mapping");

        run_enable = 1'b1;
        pwm_raw    = 1'b1;


        // 001 = A+ B-
        phase_cmd = 6'b100100;

        @(posedge clk);
        #1;

        if ({gh_a,gl_a,gh_b,gl_b,gh_c,gl_c} !== 6'b100100)
            fail("001 phase command must produce A+ B-");

        check_no_shoot_through;


        // 101 = A+ C-
        phase_cmd = 6'b100001;

        // Allow A transition and C activation.
        repeat (26) begin
            @(posedge clk);
            #1;
            check_no_shoot_through;
        end

        if ({gh_a,gl_a,gh_b,gl_b,gh_c,gl_c} !== 6'b100001)
            fail("101 phase command must produce A+ C-");

        check_no_shoot_through;


        // 100 = B+ C-
        phase_cmd = 6'b001001;

        repeat (26) begin
            @(posedge clk);
            #1;
            check_no_shoot_through;
        end

        if ({gh_a,gl_a,gh_b,gl_b,gh_c,gl_c} !== 6'b001001)
            fail("100 phase command must produce B+ C-");


        // 110 = B+ A-
        phase_cmd = 6'b011000;

        repeat (26) begin
            @(posedge clk);
            #1;
            check_no_shoot_through;
        end

        if ({gh_a,gl_a,gh_b,gl_b,gh_c,gl_c} !== 6'b011000)
            fail("110 phase command must produce B+ A-");


        // 010 = C+ A-
        phase_cmd = 6'b010010;

        repeat (26) begin
            @(posedge clk);
            #1;
            check_no_shoot_through;
        end

        if ({gh_a,gl_a,gh_b,gl_b,gh_c,gl_c} !== 6'b010010)
            fail("010 phase command must produce C+ A-");


        // 011 = C+ B-
        phase_cmd = 6'b000110;

        repeat (26) begin
            @(posedge clk);
            #1;
            check_no_shoot_through;
        end

        if ({gh_a,gl_a,gh_b,gl_b,gh_c,gl_c} !== 6'b000110)
            fail("011 phase command must produce C+ B-");


        // ============================================================
        // TEST 4: PWM HIGH-SIDE CONTROL
        // ============================================================

        $display("");
        $display("TEST 4: PWM high-side control");

        phase_cmd = 6'b100100;
        pwm_raw   = 1'b0;

        repeat (26) begin
            @(posedge clk);
            #1;
        end

        if (gh_a !== 1'b0)
            fail("PWM low must turn selected high side off");

        if (gl_b !== 1'b1)
            fail("selected low side must remain on when PWM is low");

        if (gl_a !== 1'b0 || gh_b !== 1'b0 ||
            gh_c !== 1'b0 || gl_c !== 1'b0)
            fail("unselected gates must remain off");


        pwm_raw = 1'b1;

        @(posedge clk);
        #1;

        if (gh_a !== 1'b1)
            fail("PWM high must enable selected high side");

        if (gl_b !== 1'b1)
            fail("selected low side must remain on with PWM high");

        check_no_shoot_through;


        // ============================================================
        // TEST 5: BRAKE
        // ============================================================

        $display("");
        $display("TEST 5: Brake");

        brake_active = 1'b1;

        repeat (26) begin
            @(posedge clk);
            #1;
        end

        check_all_off("brake_active must turn all gates off");

        brake_active = 1'b0;


        // ============================================================
        // TEST 6: ZERO PHASE COMMAND
        // ============================================================

        $display("");
        $display("TEST 6: Zero phase command");

        phase_cmd = 6'b000000;
        pwm_raw   = 1'b1;

        repeat (26) begin
            @(posedge clk);
            #1;
        end

        check_all_off("zero phase command must turn all gates off");


        // ============================================================
        // TEST 7: INVALID SIMULTANEOUS PHASE REQUEST
        // ============================================================

        $display("");
        $display("TEST 7: Invalid phase command");

        // Request both devices in phase A.
        phase_cmd = 6'b110000;

        repeat (2) begin
            @(posedge clk);
            #1;
        end

        if (gh_a !== 1'b0 || gl_a !== 1'b0)
            fail("simultaneous A high and low request must fail safe");

        check_no_shoot_through;


        // ============================================================
        // TEST 8: COMMUTATION DEAD TIME
        // ============================================================

        $display("");
        $display("TEST 8: Commutation dead time");

        reset_dut;

        run_enable = 1'b1;
        pwm_raw    = 1'b1;

        // Start A+ B-.
        phase_cmd = 6'b100100;

        @(posedge clk);
        #1;

        if (gh_a !== 1'b1 || gl_b !== 1'b1)
            fail("failed to establish A+ B- before dead-time test");

        // Change to B+ C-.
        // A high must turn off before B high becomes active.
        phase_cmd = 6'b001001;

        @(posedge clk);
        #1;

        if (gh_a || gl_a)
            fail("phase A must be off when leaving A+ state");

        // All phases should remain shoot-through safe.
        check_no_shoot_through;

        // Verify dead interval.
        for (i = 0; i < 24; i = i + 1) begin
            @(posedge clk);
            #1;
            check_no_shoot_through;
        end

        // After the dead time the requested B+/C- state should appear.
        @(posedge clk);
        #1;

        if ({gh_a,gl_a,gh_b,gl_b,gh_c,gl_c} !== 6'b001001)
            fail("new commutation state did not appear after dead time");

        check_no_shoot_through;


        // ============================================================
        // TEST 9: RUN DISABLE
        // ============================================================

        $display("");
        $display("TEST 9: Run disable");

        run_enable = 1'b0;

        repeat (26) begin
            @(posedge clk);
            #1;
        end

        check_all_off("disabling run_enable must turn all gates off");


        // ============================================================
        // FINAL RESULT
        // ============================================================

        $display("");

        if (errors == 0)
            $display("PASS: gate_controller unit verification");
        else
            $display(
                "FAIL: gate_controller unit verification: %0d checks failed",
                errors
            );

        $finish;
    end

endmodule
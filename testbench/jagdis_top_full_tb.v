`timescale 1ns/1ps

// Self-checking functional verification for the frozen JAGDIS-MC1 V1 RTL.
// This test retains real V1 timing: 50 MHz clock, 1250-clock PWM, and 25
// clock dead time.  It writes output/jagdis_top_full.vcd when run from the
// project root.
module jagdis_top_full_tb;
    reg clk;
    reg reset_n;
    reg hall_a, hall_b, hall_c;
    reg [9:0] duty;
    reg enable, dir, brake;
    reg oc_fault, uv_fault, ot_fault;
    wire gh_a, gl_a, gh_b, gl_b, gh_c, gl_c, run, fault;
    integer errors;
    integer i;
    integer pwm_high_count;

    jagdis_top dut (
        .CLK(clk), .RESET_N(reset_n),
        .HALL_A(hall_a), .HALL_B(hall_b), .HALL_C(hall_c),
        .DUTY(duty), .ENABLE(enable), .DIR(dir), .BRAKE(brake),
        .OC_FAULT(oc_fault), .UV_FAULT(uv_fault), .OT_FAULT(ot_fault),
        .GH_A(gh_a), .GL_A(gl_a), .GH_B(gh_b), .GL_B(gl_b),
        .GH_C(gh_c), .GL_C(gl_c), .RUN(run), .FAULT(fault)
    );

    // Unit-level interlock instance: normal six-step operation does not
    // directly swap a phase from high-side to low-side, so this verifies the
    // frozen same-phase dead-time rule explicitly.
    reg interlock_high_request, interlock_low_request;
    wire interlock_high, interlock_low;
    gate_phase #(.DEAD_TIME_CLKS(6'd25)) interlock_dut (
        .clk(clk), .reset_n(reset_n),
        .request_high(interlock_high_request),
        .request_low(interlock_low_request),
        .gate_high(interlock_high), .gate_low(interlock_low)
    );

    always #10 clk = ~clk;

    task fail;
        input [8*80-1:0] message;
        begin
            errors = errors + 1;
            $display("FAIL: %0s", message);
        end
    endtask

    task expect_gates;
        input [5:0] expected;
        input [8*80-1:0] message;
        begin
            if ({gh_a, gl_a, gh_b, gl_b, gh_c, gl_c} !== expected)
                fail(message);
        end
    endtask

    task wait_for_run;
        begin
            i = 0;
            while (!run && (i < 3000)) begin
                @(posedge clk);
                #1;
                i = i + 1;
            end
            if (!run)
                fail("controller did not enter RUN");
        end
    endtask

    task wait_for_hall_active;
        input [2:0] expected_hall;
        begin
            i = 0;
            while ((dut.hall_active !== expected_hall) && (i < 3000)) begin
                @(posedge clk);
                #1;
                i = i + 1;
            end
            if (dut.hall_active !== expected_hall)
                fail("Hall state did not become active at a PWM boundary");
            // Allow the registered gate stage to consume the new request.
            repeat (30) begin @(posedge clk); #1; end
        end
    endtask

    task reset_controller;
        begin
            enable = 1'b0;
            brake = 1'b0;
            dir = 1'b0;
            duty = 10'd0;
            oc_fault = 1'b0;
            uv_fault = 1'b0;
            ot_fault = 1'b0;
            reset_n = 1'b0;
            #1;
            expect_gates(6'b000000, "reset must force all gates low immediately");
            repeat (3) @(posedge clk);
            reset_n = 1'b1;
            repeat (4) begin @(posedge clk); #1; end
            if (fault)
                fail("reset did not clear FAULT");
        end
    endtask

    task set_hall;
        input [2:0] hall_value;
        begin
            {hall_a, hall_b, hall_c} = hall_value;
        end
    endtask

    task start_forward_full_duty;
        begin
            set_hall(3'b001);
            dir = 1'b0;
            duty = 10'd1023;
            enable = 1'b1;
            wait_for_run;
            wait_for_hall_active(3'b001);
            expect_gates(6'b100100, "001 must command A+ B- at 100 percent duty");
        end
    endtask

    initial begin
        clk = 1'b0;
        reset_n = 1'b0;
        hall_a = 1'b0;
        hall_b = 1'b0;
        hall_c = 1'b0;
        duty = 10'd0;
        enable = 1'b0;
        dir = 1'b0;
        brake = 1'b0;
        oc_fault = 1'b0;
        uv_fault = 1'b0;
        ot_fault = 1'b0;
        interlock_high_request = 1'b0;
        interlock_low_request = 1'b0;
        errors = 0;
        $dumpfile("output/jagdis_top_full.vcd");
        $dumpvars(0, jagdis_top_full_tb);

        // Reset and forward commutation table.
        reset_controller;
        set_hall(3'b001);
        start_forward_full_duty;

        set_hall(3'b101); wait_for_hall_active(3'b101); expect_gates(6'b100001, "101 must command A+ C-");
        set_hall(3'b100); wait_for_hall_active(3'b100); expect_gates(6'b001001, "100 must command B+ C-");
        set_hall(3'b110); wait_for_hall_active(3'b110); expect_gates(6'b011000, "110 must command B+ A-");
        set_hall(3'b010); wait_for_hall_active(3'b010); expect_gates(6'b010010, "010 must command C+ A-");
        set_hall(3'b011); wait_for_hall_active(3'b011); expect_gates(6'b000110, "011 must command C+ B-");
        set_hall(3'b001); wait_for_hall_active(3'b001); expect_gates(6'b100100, "forward sequence must wrap to 001");

            // Latest-valid-Hall-wins regression.
    //
    // A Hall transition may occur more than once within one PWM period.
    // hall_active must remain unchanged until the PWM boundary, while
    // hall_pending tracks the latest valid Hall state.
    //
    // Sequence:
    //     001 active
    //       ↓
    //     101 pending
    //       ↓
    //     100 pending (replaces 101)
    //       ↓
    //     PWM boundary
    //       ↓
    //     100 active

    // Align to the beginning of a PWM period.
    i = 0;
    while ((dut.pwm_counter != 11'd0) && (i < 1300)) begin
        @(posedge clk); #1;
        i = i + 1;
    end

    if (dut.pwm_counter != 11'd0)
        fail("could not align latest-Hall test to PWM period start");

    // First valid transition: 001 -> 101.
    set_hall(3'b101);

    i = 0;
    while ((!dut.hall.pending_valid ||
            dut.hall.hall_pending !== 3'b101) &&
           (i < 20)) begin
        @(posedge clk); #1;
        i = i + 1;
    end

    if (!dut.hall.pending_valid ||
        dut.hall.hall_pending !== 3'b101)
        fail("101 did not become the pending Hall state");

    if (dut.hall.hall_active !== 3'b001)
        fail("active Hall changed before PWM boundary");

    // Second valid transition arrives before the PWM boundary:
    // 101 -> 100. The new RTL must validate 100 against the pending
    // 101 state rather than the still-active 001 state.
    set_hall(3'b100);

    i = 0;
    while ((!dut.hall.pending_valid ||
            dut.hall.hall_pending !== 3'b100) &&
           (i < 20)) begin
        @(posedge clk); #1;
        i = i + 1;
    end

    if (!dut.hall.pending_valid ||
        dut.hall.hall_pending !== 3'b100)
        fail("latest valid Hall state did not replace previous pending state");

    if (dut.hall.hall_active !== 3'b001)
        fail("active Hall changed before PWM boundary during latest-Hall test");

    // Wait for the PWM boundary and verify that the latest pending state,
    // 100 rather than the stale 101, becomes active.
    i = 0;
    while ((dut.hall.hall_active !== 3'b100) && (i < 1300)) begin
        @(posedge clk); #1;
        i = i + 1;
    end

        if (dut.hall.hall_active !== 3'b100)
            fail("latest valid Hall state was not committed at PWM boundary");
                if (dut.hall.phase_cmd !== 6'b001001)
            fail("Hall 100 must command B+ C- after latest-Hall commit");

        // Restore the known Hall-001 operating state expected by the
        // subsequent duty-cycle tests.
        reset_controller;
        start_forward_full_duty;

       // Duty transfer is boundary-aligned and preserves the exact mapping.
        duty = 10'd512;
        if (dut.duty_active !== 10'd1023)
            fail("DUTY changed duty_active before the PWM boundary");
        i = 0;
        while ((dut.duty_active !== 10'd512) && (i < 1300)) begin
            @(posedge clk); #1; i = i + 1;
        end
        if (dut.duty_active !== 10'd512)
            fail("DUTY did not transfer at the next PWM boundary");
        if (dut.compare_value !== 11'd625)
            fail("DUTY 512 must map to compare value 625");
        // PWM_RAW must be high for exactly CMP intervals in one carrier.
        i = 0;
        while ((dut.pwm_counter != 11'd0) && (i < 1300)) begin
            @(posedge clk); #1; i = i + 1;
        end
        pwm_high_count = 0;
        for (i = 0; i < 1250; i = i + 1) begin
            if (dut.pwm_raw)
                pwm_high_count = pwm_high_count + 1;
            @(posedge clk); #1;
        end
        if (pwm_high_count != 625)
            fail("DUTY 512 must produce 625 high PWM clock intervals");

        duty = 10'd0;
        i = 0;
        while ((dut.duty_active !== 10'd0) && (i < 1300)) begin
            @(posedge clk); #1; i = i + 1;
        end
        if (dut.compare_value !== 11'd0)
            fail("DUTY 0 must map to compare value 0");
        expect_gates(6'b000100, "zero duty must keep selected low side on and high sides off");

        duty = 10'd1023;
        i = 0;
        while ((dut.duty_active !== 10'd1023) && (i < 1300)) begin
            @(posedge clk); #1; i = i + 1;
        end
        if (dut.compare_value !== 11'd1250)
            fail("DUTY 1023 must map to compare value 1250");

        // V1 brake is gate-off/coast.
        brake = 1'b1;
        repeat (3) begin @(posedge clk); #1; end
        expect_gates(6'b000000, "BRAKE must turn all gates off");
        if (run)
            fail("BRAKE must clear RUN");

        // Verify all external faults have immediate gate-off and latch behavior.
        reset_controller; start_forward_full_duty;
        oc_fault = 1'b1; #1;
        expect_gates(6'b000000, "OC_FAULT must asynchronously turn all gates off");
        repeat (2) begin @(posedge clk); #1; end
        if (!fault || run) fail("OC_FAULT must latch FAULT and clear RUN");

        reset_controller; start_forward_full_duty;
        uv_fault = 1'b1; #1;
        expect_gates(6'b000000, "UV_FAULT must asynchronously turn all gates off");
        repeat (2) begin @(posedge clk); #1; end
        if (!fault || run) fail("UV_FAULT must latch FAULT and clear RUN");

        reset_controller; start_forward_full_duty;
        ot_fault = 1'b1; #1;
        expect_gates(6'b000000, "OT_FAULT must asynchronously turn all gates off");
        repeat (2) begin @(posedge clk); #1; end
        if (!fault || run) fail("OT_FAULT must latch FAULT and clear RUN");

        // One invalid Hall PWM period is tolerated; a second causes shutdown.
        reset_controller; start_forward_full_duty;
        set_hall(3'b000);
        i = 0;
        while (!dut.hall.grace_used && (i < 1500)) begin
            @(posedge clk); #1; i = i + 1;
        end
        if (!dut.hall.grace_used || fault)
            fail("first invalid-Hall PWM period must be grace, not FAULT");
        i = 0;
        while (!fault && (i < 1500)) begin
            @(posedge clk); #1; i = i + 1;
        end
        if (!fault)
            fail("persistent invalid Hall must latch FAULT after grace");

        // DIR selects the expected transition sequence; it does not alter the
        // Hall-to-phase-command lookup table.
        reset_controller;
        set_hall(3'b001);
        dir = 1'b1;
        duty = 10'd1023;
        enable = 1'b1;
        wait_for_run;
        wait_for_hall_active(3'b001);
        set_hall(3'b011); wait_for_hall_active(3'b011); expect_gates(6'b000110, "reverse 001 to 011 must command C+ B-");
        set_hall(3'b010); wait_for_hall_active(3'b010); expect_gates(6'b010010, "reverse 011 to 010 must command C+ A-");

        // Same-phase high-to-low transition has exactly 25 all-off clock slots.
        reset_controller;
        interlock_high_request = 1'b1;
        @(posedge clk); #1;
        if (!interlock_high || interlock_low)
            fail("interlock did not enable requested high side");
        interlock_high_request = 1'b0;
        interlock_low_request = 1'b1;
        @(posedge clk); #1;
        if (interlock_high || interlock_low)
            fail("interlock must turn both devices off before dead time");
        for (i = 0; i < 24; i = i + 1) begin
            @(posedge clk); #1;
            if (interlock_high || interlock_low)
                fail("dead time ended before 25 clock cycles");
        end
        @(posedge clk); #1;
        if (interlock_high || !interlock_low)
            fail("interlock did not enable low side after 25-clock dead time");

        if (errors == 0)
            $display("PASS: JAGDIS full RTL verification");
        else
            $display("FAIL: JAGDIS full RTL verification: %0d checks failed", errors);
        $finish;
    end
endmodule

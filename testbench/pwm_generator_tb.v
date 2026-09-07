`timescale 1ns/1ps

module pwm_generator_tb;

    reg clk;
    reg reset_n;
    reg [9:0] duty;

    wire [10:0] pwm_counter;
    wire [9:0] duty_shadow;
    wire [9:0] duty_active;
    wire [10:0] compare_value;
    wire pwm_raw;
    wire pwm_boundary;

    integer errors;
    integer i;
    integer high_count;
    integer boundary_count;

    pwm_generator #(
        .PWM_PERIOD_CLKS(11'd1250)
    ) dut (
        .clk           (clk),
        .reset_n       (reset_n),
        .duty          (duty),
        .pwm_counter   (pwm_counter),
        .duty_shadow   (duty_shadow),
        .duty_active   (duty_active),
        .compare_value (compare_value),
        .pwm_raw       (pwm_raw),
        .pwm_boundary  (pwm_boundary)
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
            duty    = 10'd0;
            reset_n = 1'b0;

            #1;

            if (pwm_counter !== 11'd0)
                fail("reset must clear pwm_counter");

            if (duty_shadow !== 10'd0)
                fail("reset must clear duty_shadow");

            if (duty_active !== 10'd0)
                fail("reset must clear duty_active");

            if (compare_value !== 11'd0)
                fail("reset must produce compare value 0");

            if (pwm_raw !== 1'b0)
                fail("reset must produce PWM low");

            repeat (3)
                @(posedge clk);

            reset_n = 1'b1;

            repeat (3) begin
                @(posedge clk);
                #1;
            end
        end
    endtask


    task wait_for_boundary;
        begin
            i = 0;

            while (!pwm_boundary && (i < 1300)) begin
                @(posedge clk);
                #1;
                i = i + 1;
            end

            if (!pwm_boundary)
                fail("PWM boundary was not reached");
        end
    endtask


    initial begin

        clk     = 1'b0;
        reset_n = 1'b0;
        duty    = 10'd0;
        errors  = 0;


        $dumpfile("output/simulation_artifacts/pwm_generator_tb.vcd");
        $dumpvars(0, pwm_generator_tb);


        // ============================================================
        // TEST 1: RESET
        // ============================================================

        $display("");
        $display("TEST 1: Reset");

        reset_dut;


        // ============================================================
        // TEST 2: PWM PERIOD
        // ============================================================

        $display("");
        $display("TEST 2: PWM period and boundary");

        reset_dut;

        // reset_dut releases reset and allows a few clocks to pass,
        // so the counter is not expected to still be zero here.

        // Count complete PWM periods.
        boundary_count = 0;

        for (i = 0; i < 2500; i = i + 1) begin
            @(posedge clk);
            #1;

            if (pwm_boundary)
                boundary_count = boundary_count + 1;
        end

        if (boundary_count !== 2)
            fail("1250-clock PWM must produce exactly two boundaries in 2500 clocks");


        // ============================================================
        // TEST 3: PWM COUNTER SEQUENCE
        // ============================================================

        $display("");
        $display("TEST 3: PWM counter sequence");

        reset_dut;

        // Align to the next actual counter-zero state.
        i = 0;

        while ((pwm_counter !== 11'd0) && (i < 1300)) begin
            @(posedge clk);
            #1;
            i = i + 1;
        end

        if (pwm_counter !== 11'd0)
            fail("PWM counter did not return to zero");

        // Verify 0 -> 1.
        @(posedge clk);
        #1;

        if (pwm_counter !== 11'd1)
            fail("PWM counter must increment from 0 to 1");

        // Verify the counter reaches 1248.
        // We are currently at 1, so 1247 further clock edges
        // should bring it to 1248.
        for (i = 0; i < 1247; i = i + 1) begin
            @(posedge clk);
            #1;
        end

        if (pwm_counter !== 11'd1248)
            fail("PWM counter did not reach 1248 correctly");

        // Next clock must produce 1249.
        @(posedge clk);
        #1;

        if (pwm_counter !== 11'd1249)
            fail("PWM counter must reach 1249 before wrapping");

        // At counter 1249, pwm_boundary must be asserted.
        if (!pwm_boundary)
            fail("PWM boundary must be asserted at counter 1249");

        // Next clock wraps to zero.
        @(posedge clk);
        #1;

        if (pwm_counter !== 11'd0)
            fail("PWM counter must wrap from 1249 to 0");

        // ============================================================
        // TEST 4: DUTY SHADOW / ACTIVE TRANSFER
        // ============================================================

        $display("");
        $display("TEST 4: Boundary-aligned duty transfer");

        reset_dut;

        duty = 10'd512;

        // duty_shadow should capture DUTY on a clock edge.
        @(posedge clk);
        #1;

        if (duty_shadow !== 10'd512)
            fail("DUTY must transfer into duty_shadow");

        // duty_active must not change immediately.
        if (duty_active !== 10'd0)
            fail("duty_active must remain unchanged before PWM boundary");

        // Wait until the boundary.
        wait_for_boundary;

        // At the boundary, duty_active is loaded from duty_shadow.
        @(posedge clk);
        #1;

        if (duty_active !== 10'd512)
            fail("duty_active must update at PWM boundary");


        // ============================================================
        // TEST 5: DUTY 0
        // ============================================================

        $display("");
        $display("TEST 5: DUTY 0");

        duty = 10'd0;

        wait_for_boundary;

        @(posedge clk);
        #1;

        if (duty_active !== 10'd0)
            fail("DUTY 0 must transfer to duty_active");

        if (compare_value !== 11'd0)
            fail("DUTY 0 must map to compare value 0");

        if (pwm_raw)
            fail("DUTY 0 must keep PWM low");


        // ============================================================
        // TEST 6: DUTY 512
        // ============================================================

        $display("");
        $display("TEST 6: DUTY 512 compare mapping");

        duty = 10'd512;

        wait_for_boundary;

        @(posedge clk);
        #1;

        if (duty_active !== 10'd512)
            fail("DUTY 512 must transfer to duty_active");

        if (compare_value !== 11'd625)
            fail("DUTY 512 must map to compare value 625");


        // ============================================================
        // TEST 7: DUTY 1023
        // ============================================================

        $display("");
        $display("TEST 7: DUTY 1023 compare mapping");

        duty = 10'd1023;

        wait_for_boundary;

        @(posedge clk);
        #1;

        if (duty_active !== 10'd1023)
            fail("DUTY 1023 must transfer to duty_active");

        if (compare_value !== 11'd1250)
            fail("DUTY 1023 must map to compare value 1250");


        // ============================================================
        // TEST 8: EXACT PWM HIGH COUNT
        // ============================================================

        $display("");
        $display("TEST 8: Exact PWM high interval count");

        reset_dut;

        duty = 10'd512;

        wait_for_boundary;

        @(posedge clk);
        #1;

        if (duty_active !== 10'd512)
            fail("DUTY 512 was not activated");

        if (compare_value !== 11'd625)
            fail("DUTY 512 compare value incorrect");

        // Align to counter zero.
        while (pwm_counter !== 11'd0) begin
            @(posedge clk);
            #1;
        end

        high_count = 0;

        for (i = 0; i < 1250; i = i + 1) begin

            if (pwm_raw)
                high_count = high_count + 1;

            @(posedge clk);
            #1;
        end

        if (high_count !== 625)
            fail("DUTY 512 must produce exactly 625 high intervals");


        // ============================================================
        // TEST 9: 100% PWM
        // ============================================================

        $display("");
        $display("TEST 9: 100 percent PWM");

        duty = 10'd1023;

        wait_for_boundary;

        @(posedge clk);
        #1;

        if (compare_value !== 11'd1250)
            fail("100 percent duty must produce compare value 1250");

        while (pwm_counter !== 11'd0) begin
            @(posedge clk);
            #1;
        end

        high_count = 0;

        for (i = 0; i < 1250; i = i + 1) begin

            if (pwm_raw)
                high_count = high_count + 1;

            @(posedge clk);
            #1;
        end

        if (high_count !== 1250)
            fail("100 percent duty must produce 1250 high intervals");


        // ============================================================
        // TEST 10: 0 PERCENT PWM
        // ============================================================

        $display("");
        $display("TEST 10: 0 percent PWM");

        duty = 10'd0;

        wait_for_boundary;

        @(posedge clk);
        #1;

        if (compare_value !== 11'd0)
            fail("0 percent duty must produce compare value 0");

        while (pwm_counter !== 11'd0) begin
            @(posedge clk);
            #1;
        end

        high_count = 0;

        for (i = 0; i < 1250; i = i + 1) begin

            if (pwm_raw)
                high_count = high_count + 1;

            @(posedge clk);
            #1;
        end

        if (high_count !== 0)
            fail("0 percent duty must produce zero high intervals");


        // ============================================================
        // FINAL RESULT
        // ============================================================

        $display("");

        if (errors == 0)
            $display("PASS: pwm_generator unit verification");
        else
            $display(
                "FAIL: pwm_generator unit verification: %0d checks failed",
                errors
            );

        $finish;

    end

endmodule
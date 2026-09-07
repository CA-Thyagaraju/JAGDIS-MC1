`timescale 1ns/1ps

// Small integration smoke test for the frozen V1 start and fault behavior.
module jagdis_top_smoke_tb;
    reg clk = 1'b0;
    reg reset_n = 1'b0;
    reg hall_a = 1'b0;
    reg hall_b = 1'b0;
    reg hall_c = 1'b1; // 001: A+ B-
    reg [9:0] duty = 10'd1023;
    reg enable = 1'b1;
    reg dir = 1'b0;
    reg brake = 1'b0;
    reg oc_fault = 1'b0;
    reg uv_fault = 1'b0;
    reg ot_fault = 1'b0;
    wire gh_a, gl_a, gh_b, gl_b, gh_c, gl_c, run, fault;

    always #10 clk = ~clk;

    jagdis_top dut (
        .CLK(clk), .RESET_N(reset_n), .HALL_A(hall_a), .HALL_B(hall_b), .HALL_C(hall_c),
        .DUTY(duty), .ENABLE(enable), .DIR(dir), .BRAKE(brake),
        .OC_FAULT(oc_fault), .UV_FAULT(uv_fault), .OT_FAULT(ot_fault),
        .GH_A(gh_a), .GL_A(gl_a), .GH_B(gh_b), .GL_B(gl_b), .GH_C(gh_c), .GL_C(gl_c),
        .RUN(run), .FAULT(fault)
    );

    initial begin
        $dumpfile("output/simulation_artifacts/jagdis_top_smoke_tb.vcd");
        $dumpvars(0, jagdis_top_smoke_tb);
        #35 reset_n = 1'b1;
        // Two PWM periods cover reset release, Hall synchronization, shadow
        // transfer, and boundary-aligned startup.
        #51000;
        if (!run || !gh_a || !gl_b || gl_a || gh_b || gl_c || gh_c) begin
            $display("FAIL: expected A+ B- operation after startup");
            $finish;
        end
        oc_fault = 1'b1;
        #1;
        if (gh_a || gl_a || gh_b || gl_b || gh_c || gl_c) begin
            $display("FAIL: external fault did not asynchronously kill gates");
            $finish;
        end
        #30;
        if (!fault || run) begin
            $display("FAIL: fault did not latch and clear RUN");
            $finish;
        end
        $display("PASS: JAGDIS top-level smoke test");
        $finish;
    end
endmodule

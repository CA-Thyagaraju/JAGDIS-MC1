`timescale 1ns/1ps

module gate_controller #(
    parameter [5:0] DEAD_TIME_CLKS = 6'd25
) (
    input  wire       clk,
    input  wire       reset_n,
    input  wire       run_enable,
    input  wire       brake_active,
    input  wire       pwm_raw,
    input  wire [5:0] phase_cmd,
    output wire       gh_a,
    output wire       gl_a,
    output wire       gh_b,
    output wire       gl_b,
    output wire       gh_c,
    output wire       gl_c
);
    wire allow_drive;
    wire req_ah, req_al, req_bh, req_bl, req_ch, req_cl;

    assign allow_drive = run_enable && !brake_active;
    // High sides use PWM; selected low sides are continuously asserted.
    assign req_ah = allow_drive && phase_cmd[5] && pwm_raw;
    assign req_al = allow_drive && phase_cmd[4];
    assign req_bh = allow_drive && phase_cmd[3] && pwm_raw;
    assign req_bl = allow_drive && phase_cmd[2];
    assign req_ch = allow_drive && phase_cmd[1] && pwm_raw;
    assign req_cl = allow_drive && phase_cmd[0];

    gate_phase #(.DEAD_TIME_CLKS(DEAD_TIME_CLKS)) phase_a (
        .clk(clk), .reset_n(reset_n), .request_high(req_ah), .request_low(req_al),
        .gate_high(gh_a), .gate_low(gl_a)
    );
    gate_phase #(.DEAD_TIME_CLKS(DEAD_TIME_CLKS)) phase_b (
        .clk(clk), .reset_n(reset_n), .request_high(req_bh), .request_low(req_bl),
        .gate_high(gh_b), .gate_low(gl_b)
    );
    gate_phase #(.DEAD_TIME_CLKS(DEAD_TIME_CLKS)) phase_c (
        .clk(clk), .reset_n(reset_n), .request_high(req_ch), .request_low(req_cl),
        .gate_high(gh_c), .gate_low(gl_c)
    );
endmodule

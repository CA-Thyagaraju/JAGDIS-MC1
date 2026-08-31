`timescale 1ns/1ps

module jagdis_top #(
    parameter [10:0] PWM_PERIOD_CLKS = 11'd1250,
    parameter [5:0]  DEAD_TIME_CLKS  = 6'd25
) (
    input  wire       CLK,
    input  wire       RESET_N,
    input  wire       HALL_A,
    input  wire       HALL_B,
    input  wire       HALL_C,
    input  wire [9:0] DUTY,
    input  wire       ENABLE,
    input  wire       DIR,
    input  wire       BRAKE,
    input  wire       OC_FAULT,
    input  wire       UV_FAULT,
    input  wire       OT_FAULT,
    output wire       GH_A,
    output wire       GL_A,
    output wire       GH_B,
    output wire       GL_B,
    output wire       GH_C,
    output wire       GL_C,
    output wire       RUN,
    output wire       FAULT
);
    wire reset_n_sync;
    wire [10:0] pwm_counter;
    wire [9:0] duty_shadow, duty_active;
    wire [10:0] compare_value;
    wire pwm_raw, pwm_boundary;
    wire [2:0] hall_sync;
    wire hall_valid, hall_fault;
    wire [2:0] hall_active;
    wire [5:0] phase_cmd;
    wire run_enable, brake_active, run_internal;
    wire fault_condition, fault_latched;
    wire gh_a_normal, gl_a_normal, gh_b_normal, gl_b_normal, gh_c_normal, gl_c_normal;

    reset_sync reset_conditioner (.clk(CLK), .reset_n(RESET_N), .reset_n_sync(reset_n_sync));

    pwm_generator #(.PWM_PERIOD_CLKS(PWM_PERIOD_CLKS)) pwm (
        .clk(CLK), .reset_n(reset_n_sync), .duty(DUTY), .pwm_counter(pwm_counter),
        .duty_shadow(duty_shadow), .duty_active(duty_active), .compare_value(compare_value),
        .pwm_raw(pwm_raw), .pwm_boundary(pwm_boundary)
    );

    hall_commutation hall (
        .clk(CLK), .reset_n(reset_n_sync), .hall_a(HALL_A), .hall_b(HALL_B), .hall_c(HALL_C),
        .dir(DIR), .pwm_boundary(pwm_boundary), .hall_sync(hall_sync), .hall_valid(hall_valid),
        .hall_active(hall_active), .hall_fault(hall_fault), .phase_cmd(phase_cmd)
    );

    fault_manager faults (
        .clk(CLK), .reset_n(reset_n_sync), .oc_fault(OC_FAULT), .uv_fault(UV_FAULT),
        .ot_fault(OT_FAULT), .hall_fault(hall_fault), .fault_condition(fault_condition),
        .fault_latched(fault_latched)
    );

    control_fsm control (
        .clk(CLK), .reset_n(reset_n_sync), .enable(ENABLE), .brake(BRAKE),
        .hall_valid(hall_valid), .pwm_boundary(pwm_boundary), .fault_condition(fault_condition),
        .fault_latched(fault_latched), .run_enable(run_enable), .brake_active(brake_active),
        .run(run_internal)
    );

    gate_controller #(.DEAD_TIME_CLKS(DEAD_TIME_CLKS)) gates (
        .clk(CLK), .reset_n(reset_n_sync), .run_enable(run_enable), .brake_active(brake_active),
        .pwm_raw(pwm_raw), .phase_cmd(phase_cmd), .gh_a(gh_a_normal), .gl_a(gl_a_normal),
        .gh_b(gh_b_normal), .gl_b(gl_b_normal), .gh_c(gh_c_normal), .gl_c(gl_c_normal)
    );

    // RESET_N and external faults bypass all sequential logic.  hall_fault is
    // synchronous, but after grace it receives the same immediate gate kill.
    assign GH_A = gh_a_normal & RESET_N & ~fault_condition & ~fault_latched;
    assign GL_A = gl_a_normal & RESET_N & ~fault_condition & ~fault_latched;
    assign GH_B = gh_b_normal & RESET_N & ~fault_condition & ~fault_latched;
    assign GL_B = gl_b_normal & RESET_N & ~fault_condition & ~fault_latched;
    assign GH_C = gh_c_normal & RESET_N & ~fault_condition & ~fault_latched;
    assign GL_C = gl_c_normal & RESET_N & ~fault_condition & ~fault_latched;
    assign RUN = run_internal & ~fault_condition;
    assign FAULT = fault_latched;
endmodule

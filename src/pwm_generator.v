`timescale 1ns/1ps

module pwm_generator #(
    parameter [10:0] PWM_PERIOD_CLKS = 11'd1250
) (
    input  wire        clk,
    input  wire        reset_n,
    input  wire [9:0]  duty,
    output reg  [10:0] pwm_counter,
    output reg  [9:0]  duty_shadow,
    output reg  [9:0]  duty_active,
    output reg  [10:0] compare_value,
    output wire        pwm_raw,
    output wire        pwm_boundary
);
    // The product is at most 1,278,750.  The extra bits retain explicit
    // arithmetic sizing across conservative Verilog-2001 elaborators.
    localparam [10:0] PWM_LAST_COUNT = PWM_PERIOD_CLKS - 11'd1;
    reg [21:0] duty_product;
    reg [21:0] compare_quotient;

    assign pwm_boundary = (pwm_counter == PWM_LAST_COUNT);
    assign pwm_raw = (pwm_counter < compare_value);

    always @(*) begin
        duty_product = duty_active * PWM_PERIOD_CLKS;
        compare_quotient = duty_product / 1023;
        compare_value = compare_quotient[10:0];
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            pwm_counter <= 11'd0;
            duty_shadow <= 10'd0;
            duty_active <= 10'd0;
        end else begin
            duty_shadow <= duty;
            if (pwm_boundary) begin
                pwm_counter <= 11'd0;
                duty_active <= duty_shadow;
            end else begin
                pwm_counter <= pwm_counter + 11'd1;
            end
        end
    end
endmodule

`timescale 1ns/1ps

module control_fsm (
    input  wire clk,
    input  wire reset_n,
    input  wire enable,
    input  wire brake,
    input  wire hall_valid,
    input  wire pwm_boundary,
    input  wire fault_condition,
    input  wire fault_latched,
    output reg  run_enable,
    output reg  brake_active,
    output reg  run
);
    localparam [2:0] IDLE    = 3'd0;
    localparam [2:0] STARTUP = 3'd1;
    localparam [2:0] RUN     = 3'd2;
    localparam [2:0] BRAKE   = 3'd3;
    localparam [2:0] FAULT   = 3'd4;

    reg [2:0] state;
    reg [2:0] next_state;

    always @(*) begin
        next_state = state;
        if (fault_condition || fault_latched) begin
            next_state = FAULT;
        end else begin
            case (state)
                IDLE:    if (enable) next_state = STARTUP;
                STARTUP: begin
                    if (!enable) next_state = IDLE;
                    else if (brake) next_state = BRAKE;
                    else if (hall_valid && pwm_boundary) next_state = RUN;
                end
                RUN: begin
                    if (!enable) next_state = IDLE;
                    else if (brake) next_state = BRAKE;
                end
                BRAKE: begin
                    if (!brake) begin
                        if (enable) next_state = STARTUP;
                        else next_state = IDLE;
                    end
                end
                FAULT: next_state = FAULT;
                default: next_state = IDLE;
            endcase
        end
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    always @(*) begin
        run_enable = (state == RUN) && !fault_latched;
        brake_active = (state == BRAKE);
        run = run_enable;
    end
endmodule

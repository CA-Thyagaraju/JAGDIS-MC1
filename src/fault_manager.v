`timescale 1ns/1ps

module fault_manager (
    input  wire clk,
    input  wire reset_n,
    input  wire oc_fault,
    input  wire uv_fault,
    input  wire ot_fault,
    input  wire hall_fault,
    output wire fault_condition,
    output reg  fault_latched
);
    assign fault_condition = oc_fault | uv_fault | ot_fault | hall_fault;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            fault_latched <= 1'b0;
        else if (fault_condition)
            fault_latched <= 1'b1;
    end
endmodule

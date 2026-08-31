`timescale 1ns/1ps

// Per-half-bridge request interlock.  Dead time is introduced only when the
// currently asserted device and requested device are complementary.
module gate_phase #(
    parameter [5:0] DEAD_TIME_CLKS = 6'd25
) (
    input  wire clk,
    input  wire reset_n,
    input  wire request_high,
    input  wire request_low,
    output reg  gate_high,
    output reg  gate_low
);
    reg [5:0] dead_count;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            gate_high <= 1'b0;
            gate_low <= 1'b0;
            dead_count <= 6'd0;
        end else if (dead_count != 6'd0) begin
            gate_high <= 1'b0;
            gate_low <= 1'b0;
            if (dead_count == 6'd1) begin
                dead_count <= 6'd0;
                // Requests are sampled here, giving latest-request-wins
                // behavior while the phase has both switches off.
                gate_high <= request_high & ~request_low;
                gate_low <= request_low & ~request_high;
            end else begin
                dead_count <= dead_count - 6'd1;
            end
        end else if ((gate_high && request_low) ||
                     (gate_low && request_high)) begin
            gate_high <= 1'b0;
            gate_low <= 1'b0;
            dead_count <= DEAD_TIME_CLKS;
        end else begin
            // A high and low request together is never a legal phase command;
            // fail safe by turning this half bridge off.
            gate_high <= request_high & ~request_low;
            gate_low <= request_low & ~request_high;
        end
    end
endmodule

`timescale 1ns/1ps

// Active-low reset conditioner: assertion is asynchronous; deassertion takes
// two CLK edges.  Downstream sequential logic uses reset_n_sync.
module reset_sync (
    input  wire clk,
    input  wire reset_n,
    output wire reset_n_sync
);
    reg [1:0] release_pipe;

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n)
            release_pipe <= 2'b00;
        else
            release_pipe <= {release_pipe[0], 1'b1};
    end

    assign reset_n_sync = release_pipe[1];
endmodule

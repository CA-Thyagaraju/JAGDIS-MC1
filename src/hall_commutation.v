`timescale 1ns/1ps

module hall_commutation (
    input  wire       clk,
    input  wire       reset_n,
    input  wire       hall_a,
    input  wire       hall_b,
    input  wire       hall_c,
    input  wire       dir,
    input  wire       pwm_boundary,
    output wire [2:0] hall_sync,
    output wire       hall_valid,
    output reg  [2:0] hall_active,
    output reg        hall_fault,
    output reg  [5:0] phase_cmd
);
    reg [1:0] hall_a_pipe;
    reg [1:0] hall_b_pipe;
    reg [1:0] hall_c_pipe;
    reg [2:0] hall_previous;
    reg [2:0] hall_pending;
    reg       pending_valid;
    reg       bad_hall_observed;
    reg       grace_used;

    assign hall_sync = {hall_a_pipe[1], hall_b_pipe[1], hall_c_pipe[1]};
    assign hall_valid = (hall_sync == 3'b001) || (hall_sync == 3'b101) ||
                        (hall_sync == 3'b100) || (hall_sync == 3'b110) ||
                        (hall_sync == 3'b010) || (hall_sync == 3'b011);

    function valid_transition;
        input [2:0] from_hall;
        input [2:0] to_hall;
        input       direction;
        begin
            valid_transition = 1'b0;
            if (!direction) begin
                case (from_hall)
                    3'b001: valid_transition = (to_hall == 3'b101);
                    3'b101: valid_transition = (to_hall == 3'b100);
                    3'b100: valid_transition = (to_hall == 3'b110);
                    3'b110: valid_transition = (to_hall == 3'b010);
                    3'b010: valid_transition = (to_hall == 3'b011);
                    3'b011: valid_transition = (to_hall == 3'b001);
                    default: valid_transition = 1'b0;
                endcase
            end else begin
                case (from_hall)
                    3'b001: valid_transition = (to_hall == 3'b011);
                    3'b011: valid_transition = (to_hall == 3'b010);
                    3'b010: valid_transition = (to_hall == 3'b110);
                    3'b110: valid_transition = (to_hall == 3'b100);
                    3'b100: valid_transition = (to_hall == 3'b101);
                    3'b101: valid_transition = (to_hall == 3'b001);
                    default: valid_transition = 1'b0;
                endcase
            end
        end
    endfunction

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            hall_a_pipe <= 2'b00;
            hall_b_pipe <= 2'b00;
            hall_c_pipe <= 2'b00;
        end else begin
            hall_a_pipe <= {hall_a_pipe[0], hall_a};
            hall_b_pipe <= {hall_b_pipe[0], hall_b};
            hall_c_pipe <= {hall_c_pipe[0], hall_c};
        end
    end

    always @(posedge clk or negedge reset_n) begin
        if (!reset_n) begin
            hall_previous <= 3'b000;
            hall_pending <= 3'b000;
            hall_active <= 3'b000;
            pending_valid <= 1'b0;
            bad_hall_observed <= 1'b0;
            grace_used <= 1'b0;
            hall_fault <= 1'b0;
        end else begin
            // Invalid levels are observed continuously so a stable 000/111
            // state is not hidden merely because it did not transition.
            if (!hall_valid)
                bad_hall_observed <= 1'b1;

            if (hall_sync != hall_previous) begin
                hall_previous <= hall_sync;
                if (hall_valid) begin
                    if ((hall_active == 3'b000) ||
                        valid_transition(hall_active, hall_sync, dir)) begin
                        hall_pending <= hall_sync;
                        pending_valid <= 1'b1;
                    end else begin
                        bad_hall_observed <= 1'b1;
                    end
                end
            end

            if (pwm_boundary) begin
                if (pending_valid) begin
                    hall_active <= hall_pending;
                    pending_valid <= 1'b0;
                end
                if (bad_hall_observed) begin
                    if (grace_used)
                        hall_fault <= 1'b1;
                    else
                        grace_used <= 1'b1;
                end else begin
                    grace_used <= 1'b0;
                end
                bad_hall_observed <= 1'b0;
            end
        end
    end

    always @(*) begin
        case (hall_active)
            3'b001: phase_cmd = 6'b100100; // A+ B-
            3'b101: phase_cmd = 6'b100001; // A+ C-
            3'b100: phase_cmd = 6'b001001; // B+ C-
            3'b110: phase_cmd = 6'b011000; // B+ A-
            3'b010: phase_cmd = 6'b010010; // C+ A-
            3'b011: phase_cmd = 6'b000110; // C+ B-
            default: phase_cmd = 6'b000000;
        endcase
    end
endmodule

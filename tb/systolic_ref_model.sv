// Golden reference: structural duplicate of systolic_array (lock-step scoreboard).
`timescale 1ns / 1ps

module systolic_ref_model #(
    parameter int N      = 4,
    parameter int DATA_W = 8,
    parameter int ACC_W  = 32
)(
    input  logic                           clk,
    input  logic                           rst_n,
    input  logic                           valid_in,
    input  logic signed [DATA_W-1:0]       a_in [0:N-1],
    input  logic signed [DATA_W-1:0]       b_in [0:N-1],
    output logic signed [ACC_W-1:0]        sum  [0:N-1][0:N-1]
);

    logic [0:N-1] o_valid_unused;

    systolic_array #(
        .N(N),
        .DATA_W(DATA_W),
        .ACC_W(ACC_W)
    ) u_array (
        .i_clk(clk),
        .i_rst_n(rst_n),
        .i_valid(valid_in),
        .i_a(a_in),
        .i_b(b_in),
        .o_sum(sum),
        .o_valid(o_valid_unused)
    );

endmodule

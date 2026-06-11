// Description: NxN systolic array of MAC PEs with data flow left-to-right (A) and top-to-bottom (B).
// PE(i,j) accumulates a[i]*b[j]: with A/B held constant and i_valid pulsed for k cycles,
// o_sum converges to k * (a outer b) once the diagonal valid wavefront has passed
// (i+j+1 cycles to reach PE(i,j), 2N-1 cycles for the full array).
module systolic_array #(
    parameter int N       = 4,
    parameter int DATA_W  = 8,
    parameter int ACC_W   = 32
)(
    input  logic              i_clk,
    input  logic              i_rst_n,
    input  logic              i_valid,                // Enable computation

    input  logic signed [DATA_W-1:0] i_a [0:N-1],    // A data inputs (one per row, enters at col 0)
    input  logic signed [DATA_W-1:0] i_b [0:N-1],    // B data inputs (one per column, enters at row 0)

    output logic signed [ACC_W-1:0]  o_sum [0:N-1][0:N-1],  // NxN accumulator outputs
    output logic [0:N-1]              o_valid         // Valid signal per row (pipelined)
);

    logic signed [DATA_W-1:0] a_flow [0:N-1][0:N];     // A dataflow: [row][col], left to right
    logic signed [DATA_W-1:0] b_flow [0:N][0:N-1];     // B dataflow: [row][col], top to bottom
    logic                     valid_pipe [0:N-1][0:N-1]; // diagonal valid wavefront

    genvar i, j;
    generate
        for (j = 0; j < N; j++) begin : btop
            assign b_flow[0][j] = i_b[j];
        end

        for (i = 0; i < N; i++) begin : row
            assign a_flow[i][0] = i_a[i];

            for (j = 0; j < N; j++) begin : col
                // Valid reaches PE(i,j) i+j+1 cycles after i_valid: down the
                // first column, then across the row, matching the operand
                // arrival skew (A delayed j hops, B delayed i hops).
                always_ff @(posedge i_clk or negedge i_rst_n)
                    if (!i_rst_n)
                        valid_pipe[i][j] <= 1'b0;
                    else if (j > 0)
                        valid_pipe[i][j] <= valid_pipe[i][j-1];
                    else if (i > 0)
                        valid_pipe[i][j] <= valid_pipe[i-1][0];
                    else
                        valid_pipe[i][j] <= i_valid;

                mac_pe #(
                    .DATA_W(DATA_W),
                    .ACC_W(ACC_W)
                ) pe (
                    .i_clk(i_clk),
                    .i_rst_n(i_rst_n),
                    .i_valid(valid_pipe[i][j]),
                    .i_a(a_flow[i][j]),
                    .i_b(b_flow[i][j]),
                    .o_a(a_flow[i][j+1]),
                    .o_b(b_flow[i+1][j]),
                    .o_sum(o_sum[i][j])
                );
            end

            assign o_valid[i] = valid_pipe[i][N-1];
        end
    endgenerate

endmodule

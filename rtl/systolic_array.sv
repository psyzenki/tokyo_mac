// Description: NxN systolic array of MAC PEs with data flow left-to-right (A) and top-to-bottom (B)
module systolic_array #(
    parameter int N       = 4,
    parameter int DATA_W  = 8,
    parameter int ACC_W   = 32
)(
    input  logic              i_clk,
    input  logic              i_rst_n,
    input  logic              i_valid,                // Enable computation

    input  logic signed [DATA_W-1:0] i_a [0:N-1],    // A data inputs (one per row)
    input  logic signed [DATA_W-1:0] i_b [0:N-1],    // B data inputs (one per column)

    output logic signed [ACC_W-1:0]  o_sum [0:N-1][0:N-1],  // NxN accumulator outputs
    output logic [0:N-1]              o_valid         // Valid signal per row (pipelined)
);

    logic signed [DATA_W-1:0] a_flow [0:N][0:N];     // A dataflow: [row][col]
    logic signed [DATA_W-1:0] b_flow [0:N][0:N];     // B dataflow: [row][col]
    logic [0:N]               valid_flow [0:N];      // Valid at col 0 and after row pipeline
    logic                     valid_row_pipe [0:N-1][0:N-1];

    genvar i, j;
    generate
        for (i = 0; i < N; i++) begin : row
            assign a_flow[i][0] = i_a[i];
            assign b_flow[i][0] = i_b[i];
            if (i == 0)
                assign valid_flow[i][0] = i_valid;
            else
                assign valid_flow[i][0] = valid_flow[i-1][N];

            for (j = 0; j < N; j++) begin : col
                if (j == 0) begin : g_vpipe0
                    always_ff @(posedge i_clk or negedge i_rst_n)
                        if (!i_rst_n)
                            valid_row_pipe[i][0] <= 1'b0;
                        else
                            valid_row_pipe[i][0] <= valid_flow[i][0];
                end else begin : g_vpipe
                    always_ff @(posedge i_clk or negedge i_rst_n)
                        if (!i_rst_n)
                            valid_row_pipe[i][j] <= 1'b0;
                        else
                            valid_row_pipe[i][j] <= valid_row_pipe[i][j-1];
                end
                mac_pe #(
                    .DATA_W(DATA_W),
                    .ACC_W(ACC_W)
                ) pe (
                    .i_clk(i_clk),
                    .i_rst_n(i_rst_n),
                    .i_valid(valid_flow[i][0]),
                    .i_a(a_flow[i][j]),
                    .i_b(b_flow[i][j]),
                    .o_a(a_flow[i][j+1]),
                    .o_b(b_flow[i][j+1]),
                    .o_sum(o_sum[i][j])
                );
            end

            assign valid_flow[i][N] = valid_row_pipe[i][N-1];
            assign o_valid[i]     = valid_flow[i][N];
        end
    endgenerate

endmodule

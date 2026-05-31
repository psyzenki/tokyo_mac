// Module: mac_pe.sv
// Date        Description
// -----------------------------------------------------------------------------
// 2026-05-31  Initial version - Simple MAC PE for INT8 data and INT32 accumulation
// 2026-05-31  Added optimizations to skip MAC when either input is zero and handle
//             multiplication by 1 or -1 efficiently        
// -----------------------------------------------------------------------------
module mac_pe #(
    parameter int DATA_W = 8,
    parameter int ACC_W  = 32
)(
    input  logic              i_clk,
    input  logic              i_rst_n,
    input  logic              i_valid,

    input  logic signed [DATA_W-1:0] i_a,
    input  logic signed [DATA_W-1:0] i_b,

    output logic signed [DATA_W-1:0] o_a,
    output logic signed [DATA_W-1:0] o_b,

    output logic signed [ACC_W-1:0]  o_sum
);

    logic signed [DATA_W-1:0] a_reg;
    logic signed [DATA_W-1:0] b_reg;
    logic signed [ACC_W-1:0]  sum_reg;

    always_ff @(posedge i_clk or negedge i_rst_n)
        if (!i_rst_n) begin
            a_reg   <= '0;
            b_reg   <= '0;
            sum_reg <= '0;
        end
        else begin
            a_reg   <= i_a;
            b_reg   <= i_b;
            if (i_valid)
                if (i_a != 0 && i_b != 0) // skip MAC if either input is zero
                    if (i_a == signed'(DATA_W)'(1)) // same as 8'sd1
                        sum_reg <= sum_reg + i_b; // Optimization for multiplying by 1
                    else if (i_a == signed'(DATA_W)'(-1)) // same as 8'sd-1
                        sum_reg <= sum_reg - i_b; // Optimization for multiplying by -1
                    else if (i_b == signed'(DATA_W)'(1))
                        sum_reg <= sum_reg + i_a; // Optimization for multiplying by 1
                    else if (i_b == signed'(DATA_W)'(-1))
                        sum_reg <= sum_reg - i_a; // Optimization for multiplying by -1
                    else
                        sum_reg <= sum_reg + i_a*i_b;
            else
                sum_reg <= sum_reg; // Hold value if not valid 
        end

    assign o_a   = a_reg;
    assign o_b   = b_reg;
    assign o_sum = sum_reg;

endmodule
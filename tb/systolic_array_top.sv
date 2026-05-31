// Simulation top — array size from compile-time macro N (see Makefile).
`ifndef ARRAY_N
`define ARRAY_N 4
`endif

module systolic_array_top;
    systolic_array_tb #(.N(`ARRAY_N)) u_tb ();
endmodule

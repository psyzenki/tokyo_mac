// Compile-only wrapper: instantiates tokyo_mac_top (use tokyo_mac_sys_tb for protocol tests).
`timescale 1ns / 1ps

module tokyo_mac_top_tb;

    localparam int CLK_PERIOD_NS = 20;

    logic clk, rst_n, uart_rx, uart_tx;

    tokyo_mac_top dut (
        .i_clk(clk),
        .i_rst_n(rst_n),
        .i_uart_rx(uart_rx),
        .o_uart_tx(uart_tx)
    );

    initial clk = 0;
    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    initial begin
        uart_rx = 1'b1;
        rst_n   = 0;
        repeat (4) @(posedge clk);
        rst_n = 1;
        repeat (16) @(posedge clk);
        $display("tokyo_mac_top_tb elaborate OK");
        $finish;
    end

endmodule

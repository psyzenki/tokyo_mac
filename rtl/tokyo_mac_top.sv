// Module: tokyo_mac_top.sv
// Date        Description
// -----------------------------------------------------------------------------
// 2026-05-31  Top: UART host link + uart_host_if + NxN systolic_array.
// -----------------------------------------------------------------------------
module tokyo_mac_top #(
    parameter int N       = 4,
    parameter int DATA_W  = 8,
    parameter int ACC_W   = 32,
    parameter int CLK_HZ  = 50_000_000,
    parameter int BAUD    = 115200
)(
    input  logic i_clk,
    input  logic i_rst_n,

    input  logic i_uart_rx,
    output logic o_uart_tx
);

    logic                  uart_tx_valid;
    logic [7:0]            uart_tx_data;
    logic                  uart_tx_ready;
    logic                  uart_rx_valid;
    logic [7:0]            uart_rx_data;
    logic                  uart_rx_ready;

    logic                  array_valid;
    logic signed [DATA_W-1:0] a_drv [0:N-1];
    logic signed [DATA_W-1:0] b_drv [0:N-1];
    logic signed [ACC_W-1:0]  sum    [0:N-1][0:N-1];
    logic [0:N-1]             array_valid_out;

    uart #(
        .CLK_HZ(CLK_HZ),
        .BAUD(BAUD),
        .DATA_BITS(8)
    ) u_uart (
        .i_clk(i_clk),
        .i_rst_n(i_rst_n),
        .i_rx(i_uart_rx),
        .o_tx(o_uart_tx),
        .i_tx_valid(uart_tx_valid),
        .i_tx_data(uart_tx_data),
        .o_tx_ready(uart_tx_ready),
        .o_rx_valid(uart_rx_valid),
        .o_rx_data(uart_rx_data),
        .i_rx_ready(uart_rx_ready)
    );

    uart_host_if #(
        .N(N),
        .DATA_W(DATA_W),
        .ACC_W(ACC_W)
    ) u_host (
        .i_clk(i_clk),
        .i_rst_n(i_rst_n),
        .o_tx_valid(uart_tx_valid),
        .o_tx_data(uart_tx_data),
        .i_tx_ready(uart_tx_ready),
        .i_rx_valid(uart_rx_valid),
        .i_rx_data(uart_rx_data),
        .o_rx_ready(uart_rx_ready),
        .o_array_valid(array_valid),
        .o_a(a_drv),
        .o_b(b_drv),
        .i_sum(sum)
    );

    systolic_array #(
        .N(N),
        .DATA_W(DATA_W),
        .ACC_W(ACC_W)
    ) u_array (
        .i_clk(i_clk),
        .i_rst_n(i_rst_n),
        .i_valid(array_valid),
        .i_a(a_drv),
        .i_b(b_drv),
        .o_sum(sum),
        .o_valid(array_valid_out)
    );

endmodule

// Smoke test: loopback one byte through TX into RX (wired in tb).
`timescale 1ns / 1ps

module uart_tb;

    localparam int CLK_HZ = 50_000_000;
    localparam int BAUD   = 1_000_000;
    localparam int CLK_PERIOD_NS = 20;

    logic clk, rst_n;
    logic rx, tx;
    logic tx_valid, tx_ready;
    logic [7:0] tx_data;
    logic rx_valid, rx_ready;
    logic [7:0] rx_data;

    uart #(
        .CLK_HZ(CLK_HZ),
        .BAUD(BAUD),
        .DATA_BITS(8)
    ) dut (
        .i_clk(clk),
        .i_rst_n(rst_n),
        .i_rx(rx),
        .o_tx(tx),
        .i_tx_valid(tx_valid),
        .i_tx_data(tx_data),
        .o_tx_ready(tx_ready),
        .o_rx_valid(rx_valid),
        .o_rx_data(rx_data),
        .i_rx_ready(rx_ready)
    );

    assign rx = tx;
    assign rx_ready = 1'b1;

    initial clk = 0;
    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    initial begin
        tx_valid = 0;
        tx_data  = 8'h00;
        rst_n    = 0;
        repeat (8) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        wait (tx_ready);
        tx_data  = 8'hA5;
        tx_valid = 1;
        @(posedge clk);
        tx_valid = 0;

        wait (rx_valid);
        if (rx_data !== 8'hA5)
            $error("loopback expected 8'hA5, got %h", rx_data);
        else
            $display("uart_tb loopback OK");

        repeat (2000) @(posedge clk);
        $finish;
    end

endmodule

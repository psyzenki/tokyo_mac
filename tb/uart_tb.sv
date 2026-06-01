// Loopback test: drive TX bytes and verify RX (rx wired to tx in tb).
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

    int pass_count;
    int fail_count;

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

    task automatic send_and_check(input logic [7:0] exp);
        @(posedge clk);
        tx_data  = exp;
        tx_valid = 1'b1;
        while (tx_ready) @(posedge clk);  // accepted when ready drops
        @(posedge clk);
        tx_valid = 1'b0;
        while (!rx_valid) @(posedge clk);  // RX finishes before TX; don't wait for tx_ready first
        while (!tx_ready) @(posedge clk);
        if (rx_data !== exp) begin
            $error("loopback expected 8'h%02x, got 8'h%02x", exp, rx_data);
            fail_count++;
        end else begin
            $display("uart_tb loopback OK: 8'h%02x", exp);
            pass_count++;
        end
        #100ns;
    endtask

    initial clk = 0;
    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    initial begin
        tx_valid   = 1'b0;
        tx_data    = 8'h00;
        rst_n      = 1'b0;
        pass_count = 0;
        fail_count = 0;

        repeat (8) @(posedge clk);
        rst_n = 1'b1;
        @(posedge clk);
        wait (tx_ready);

        // Classic bit-pattern smoke bytes
        send_and_check(8'hA5);
        send_and_check(8'hFF);
        send_and_check(8'h55);
        send_and_check(8'hAA);
        send_and_check(8'hA5);
        send_and_check(8'h5A);
        send_and_check(8'h0F);
        send_and_check(8'hF0);

        // Walking-one and walking-zero
        for (int i = 0; i < 8; i++)
            send_and_check(8'(1 << i));
        for (int i = 0; i < 8; i++)
            send_and_check(8'(~(1 << i)));

        // Sequential ramp
        for (int i = 0; i < 32; i++)
            send_and_check(8'(i));

        // Alternating bursts (matrix-ish payload samples)
        send_and_check(8'hDE);
        send_and_check(8'hAD);
        send_and_check(8'hBE);
        send_and_check(8'hEF);
        send_and_check(8'hCA);
        send_and_check(8'hFE);
        send_and_check(8'hBA);
        send_and_check(8'hBE);

        repeat (2000) @(posedge clk);

        if (fail_count == 0)
            $display("uart_tb PASSED: %0d bytes loopback OK", pass_count);
        else
            $error("uart_tb FAILED: %0d pass, %0d fail", pass_count, fail_count);

        $finish;
    end

endmodule

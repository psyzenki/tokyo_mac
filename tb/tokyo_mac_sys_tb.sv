// Protocol test for uart_host_if + systolic_array (byte-level host link).
`timescale 1ns / 1ps

module tokyo_mac_sys_tb;

    localparam int N = 4;
    localparam int CLK_PERIOD_NS = 20;

    logic clk, rst_n;
    logic host_tx_valid, host_tx_ready;
    logic [7:0] host_tx_data;
    logic host_rx_valid, host_rx_ready;
    logic [7:0] host_rx_data;
    logic array_valid;
    logic signed [7:0] a_drv [0:N-1];
    logic signed [7:0] b_drv [0:N-1];
    logic signed [31:0] sum [0:N-1][0:N-1];
    logic [0:N-1] array_valid_out;

    initial clk = 0;
    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    uart_host_if #(.N(N)) u_host (
        .i_clk(clk), .i_rst_n(rst_n),
        .o_tx_valid(host_tx_valid), .o_tx_data(host_tx_data), .i_tx_ready(host_tx_ready),
        .i_rx_valid(host_rx_valid), .i_rx_data(host_rx_data), .o_rx_ready(host_rx_ready),
        .o_array_valid(array_valid), .o_a(a_drv), .o_b(b_drv), .i_sum(sum)
    );

    systolic_array #(.N(N)) u_array (
        .i_clk(clk), .i_rst_n(rst_n), .i_valid(array_valid),
        .i_a(a_drv), .i_b(b_drv), .o_sum(sum), .o_valid(array_valid_out)
    );

    assign host_tx_ready = 1'b1;

    task host_push(input logic [7:0] b);
        host_rx_valid = 1'b1;
        host_rx_data  = b;
        @(posedge clk);
        while (!host_rx_ready)
            @(posedge clk);
        host_rx_valid = 1'b0;
        @(posedge clk);
    endtask

    task host_pop(output logic [7:0] b);
        int t;
        t = 0;
        while (!host_tx_valid && t < 5000) begin
            @(posedge clk);
            t = t + 1;
        end
        b = host_tx_data;
        @(posedge clk);
    endtask

    initial begin
        logic [7:0] rsp;
        int i;
        rst_n = 0;
        host_rx_valid = 0;
        repeat (8) @(posedge clk);
        rst_n = 1;
        @(posedge clk);

        host_push(8'h01);
        wait (host_tx_valid);
        host_pop(rsp);
        if (rsp !== 8'h55) $error("PING got %02h", rsp);

        host_push(8'h10);
        for (i = 0; i < N; i = i + 1)
            host_push(8'(i + 1));
        wait (host_tx_valid);
        host_pop(rsp);
        if (rsp !== 8'h00) $error("SET_A ACK got %02h", rsp);

        host_push(8'h11);
        for (i = 0; i < N; i = i + 1)
            host_push(8'(i + 2));
        wait (host_tx_valid);
        host_pop(rsp);

        host_push(8'h12);
        host_push(8'h01);
        wait (host_tx_valid);
        host_pop(rsp);

        repeat (64) @(posedge clk);

        host_push(8'h20);
        host_push(8'h00);
        host_push(8'h00);
        wait (host_tx_valid);
        host_pop(rsp);
        host_pop(rsp);
        host_pop(rsp);
        host_pop(rsp);
        $display("tokyo_mac_sys_tb PE(0,0) LE msb byte = %0d", $signed(rsp));

        $display("tokyo_mac_sys_tb OK");
        $finish;
    end

endmodule

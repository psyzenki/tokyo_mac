// End-to-end test: PC-side UART bit-bang -> tokyo_mac_top (uart + host_if + array).
//
// Test plan
// ---------
//  1. Reset / idle        : o_uart_tx idles high after reset
//  2. PING (0x01)         : reply 0x55
//  3. INFO (0x02)         : reply N, DATA_W, ACC_W
//  4. Bad opcode (0x99)   : reply 0xFF
//  5. SET_A / SET_B       : ACK 0x00; normal, zero, INT8 extreme vectors
//  6. RUN (0x12)          : ACK; count=0->1; multi-cycle run
//  7. GET_SUM (0x20)      : 4-byte LE int32 vs o_sum; bad index -> 0xFF
//  8. GET_ALL (0x21)      : N*N*4 bytes row-major vs o_sum
//  9. Full demo flow      : load A/B, run, read corners
// 10. Accumulation       : second RUN doubles PE(0,0) sum
// 11. UART idle sanity   : serial lines high, no X after tests
`timescale 1ns / 1ps

module tokyo_mac_top_tb;

    localparam int N             = 4;
    localparam int DATA_W        = 8;
    localparam int ACC_W         = 32;
    localparam int CLK_HZ        = 50_000_000;
    localparam int BAUD          = 1_000_000;  // fast sim (FPGA default 115200)
    localparam int BIT_DIV       = CLK_HZ / BAUD;
    localparam int CLK_PERIOD_NS = 20;
    localparam int ALL_BYTES     = N * N * (ACC_W / 8);
    localparam int PIPE_CYCLES   = N * N + 32;

    localparam logic [7:0] OPC_PING    = 8'h01;
    localparam logic [7:0] OPC_INFO    = 8'h02;
    localparam logic [7:0] OPC_SET_A   = 8'h10;
    localparam logic [7:0] OPC_SET_B   = 8'h11;
    localparam logic [7:0] OPC_RUN     = 8'h12;
    localparam logic [7:0] OPC_GET_SUM = 8'h20;
    localparam logic [7:0] OPC_GET_ALL = 8'h21;
    localparam logic [7:0] RSP_PONG    = 8'h55;
    localparam logic [7:0] RSP_ACK     = 8'h00;
    localparam logic [7:0] RSP_ERR     = 8'hff;

    logic clk, rst_n, uart_rx, uart_tx;

    int pass_cnt, fail_cnt;
    int idx_i, idx_r, idx_c;

    logic signed [7:0]  a_vec [0:N-1];
    logic signed [7:0]  b_vec [0:N-1];
    logic signed [31:0] sum_ref, sum_got, sum_first;

    tokyo_mac_top #(
        .N(N),
        .DATA_W(DATA_W),
        .ACC_W(ACC_W),
        .CLK_HZ(CLK_HZ),
        .BAUD(BAUD)
    ) dut (
        .i_clk(clk),
        .i_rst_n(rst_n),
        .i_uart_rx(uart_rx),
        .o_uart_tx(uart_tx)
    );

    initial clk = 0;
    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    // -------------------------------------------------------------------------
    // UART host BFM (8N1)
    // -------------------------------------------------------------------------
    task automatic uart_host_send_byte(input logic [7:0] data);
        int b;
        uart_rx = 1'b0;
        repeat (BIT_DIV) @(posedge clk);
        for (b = 0; b < 8; b++) begin
            uart_rx = data[b];
            repeat (BIT_DIV) @(posedge clk);
        end
        uart_rx = 1'b1;
        repeat (BIT_DIV) @(posedge clk);
    endtask

    task automatic uart_host_recv_byte(output logic [7:0] data);
        int b, guard;
        guard = 0;
        while (uart_tx !== 1'b0) begin
            @(posedge clk);
            if (++guard > BIT_DIV * 40) begin
                $error("uart_host_recv_byte timeout");
                data = 8'hxx;
                return;
            end
        end
        repeat (BIT_DIV / 2) @(posedge clk);
        for (b = 0; b < 8; b++) begin
            repeat (BIT_DIV) @(posedge clk);
            data[b] = uart_tx;
        end
        repeat (BIT_DIV) @(posedge clk);
    endtask

    // -------------------------------------------------------------------------
    // Scoreboard
    // -------------------------------------------------------------------------
    task automatic check_u8(input string tag, input logic [7:0] exp, input logic [7:0] act);
        if (act !== exp) begin
            $error("FAIL [%s] exp=8'h%02x got=8'h%02x", tag, exp, act);
            fail_cnt++;
        end else begin
            $display("PASS [%s]", tag);
            pass_cnt++;
        end
    endtask

    task automatic check_i32(input string tag, input logic signed [31:0] exp,
                             input logic signed [31:0] act);
        if (act !== exp) begin
            $error("FAIL [%s] exp=%0d got=%0d", tag, exp, act);
            fail_cnt++;
        end else begin
            $display("PASS [%s] sum=%0d", tag, act);
            pass_cnt++;
        end
    endtask

    task automatic reset_dut;
        rst_n   = 1'b0;
        uart_rx = 1'b1;
        repeat (8) @(posedge clk);
        rst_n = 1'b1;
        repeat (4) @(posedge clk);
    endtask

    task automatic wait_pipeline;
        repeat (PIPE_CYCLES) @(posedge clk);
    endtask

    function automatic logic signed [31:0] array_sum(input int r, input int c);
        return dut.u_array.o_sum[r][c];
    endfunction

    // -------------------------------------------------------------------------
    // Protocol helpers
    // -------------------------------------------------------------------------
    task automatic host_ping;
        logic [7:0] rsp;
        uart_host_send_byte(OPC_PING);
        uart_host_recv_byte(rsp);
        check_u8("ping", RSP_PONG, rsp);
    endtask

    task automatic host_info;
        logic [7:0] n, dw, aw;
        uart_host_send_byte(OPC_INFO);
        uart_host_recv_byte(n);
        uart_host_recv_byte(dw);
        uart_host_recv_byte(aw);
        check_u8("info_N", N[7:0], n);
        check_u8("info_DATA_W", DATA_W[7:0], dw);
        check_u8("info_ACC_W", ACC_W[7:0], aw);
    endtask

    task automatic host_bad_opcode;
        logic [7:0] rsp;
        uart_host_send_byte(8'h99);
        uart_host_recv_byte(rsp);
        check_u8("bad_opcode", RSP_ERR, rsp);
    endtask

    task automatic host_set_a;
        logic [7:0] rsp;
        uart_host_send_byte(OPC_SET_A);
        for (idx_i = 0; idx_i < N; idx_i = idx_i + 1)
            uart_host_send_byte(a_vec[idx_i][7:0]);
        uart_host_recv_byte(rsp);
        check_u8("set_a_ack", RSP_ACK, rsp);
    endtask

    task automatic host_set_b;
        logic [7:0] rsp;
        uart_host_send_byte(OPC_SET_B);
        for (idx_i = 0; idx_i < N; idx_i = idx_i + 1)
            uart_host_send_byte(b_vec[idx_i][7:0]);
        uart_host_recv_byte(rsp);
        check_u8("set_b_ack", RSP_ACK, rsp);
    endtask

    task automatic host_run(input logic [7:0] count);
        logic [7:0] rsp;
        uart_host_send_byte(OPC_RUN);
        uart_host_send_byte(count);
        uart_host_recv_byte(rsp);
        check_u8($sformatf("run_%0d_ack", count), RSP_ACK, rsp);
    endtask

    task automatic host_get_sum_check(input int r, input int c);
        logic [7:0] b0, b1, b2, b3;
        uart_host_send_byte(OPC_GET_SUM);
        uart_host_send_byte(r[7:0]);
        uart_host_send_byte(c[7:0]);
        sum_ref = array_sum(r, c);
        uart_host_recv_byte(b0);
        uart_host_recv_byte(b1);
        uart_host_recv_byte(b2);
        uart_host_recv_byte(b3);
        sum_got = $signed({b3, b2, b1, b0});
        check_i32($sformatf("get_sum_%0d_%0d", r, c), sum_ref, sum_got);
    endtask

    task automatic host_get_sum_bad(input int r, input int c);
        logic [7:0] rsp;
        uart_host_send_byte(OPC_GET_SUM);
        uart_host_send_byte(r[7:0]);
        uart_host_send_byte(c[7:0]);
        uart_host_recv_byte(rsp);
        check_u8($sformatf("get_sum_bad_%0d_%0d", r, c), RSP_ERR, rsp);
    endtask

    task automatic host_get_all_check;
        logic [7:0] byte_v;
        logic signed [31:0] word;
        int idx;
        idx = 0;
        uart_host_send_byte(OPC_GET_ALL);
        for (idx_r = 0; idx_r < N; idx_r = idx_r + 1) begin
            for (idx_c = 0; idx_c < N; idx_c = idx_c + 1) begin
                word = '0;
                uart_host_recv_byte(byte_v);
                word[7:0] = byte_v;
                uart_host_recv_byte(byte_v);
                word[15:8] = byte_v;
                uart_host_recv_byte(byte_v);
                word[23:16] = byte_v;
                uart_host_recv_byte(byte_v);
                word[31:24] = byte_v;
                check_i32($sformatf("get_all_%0d_%0d", idx_r, idx_c),
                          array_sum(idx_r, idx_c), word);
                idx = idx + 4;
            end
        end
        if (idx !== ALL_BYTES) begin
            $error("FAIL [get_all_len] exp=%0d got=%0d", ALL_BYTES, idx);
            fail_cnt++;
        end
    endtask

    task automatic load_vectors(input int pattern);
        for (idx_i = 0; idx_i < N; idx_i = idx_i + 1)
            case (pattern)
                0: begin a_vec[idx_i] = 8'sd1 + idx_i; b_vec[idx_i] = 8'sd2; end
                1: begin a_vec[idx_i] = 8'sd0;        b_vec[idx_i] = 8'sd0; end
                2: begin a_vec[idx_i] = 8'sd127;      b_vec[idx_i] = 8'sd127; end
                3: begin a_vec[idx_i] = -8'sd128;     b_vec[idx_i] = 8'sd1; end
                4: begin a_vec[idx_i] = 8'sd1;        b_vec[idx_i] = -8'sd128; end
                default: begin
                    a_vec[idx_i] = $signed({1'b0, idx_i, 4'hA} ^ 8'h5A);
                    b_vec[idx_i] = $signed({4'hA, idx_i, 1'b0} ^ 8'hA5);
                end
            endcase
    endtask

    // -------------------------------------------------------------------------
    // Main test sequence
    // -------------------------------------------------------------------------
    initial begin
        pass_cnt = 0;
        fail_cnt = 0;
        $display("=== tokyo_mac_top_tb N=%0d BAUD=%0d ===", N, BAUD);

        // 1. reset / idle
        reset_dut;
        if (uart_tx !== 1'b1) begin
            $error("FAIL [idle_tx] o_uart_tx not high after reset");
            fail_cnt++;
        end else begin
            $display("PASS [idle_tx]");
            pass_cnt++;
        end

        // 2. ping
        host_ping;

        // 3. info
        host_info;

        // 4. bad opcode
        host_bad_opcode;

        // 5-7. normal demo + get_sum corners
        load_vectors(0);
        host_set_a;
        host_set_b;
        host_run(8'd1);
        wait_pipeline;
        host_get_sum_check(0, 0);
        host_get_sum_check(N - 1, N - 1);

        // 8. get_all
        host_get_all_check;

        // 6. run count=0 (protocol: treated as 1)
        reset_dut;
        load_vectors(0);
        host_set_a;
        host_set_b;
        host_run(8'd0);
        wait_pipeline;
        host_get_sum_check(0, 0);

        // 6. multi-cycle run
        reset_dut;
        load_vectors(0);
        host_set_a;
        host_set_b;
        host_run(8'd4);
        wait_pipeline;
        host_get_sum_check(0, 0);

        // 7. bad get_sum index
        host_get_sum_bad(N, 0);
        host_get_sum_bad(0, N);

        // 5. zero vectors (mac_pe skips zero product)
        reset_dut;
        load_vectors(1);
        host_set_a;
        host_set_b;
        host_run(8'd1);
        wait_pipeline;
        host_get_sum_check(0, 0);

        // 5. INT8 extremes
        reset_dut;
        load_vectors(2);
        host_set_a;
        host_set_b;
        host_run(8'd1);
        wait_pipeline;
        host_get_sum_check(0, 0);

        reset_dut;
        load_vectors(3);
        host_set_a;
        host_set_b;
        host_run(8'd1);
        wait_pipeline;
        host_get_sum_check(0, 0);

        reset_dut;
        load_vectors(4);
        host_set_a;
        host_set_b;
        host_run(8'd1);
        wait_pipeline;
        host_get_sum_check(0, 0);

        // 9. full demo + 10. accumulation (run twice)
        reset_dut;
        load_vectors(5);
        host_set_a;
        host_set_b;
        host_run(8'd1);
        wait_pipeline;
        sum_first = array_sum(0, 0);
        host_get_sum_check(0, 0);
        host_run(8'd1);
        wait_pipeline;
        check_i32("accum_2x", sum_first * 2, array_sum(0, 0));
        host_get_sum_check(0, 0);

        // 11. uart idle
        repeat (BIT_DIV * 4) @(posedge clk);
        if (uart_tx !== 1'b1 || uart_rx !== 1'b1) begin
            $error("FAIL [idle_lines_end]");
            fail_cnt++;
        end else begin
            $display("PASS [idle_lines_end]");
            pass_cnt++;
        end

        $display("=== tokyo_mac_top_tb done: %0d passed, %0d failed ===",
                 pass_cnt, fail_cnt);
        if (fail_cnt != 0)
            $display("tokyo_mac_top_tb FAILED");
        else
            $display("tokyo_mac_top_tb PASSED");
        $finish;
    end

endmodule

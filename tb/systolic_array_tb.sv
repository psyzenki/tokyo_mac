// Parametric testbench for systolic_array: input MAC and output MAC (o_sum).
`timescale 1ns / 1ps

module systolic_array_tb #(
    parameter int N      = 4,
    parameter int DATA_W = 8,
    parameter int ACC_W  = 32
);

    localparam int CLK_PERIOD_NS = 10;

    logic clk, rst_n, valid;
    logic signed [DATA_W-1:0] a_in [0:N-1];
    logic signed [DATA_W-1:0] b_in [0:N-1];
    logic signed [DATA_W-1:0] a_vec [0:N-1];
    logic signed [DATA_W-1:0] b_vec [0:N-1];
    logic signed [ACC_W-1:0]  o_sum [0:N-1][0:N-1];
    logic signed [ACC_W-1:0]  ref_sum [0:N-1][0:N-1];
    logic [0:N-1]             o_valid;

    int pass_cnt, fail_cnt;
    int idx_i, idx_j, idx_r, idx_c, idx_pat, idx_b, idx_len, idx_cycles;

    systolic_array #(
        .N(N), .DATA_W(DATA_W), .ACC_W(ACC_W)
    ) dut (
        .i_clk(clk),
        .i_rst_n(rst_n),
        .i_valid(valid),
        .i_a(a_in),
        .i_b(b_in),
        .o_sum(o_sum),
        .o_valid(o_valid)
    );

    systolic_ref_model #(
        .N(N), .DATA_W(DATA_W), .ACC_W(ACC_W)
    ) golden (
        .clk(clk),
        .rst_n(rst_n),
        .valid_in(valid),
        .a_in(a_in),
        .b_in(b_in),
        .sum(ref_sum)
    );

    initial clk = 0;
    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    task reset_dut;
        rst_n = 0;
        valid = 0;
        for (idx_i = 0; idx_i < N; idx_i = idx_i + 1) begin
            a_in[idx_i] = '0;
            b_in[idx_i] = '0;
        end
        repeat (4) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
    endtask

    task apply_inputs(input logic drv_valid);
        valid = drv_valid;
        for (idx_i = 0; idx_i < N; idx_i = idx_i + 1) begin
            a_in[idx_i] = a_vec[idx_i];
            b_in[idx_i] = b_vec[idx_i];
        end
        @(posedge clk);
    endtask

    task check_output_mac(input string tag);
        for (idx_i = 0; idx_i < N; idx_i = idx_i + 1)
            for (idx_j = 0; idx_j < N; idx_j = idx_j + 1)
                if (ref_sum[idx_i][idx_j] !== o_sum[idx_i][idx_j]) begin
                    $error("[%s] PE(%0d,%0d) o_sum exp=%0d got=%0d",
                           tag, idx_i, idx_j, ref_sum[idx_i][idx_j], o_sum[idx_i][idx_j]);
                    fail_cnt = fail_cnt + 1;
                end else
                    pass_cnt = pass_cnt + 1;
    endtask

    // Input MAC at PE(0,0) when row valid is asserted
    task check_input_mac_pe00(input string tag, input logic signed [DATA_W-1:0] ea, eb);
        logic signed [ACC_W-1:0] exp_p, act_p;
        if (dut.row[0].col[0].pe.i_valid === 1'b1) begin
            exp_p = ea * eb;
            act_p = dut.row[0].col[0].pe.i_a * dut.row[0].col[0].pe.i_b;
            if (act_p !== exp_p) begin
                $error("[%s] input MAC PE(0,0) exp=%0d got=%0d", tag, exp_p, act_p);
                fail_cnt = fail_cnt + 1;
            end else
                pass_cnt = pass_cnt + 1;
        end
    endtask

    initial begin
        pass_cnt = 0;
        fail_cnt = 0;
        $display("=== systolic_array_tb N=%0d ===", N);

        // reset
        reset_dut;
        check_output_mac("after_reset");

        // input MAC
        reset_dut;
        for (idx_i = 0; idx_i < N; idx_i = idx_i + 1) begin
            a_vec[idx_i] = 8'sd6;
            b_vec[idx_i] = -8'sd2;
        end
        valid = 1;
        for (idx_i = 0; idx_i < N; idx_i = idx_i + 1) begin
            a_in[idx_i] = a_vec[idx_i];
            b_in[idx_i] = b_vec[idx_i];
        end
        @(posedge clk);
        #0;
        check_input_mac_pe00("input_mac", 8'sd6, -8'sd2);
        valid = 0;
        @(posedge clk);

        // one-hot rows
        reset_dut;
        for (idx_r = 0; idx_r < N; idx_r = idx_r + 1) begin
            for (idx_i = 0; idx_i < N; idx_i = idx_i + 1) begin
                a_vec[idx_i] = (idx_i == idx_r) ? 8'sd3 : 8'sd0;
                b_vec[idx_i] = (idx_i == idx_r) ? 8'sd4 : 8'sd0;
            end
            apply_inputs(1'b1);
            apply_inputs(1'b0);
        end
        for (idx_r = 0; idx_r < N * N + 4; idx_r = idx_r + 1)
            apply_inputs(0);
        check_output_mac("one_hot_rows");

        // uniform stream (1 and 8 cycles)
        for (idx_cycles = 1; idx_cycles <= 8; idx_cycles = idx_cycles * 8) begin
            reset_dut;
            for (idx_i = 0; idx_i < N; idx_i = idx_i + 1) begin
                a_vec[idx_i] = 8'sd1 + idx_i;
                b_vec[idx_i] = 8'sd2;
            end
            for (idx_c = 0; idx_c < idx_cycles; idx_c = idx_c + 1)
                apply_inputs(1'b1);
            for (idx_c = 0; idx_c < N + 4; idx_c = idx_c + 1)
                apply_inputs(0);
            check_output_mac("uniform_stream");
        end

        // checkerboard
        reset_dut;
        for (idx_r = 0; idx_r < N; idx_r = idx_r + 1) begin
            for (idx_c = 0; idx_c < N; idx_c = idx_c + 1) begin
                for (idx_i = 0; idx_i < N; idx_i = idx_i + 1) begin
                    a_vec[idx_i] = ((idx_i + idx_r) % 2) ? 8'sd5 : -8'sd3;
                    b_vec[idx_i] = ((idx_i + idx_c) % 2) ? 8'sd2 : 8'sd7;
                end
                apply_inputs(1'b1);
            end
        end
        for (idx_r = 0; idx_r < N * 2 + 4; idx_r = idx_r + 1)
            apply_inputs(0);
        check_output_mac("checkerboard");

        // edge extremes
        reset_dut;
        for (idx_pat = 0; idx_pat < 4; idx_pat = idx_pat + 1) begin
            for (idx_i = 0; idx_i < N; idx_i = idx_i + 1) begin
                case (idx_pat)
                    0: begin a_vec[idx_i] = 8'sd127;   b_vec[idx_i] = 8'sd127;   end
                    1: begin a_vec[idx_i] = -8'sd128;  b_vec[idx_i] = 8'sd1;     end
                    2: begin a_vec[idx_i] = 8'sd1;     b_vec[idx_i] = -8'sd128;  end
                    3: begin a_vec[idx_i] = -8'sd128; b_vec[idx_i] = -8'sd128;  end
                endcase
            end
            apply_inputs(1'b1);
        end
        for (idx_r = 0; idx_r < N + 6; idx_r = idx_r + 1)
            apply_inputs(0);
        check_output_mac("edge_extremes");

        // random bursts (deterministic LFSR — no $srandom in Icarus)
        reset_dut;
        for (idx_b = 0; idx_b < 12; idx_b = idx_b + 1) begin
            idx_len = (idx_b % 8) + 1;
            for (idx_c = 0; idx_c < idx_len; idx_c = idx_c + 1) begin
                for (idx_i = 0; idx_i < N; idx_i = idx_i + 1) begin
                    a_vec[idx_i] = $signed({1'b0, idx_b, idx_c, idx_i} ^ 8'h5A);
                    b_vec[idx_i] = $signed({idx_i, idx_c, idx_b, 1'b0} ^ 8'hA5);
                end
                apply_inputs(1'b1);
            end
            for (idx_i = 0; idx_i < N; idx_i = idx_i + 1) begin
                a_vec[idx_i] = 0;
                b_vec[idx_i] = 0;
            end
            apply_inputs(0);
        end
        for (idx_r = 0; idx_r < N * N + 8; idx_r = idx_r + 1)
            apply_inputs(0);
        check_output_mac("random_burst");

        $display("=== systolic_array_tb N=%0d done: %0d passed, %0d failed ===",
                 N, pass_cnt, fail_cnt);
        if (fail_cnt != 0)
            $display("systolic_array_tb FAILED");
        $finish;
    end

endmodule

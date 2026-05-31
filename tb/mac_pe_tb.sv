// Unit testbench for mac_pe (input MAC + registered output sum).
`timescale 1ns / 1ps

module mac_pe_tb;

    localparam int DATA_W = 8;
    localparam int ACC_W  = 32;
    localparam int CLK_PERIOD_NS = 10;

    logic clk, rst_n, valid;
    logic signed [DATA_W-1:0] a, b;
    logic signed [DATA_W-1:0] o_a, o_b;
    logic signed [ACC_W-1:0]  o_sum;

    int pass_cnt, fail_cnt;

    mac_pe #(.DATA_W(DATA_W), .ACC_W(ACC_W)) dut (
        .i_clk(clk),
        .i_rst_n(rst_n),
        .i_valid(valid),
        .i_a(a),
        .i_b(b),
        .o_a(o_a),
        .o_b(o_b),
        .o_sum(o_sum)
    );

    initial clk = 0;
    always #(CLK_PERIOD_NS / 2) clk = ~clk;

    task reset_dut();
        rst_n = 0;
        valid = 0;
        a     = 0;
        b     = 0;
        repeat (3) @(posedge clk);
        rst_n = 1;
        @(posedge clk);
    endtask

    task check_eq(
        input string name,
        input logic signed [ACC_W-1:0] exp,
        input logic signed [ACC_W-1:0] act
    );
        if (exp !== act) begin
            $error("[%s] expected %0d, got %0d", name, exp, act);
            fail_cnt++;
        end else
            pass_cnt++;
    endtask

    task pulse_mac(input logic signed [DATA_W-1:0] ai, bi);
        a = ai;
        b = bi;
        valid = 1;
        @(posedge clk);
        valid = 0;
        @(posedge clk);
    endtask

    // --- tests ---

    task test_single_mac();
        logic signed [ACC_W-1:0] golden;
        reset_dut();
        golden = 0;
        pulse_mac(8'd3, -8'd4);
        golden += 3 * (-4);
        check_eq("single_mac o_sum", golden, o_sum);
        check_eq("o_a delayed", 8'd3, o_a);
        check_eq("o_b delayed", -8'd4, o_b);
    endtask

    task test_accumulate();
        logic signed [ACC_W-1:0] golden;
        int k;
        reset_dut();
        golden = 0;
        for (k = 0; k < 5; k++) begin
            pulse_mac(8'd2, 8'd3);
            golden += 2 * 3;
            check_eq("accum", golden, o_sum);
        end
    endtask

    task test_valid_gating();
        reset_dut();
        a = 8'd10;
        b = 8'd10;
        valid = 0;
        repeat (4) @(posedge clk);
        check_eq("valid=0 no accumulate", 0, o_sum);
        pulse_mac(8'd1, 8'd1);
        check_eq("valid=1 accumulate", 1, o_sum);
    endtask

    task test_edge_values();
        logic signed [DATA_W-1:0] a_tab [4];
        logic signed [DATA_W-1:0] b_tab [4];
        logic signed [ACC_W-1:0] golden;
        int i;
        reset_dut();
        a_tab[0] = 8'sd127;   b_tab[0] = 8'sd127;
        a_tab[1] = 8'sd127;   b_tab[1] = -8'sd1;
        a_tab[2] = -8'sd128;  b_tab[2] = 8'sd1;
        a_tab[3] = -8'sd128;  b_tab[3] = -8'sd128;
        golden = 0;
        for (i = 0; i < 4; i++) begin
            pulse_mac(a_tab[i], b_tab[i]);
            golden += a_tab[i] * b_tab[i];
            check_eq("edge", golden, o_sum);
        end
    endtask

    initial begin
        $display("=== mac_pe_tb ===");
        pass_cnt = 0;
        fail_cnt = 0;
        test_single_mac();
        test_accumulate();
        test_valid_gating();
        test_edge_values();
        $display("=== mac_pe_tb done: %0d passed, %0d failed ===", pass_cnt, fail_cnt);
        if (fail_cnt != 0)
            $display("mac_pe_tb FAILED");
        $finish;
    end

endmodule

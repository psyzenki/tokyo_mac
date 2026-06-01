// Module: uart_host_if.sv
// Date        Description
// -----------------------------------------------------------------------------
// 2026-05-31  UART byte protocol: load A/B vectors, pulse valid, read o_sum.
//             Opcodes: 0x01 PING, 0x02 INFO, 0x10 SET_A, 0x11 SET_B, 0x12 RUN,
//                      0x20 GET_SUM (row,col), 0x21 GET_ALL (see README).
// -----------------------------------------------------------------------------
module uart_host_if #(
    parameter int N       = 4,
    parameter int DATA_W  = 8,
    parameter int ACC_W   = 32
)(
    input  logic                     i_clk,
    input  logic                     i_rst_n,

    output logic                     o_tx_valid,
    output logic [7:0]               o_tx_data,
    input  logic                     i_tx_ready,

    input  logic                     i_rx_valid,
    input  logic [7:0]               i_rx_data,
    output logic                     o_rx_ready,

    output logic                     o_array_valid,
    output logic signed [DATA_W-1:0] o_a [0:N-1],
    output logic signed [DATA_W-1:0] o_b [0:N-1],

    input  logic signed [ACC_W-1:0]  i_sum [0:N-1][0:N-1]
);

    localparam logic [7:0] OPC_PING    = 8'h01;
    localparam logic [7:0] OPC_INFO    = 8'h02;
    localparam logic [7:0] OPC_SET_A     = 8'h10;
    localparam logic [7:0] OPC_SET_B     = 8'h11;
    localparam logic [7:0] OPC_RUN       = 8'h12;
    localparam logic [7:0] OPC_GET_SUM   = 8'h20;
    localparam logic [7:0] OPC_GET_ALL   = 8'h21;

    localparam logic [7:0] RSP_PONG = 8'h55;
    localparam logic [7:0] RSP_ACK  = 8'h00;
    localparam logic [7:0] RSP_ERR  = 8'hff;

    localparam int IDX_W     = (N <= 1) ? 1 : $clog2(N);
    localparam int ALL_BYTES = N * N * (ACC_W / 8);

    typedef enum logic [2:0] {
        CMD_IDLE,
        CMD_RECV_PAYLOAD,
        CMD_RECV_RUN_CNT,
        CMD_RECV_ROW,
        CMD_RECV_COL,
        CMD_TX
    } cmd_state_t;

    cmd_state_t cmd_state;

    logic [7:0]               opc_reg;
    logic [7:0]               tx_opc;
    logic [IDX_W-1:0]         idx_reg;
    logic [IDX_W-1:0]         row_reg;
    logic [IDX_W-1:0]         col_reg;
    logic [7:0]               run_remain;
    logic signed [DATA_W-1:0] a_hold [0:N-1];
    logic signed [DATA_W-1:0] b_hold [0:N-1];

    logic [3:0]               tx_phase;
    logic [15:0]              tx_all_idx;
    logic signed [ACC_W-1:0]  tx_sum_word;
    logic                     tx_err;

    logic [7:0]               tx_byte_next;
    logic                     tx_done;
    logic [15:0]              all_elem_idx;
    logic [IDX_W-1:0]         all_r;
    logic [IDX_W-1:0]         all_c;
    logic [1:0]               all_bsel;
    logic signed [ACC_W-1:0]  all_word;

    integer ri;

    assign o_a = a_hold;
    assign o_b = b_hold;
    assign o_array_valid = (run_remain != 8'd0);

    always_comb begin
        all_elem_idx = tx_all_idx >> 2;
        all_bsel     = tx_all_idx[1:0];
        all_r        = all_elem_idx / N;
        all_c        = all_elem_idx % N;
        if (all_elem_idx >= N * N)
            all_word = '0;
        else
            all_word = i_sum[all_r][all_c];

        tx_byte_next = 8'h00;
        tx_done      = 1'b1;
        case (tx_opc)
            OPC_PING: begin
                tx_byte_next = RSP_PONG;
                tx_done      = 1'b1;
            end
            OPC_INFO: begin
                case (tx_phase)
                    4'd0: tx_byte_next = N[7:0];
                    4'd1: tx_byte_next = DATA_W[7:0];
                    default: tx_byte_next = ACC_W[7:0];
                endcase
                tx_done = (tx_phase == 4'd2);
            end
            OPC_SET_A,
            OPC_SET_B,
            OPC_RUN: begin
                tx_byte_next = tx_err ? RSP_ERR : RSP_ACK;
                tx_done      = 1'b1;
            end
            OPC_GET_SUM: begin
                if (tx_err) begin
                    tx_byte_next = RSP_ERR;
                    tx_done      = 1'b1;
                end else begin
                    case (tx_phase)
                        4'd0: tx_byte_next = tx_sum_word[7:0];
                        4'd1: tx_byte_next = tx_sum_word[15:8];
                        4'd2: tx_byte_next = tx_sum_word[23:16];
                        default: tx_byte_next = tx_sum_word[31:24];
                    endcase
                    tx_done = (tx_phase == 4'd3);
                end
            end
            OPC_GET_ALL: begin
                case (all_bsel)
                    2'd0: tx_byte_next = all_word[7:0];
                    2'd1: tx_byte_next = all_word[15:8];
                    2'd2: tx_byte_next = all_word[23:16];
                    default: tx_byte_next = all_word[31:24];
                endcase
                tx_done = (tx_all_idx == ALL_BYTES - 1);
            end
            default: begin
                tx_byte_next = RSP_ERR;
                tx_done      = 1'b1;
            end
        endcase
    end

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            cmd_state   <= CMD_IDLE;
            opc_reg     <= 8'h00;
            tx_opc      <= 8'h00;
            idx_reg     <= '0;
            row_reg     <= '0;
            col_reg     <= '0;
            run_remain  <= 8'd0;
            tx_phase    <= 4'd0;
            tx_all_idx  <= 16'd0;
            tx_sum_word <= '0;
            tx_err      <= 1'b0;
            o_tx_valid  <= 1'b0;
            o_tx_data   <= 8'h00;
            o_rx_ready  <= 1'b1;
            for (ri = 0; ri < N; ri = ri + 1) begin
                a_hold[ri] <= '0;
                b_hold[ri] <= '0;
            end
        end else begin
            if (run_remain != 8'd0)
                run_remain <= run_remain - 8'd1;

            if (o_tx_valid && i_tx_ready)
                o_tx_valid <= 1'b0;

            case (cmd_state)
                CMD_IDLE: begin
                    o_rx_ready <= 1'b1;
                    if (i_rx_valid && o_rx_ready) begin
                        opc_reg <= i_rx_data;
                        tx_err  <= 1'b0;
                        case (i_rx_data)
                            OPC_PING, OPC_INFO, OPC_GET_ALL: begin
                                tx_opc    <= i_rx_data;
                                tx_phase  <= 4'd0;
                                tx_all_idx <= 16'd0;
                                cmd_state <= CMD_TX;
                            end
                            OPC_SET_A, OPC_SET_B: begin
                                tx_opc    <= i_rx_data;
                                idx_reg   <= '0;
                                cmd_state <= CMD_RECV_PAYLOAD;
                            end
                            OPC_RUN: begin
                                tx_opc    <= OPC_RUN;
                                cmd_state <= CMD_RECV_RUN_CNT;
                            end
                            OPC_GET_SUM: begin
                                tx_opc    <= OPC_GET_SUM;
                                cmd_state <= CMD_RECV_ROW;
                            end
                            default: begin
                                tx_opc    <= 8'h00;
                                tx_err    <= 1'b1;
                                cmd_state <= CMD_TX;
                            end
                        endcase
                    end
                end

                CMD_RECV_PAYLOAD: begin
                    o_rx_ready <= 1'b1;
                    if (i_rx_valid && o_rx_ready) begin
                        if (opc_reg == OPC_SET_A)
                            a_hold[idx_reg] <= $signed(i_rx_data);
                        else
                            b_hold[idx_reg] <= $signed(i_rx_data);
                        if (idx_reg == IDX_W'(N - 1)) begin
                            tx_opc    <= opc_reg;
                            tx_phase  <= 4'd0;
                            cmd_state <= CMD_TX;
                        end else
                            idx_reg <= idx_reg + 1'b1;
                    end
                end

                CMD_RECV_RUN_CNT: begin
                    o_rx_ready <= 1'b1;
                    if (i_rx_valid && o_rx_ready) begin
                        run_remain <= (i_rx_data == 8'd0) ? 8'd1 : i_rx_data;
                        tx_opc     <= OPC_RUN;
                        tx_phase   <= 4'd0;
                        cmd_state  <= CMD_TX;
                    end
                end

                CMD_RECV_ROW: begin
                    o_rx_ready <= 1'b1;
                    if (i_rx_valid && o_rx_ready) begin
                        row_reg   <= i_rx_data[IDX_W-1:0];
                        cmd_state <= CMD_RECV_COL;
                    end
                end

                CMD_RECV_COL: begin
                    o_rx_ready <= 1'b1;
                    if (i_rx_valid && o_rx_ready) begin
                        col_reg <= i_rx_data[IDX_W-1:0];
                        tx_opc  <= OPC_GET_SUM;
                        tx_phase <= 4'd0;
                        if (row_reg < IDX_W'(N) && i_rx_data[IDX_W-1:0] < IDX_W'(N)) begin
                            tx_err      <= 1'b0;
                            tx_sum_word <= i_sum[row_reg][i_rx_data[IDX_W-1:0]];
                        end else
                            tx_err <= 1'b1;
                        cmd_state <= CMD_TX;
                    end
                end

                CMD_TX: begin
                    o_rx_ready <= 1'b0;
                    if (!o_tx_valid && i_tx_ready) begin
                        o_tx_data  <= tx_byte_next;
                        o_tx_valid <= 1'b1;
                        if (tx_done)
                            cmd_state <= CMD_IDLE;
                        else if (tx_opc == OPC_GET_ALL)
                            tx_all_idx <= tx_all_idx + 16'd1;
                        else
                            tx_phase <= tx_phase + 4'd1;
                    end
                end

                default: cmd_state <= CMD_IDLE;
            endcase
        end
    end

endmodule

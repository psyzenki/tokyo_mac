// Module: uart.sv
// Date        Description
// -----------------------------------------------------------------------------
// 2026-05-31  Async UART (8N1) with byte-stream TX/RX for host terminal link.
//             Intended for loading matrix data / valid controls and reading results.
// -----------------------------------------------------------------------------
module uart #(
    parameter int CLK_HZ    = 50_000_000,
    parameter int BAUD      = 115200,
    parameter int DATA_BITS = 8
)(
    input  logic                  i_clk,
    input  logic                  i_rst_n,

    input  logic                  i_rx,
    output logic                  o_tx,

    input  logic                  i_tx_valid,
    input  logic [DATA_BITS-1:0]  i_tx_data,
    output logic                  o_tx_ready,

    output logic                  o_rx_valid,
    output logic [DATA_BITS-1:0]  o_rx_data,
    input  logic                  i_rx_ready
);

    localparam int BIT_DIV   = CLK_HZ / BAUD;
    localparam int BIT_CNT_W = (BIT_DIV <= 1) ? 1 : $clog2(BIT_DIV);

    typedef enum logic [1:0] {
        ST_IDLE  = 2'd0,
        ST_START = 2'd1,
        ST_DATA  = 2'd2,
        ST_STOP  = 2'd3
    } uart_state_t;

    // -------------------------------------------------------------------------
    // RX: synchronize line, oversample start, sample data near bit center
    // -------------------------------------------------------------------------
    logic       rx_sync_q_reg;
    logic       rx_line_reg;
    uart_state_t rx_state;
    logic [BIT_CNT_W-1:0] rx_bit_cnt;
    logic [3:0]           rx_bit_idx_reg;
    logic [DATA_BITS-1:0] rx_shift_reg;
    logic [DATA_BITS-1:0] rx_hold_reg;
    logic                 rx_hold_valid_reg;

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            rx_sync_q_reg <= 1'b1;
            rx_line_reg   <= 1'b1;
        end else begin
            rx_sync_q_reg <= i_rx;
            rx_line_reg   <= rx_sync_q_reg;
        end
    end

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            rx_state          <= ST_IDLE;
            rx_bit_cnt        <= '0;
            rx_bit_idx_reg    <= '0;
            rx_shift_reg      <= '0;
            rx_hold_reg       <= '0;
            rx_hold_valid_reg <= 1'b0;
        end else begin
            if (o_rx_valid && i_rx_ready)
                rx_hold_valid_reg <= 1'b0;

            unique case (rx_state)
                ST_IDLE: begin
                    rx_bit_cnt <= '0;
                    if (rx_line_reg == 1'b0) begin
                        rx_state   <= ST_START;
                        rx_bit_cnt <= BIT_CNT_W'((BIT_DIV / 2) - 1);
                    end
                end

                ST_START: begin
                    if (rx_bit_cnt == '0) begin
                        if (rx_line_reg == 1'b0) begin
                            rx_state   <= ST_DATA;
                            rx_bit_idx_reg <= '0;
                            rx_bit_cnt <= BIT_CNT_W'(BIT_DIV - 1);
                        end else
                            rx_state <= ST_IDLE;
                    end else
                        rx_bit_cnt <= rx_bit_cnt - 1'b1;
                end

                ST_DATA: begin
                    if (rx_bit_cnt == '0) begin
                        rx_shift_reg[rx_bit_idx_reg] <= rx_line_reg;
                        if (rx_bit_idx_reg == DATA_BITS - 1) begin
                            rx_state   <= ST_STOP;
                            rx_bit_cnt <= BIT_CNT_W'(BIT_DIV - 1);
                        end else begin
                            rx_bit_idx_reg <= rx_bit_idx_reg + 1'b1;
                            rx_bit_cnt <= BIT_CNT_W'(BIT_DIV - 1);
                        end
                    end else
                        rx_bit_cnt <= rx_bit_cnt - 1'b1;
                end

                ST_STOP: begin
                    if (rx_bit_cnt == '0) begin
                        if (rx_line_reg == 1'b1) begin
                            if (!rx_hold_valid_reg) begin
                                rx_hold_reg       <= rx_shift_reg;
                                rx_hold_valid_reg <= 1'b1;
                            end
                        end
                        rx_state <= ST_IDLE;
                    end else
                        rx_bit_cnt <= rx_bit_cnt - 1'b1;
                end

                default: rx_state <= ST_IDLE;
            endcase
        end
    end

    assign o_rx_valid = rx_hold_valid_reg;
    assign o_rx_data  = rx_hold_reg;

    // -------------------------------------------------------------------------
    // TX: idle high; shift start (0), data LSB-first, stop (1)
    // -------------------------------------------------------------------------
    logic       tx_line_reg;
    uart_state_t tx_state;
    logic [BIT_CNT_W-1:0] tx_bit_cnt;
    logic [3:0]           tx_bit_idx_reg;
    logic [DATA_BITS-1:0] tx_shift_reg;
    logic                 tx_busy_reg;

    assign o_tx_ready = !tx_busy_reg;
    assign o_tx       = tx_line_reg;

    always_ff @(posedge i_clk or negedge i_rst_n) begin
        if (!i_rst_n) begin
            tx_line_reg    <= 1'b1;
            tx_state       <= ST_IDLE;
            tx_bit_cnt     <= '0;
            tx_bit_idx_reg <= '0;
            tx_shift_reg   <= '0;
            tx_busy_reg    <= 1'b0;
        end else begin
            unique case (tx_state)
                ST_IDLE: begin
                    if (i_tx_valid && !tx_busy_reg) begin
                        tx_shift_reg   <= i_tx_data;
                        tx_busy_reg    <= 1'b1;
                        tx_state       <= ST_START;
                        tx_bit_cnt     <= BIT_CNT_W'(BIT_DIV - 1);
                    end else
                        tx_line_reg <= 1'b1;
                end

                ST_START: begin
                    tx_line_reg <= 1'b0;
                    if (tx_bit_cnt == '0) begin
                        tx_state       <= ST_DATA;
                        tx_bit_idx_reg <= '0;
                        tx_line_reg    <= tx_shift_reg[0];
                        tx_bit_cnt     <= BIT_CNT_W'(BIT_DIV - 1);
                    end else
                        tx_bit_cnt <= tx_bit_cnt - 1'b1;
                end

                ST_DATA: begin
                    if (tx_bit_cnt == '0) begin
                        if (tx_bit_idx_reg == DATA_BITS - 1) begin
                            tx_state       <= ST_STOP;
                            tx_line_reg    <= 1'b1;
                            tx_bit_cnt     <= BIT_CNT_W'(BIT_DIV - 1);
                        end else begin
                            tx_bit_idx_reg <= tx_bit_idx_reg + 1'b1;
                            tx_line_reg    <= tx_shift_reg[tx_bit_idx_reg + 1'b1];
                            tx_bit_cnt     <= BIT_CNT_W'(BIT_DIV - 1);
                        end
                    end else
                        tx_bit_cnt <= tx_bit_cnt - 1'b1;
                end

                ST_STOP: begin
                    tx_line_reg <= 1'b1;
                    if (tx_bit_cnt == '0) begin
                        tx_busy_reg  <= 1'b0;
                        tx_state     <= ST_IDLE;
                    end else
                        tx_bit_cnt   <= tx_bit_cnt - 1'b1;
                end

                default: tx_state <= ST_IDLE;
            endcase
        end
    end

endmodule

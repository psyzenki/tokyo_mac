// Module : cmod_a7_top
// Description : Cmod A7 board wrapper: 12 MHz clock, BTN0 reset, FTDI USB-UART to tokyo_mac_top.
module cmod_a7_top #(
  parameter N      = 4,
  parameter DATA_W = 8,
  parameter ACC_W  = 32,
  parameter CLK_HZ = 12_000_000,
  parameter BAUD   = 115200
)(
  input  logic i_clk,      // 12 MHz board oscillator (L17)
  input  logic i_btn0,     // BTN0, active high (A18) - resets core and accumulators
  input  logic i_uart_rx,  // FTDI uart_txd_in (J17)
  output logic o_uart_tx,  // FTDI uart_rxd_out (J18)
  output logic o_led0      // LED0 heartbeat (A17)
);

  localparam HEARTBEAT_W = 24; // MSB toggles ~0.7 Hz at 12 MHz

  logic [1:0]             rst_sync_reg;
  logic                   rst_n;
  logic [HEARTBEAT_W-1:0] heartbeat_cnt;
  logic                   uart_tx;

  // Async assert on button press, synchronous release; GSR powers up in reset.
  always_ff @(posedge i_clk or posedge i_btn0)
  begin
    if (i_btn0)
    begin
      rst_sync_reg <= 2'b00;
    end
    else
    begin
      rst_sync_reg <= {rst_sync_reg[0], 1'b1};
    end
  end

  assign rst_n = rst_sync_reg[1];

  always_ff @(posedge i_clk or negedge rst_n)
  begin
    if (!rst_n)
    begin
      heartbeat_cnt <= '0;
    end
    else
    begin
      heartbeat_cnt <= heartbeat_cnt + 1'b1;
    end
  end

  tokyo_mac_top #(
    .N      (N),
    .DATA_W (DATA_W),
    .ACC_W  (ACC_W),
    .CLK_HZ (CLK_HZ),
    .BAUD   (BAUD)
  ) u_core (
    .i_clk     (i_clk),
    .i_rst_n   (rst_n),
    .i_uart_rx (i_uart_rx),
    .o_uart_tx (uart_tx)
  );

  assign o_uart_tx = uart_tx;
  assign o_led0    = heartbeat_cnt[HEARTBEAT_W-1];

endmodule

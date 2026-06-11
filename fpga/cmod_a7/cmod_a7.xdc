# Digilent Cmod A7 constraints for cmod_a7_top (pin names per Cmod-A7-Master.xdc)

## 12 MHz system clock
set_property -dict { PACKAGE_PIN L17 IOSTANDARD LVCMOS33 } [get_ports i_clk]
create_clock -name sys_clk -period 83.333 [get_ports i_clk]

## BTN0 (active high) -> reset
set_property -dict { PACKAGE_PIN A18 IOSTANDARD LVCMOS33 } [get_ports i_btn0]

## LED0 heartbeat
set_property -dict { PACKAGE_PIN A17 IOSTANDARD LVCMOS33 } [get_ports o_led0]

## On-board FTDI FT2232HQ USB-UART
## J17 = uart_txd_in  (host TX -> FPGA RX)
## J18 = uart_rxd_out (FPGA TX -> host RX)
set_property -dict { PACKAGE_PIN J17 IOSTANDARD LVCMOS33 } [get_ports i_uart_rx]
set_property -dict { PACKAGE_PIN J18 IOSTANDARD LVCMOS33 } [get_ports o_uart_tx]

## Asynchronous I/O - no timing relationship to sys_clk
set_false_path -from [get_ports i_uart_rx]
set_false_path -to   [get_ports o_uart_tx]
set_false_path -from [get_ports i_btn0]
set_false_path -to   [get_ports o_led0]

## Configuration
set_property CFGBVS VCCO [current_design]
set_property CONFIG_VOLTAGE 3.3 [current_design]
set_property BITSTREAM.GENERAL.COMPRESS TRUE [current_design]

## QSPI flash boot (MX25L3233F): x4 data width, 33 MHz config clock
set_property BITSTREAM.CONFIG.SPI_BUSWIDTH 4 [current_design]
set_property BITSTREAM.CONFIG.CONFIGRATE 33 [current_design]

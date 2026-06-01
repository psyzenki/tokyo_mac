# tokyo_mac

SystemVerilog MAC processing element, N×N systolic array, and UART for host communication.

## Simulation

Requires [Icarus Verilog](http://iverilog.icarus.com/).

```bash
make test          # mac_pe + uart + systolic array at N=2,3,4,8
make test-pe       # mac_pe only
make test-uart     # uart loopback smoke test
make test-top      # full top: UART serial + host protocol + array readback
make test-array    # systolic array only (all default sizes)
ARRAY_SIZES="2 4 16" make test-array   # custom sizes
```

## Testbenches

| File | Purpose |
|------|---------|
| `tb/mac_pe_tb.sv` | Unit tests: single MAC, accumulation, valid gating, INT8 extremes | VERFIFED OK
| `tb/systolic_array_tb.sv` | Array tests: input MAC at PE(0,0), output MAC (`o_sum`) vs golden model, one-hot rows, uniform streams, checkerboard, random bursts, edge values | VERIFIED OK
| `tb/systolic_ref_model.sv` | Structural golden (second `systolic_array` instance for scoreboarding) |
| `tb/tokyo_mac_top_tb.sv` | End-to-end top: UART BFM + full host protocol + array readback |
| `tb/tokyo_mac_sys_tb.sv` | Fast byte-level protocol test (bypasses UART) |
| `tb/uart_tb.sv` | UART TX→RX loopback smoke test |

Compile-time array size: `-DARRAY_N=<N>` via `tb/systolic_array_top.sv`.

## UART (`rtl/uart.sv`)

8N1 async serial at `BAUD` (default 115200) with `CLK_HZ` (default 50 MHz). Byte-stream ports:

| Port | Direction | Role |
|------|-----------|------|
| `i_tx_valid` / `i_tx_data` / `o_tx_ready` | Host → FPGA | Transmit byte to PC (FPGA drives `o_tx`) |
| `o_rx_valid` / `o_rx_data` / `i_rx_ready` | FPGA ← Host | Received byte from PC (`i_rx`) |

## Top (`rtl/tokyo_mac_top.sv`)

Connects `uart` → `uart_host_if` → `systolic_array`. Pins: `i_clk`, `i_rst_n`, `i_uart_rx`, `o_uart_tx`.

### Host protocol (binary)

| Opcode | Name | Host sends | Device replies |
|--------|------|------------|----------------|
| `0x01` | PING | — | `0x55` |
| `0x02` | INFO | — | `N`, `DATA_W`, `ACC_W` |
| `0x10` | SET_A | `N` × int8 (row vector) | `0x00` ACK |
| `0x11` | SET_B | `N` × int8 | `0x00` ACK |
| `0x12` | RUN | count (1–255, 0→1) | `0x00` ACK; asserts `i_valid` for count cycles |
| `0x20` | GET_SUM | row, col | 4 bytes LE int32 |
| `0x21` | GET_ALL | — | `N×N×4` bytes LE, row-major `o_sum` |

Invalid opcode or bad index → `0xFF`. `SET_A` / `SET_B` update held inputs; `RUN` MACs using held `A` and `B`.

## FPGA + PC host

### Hardware

1. Synthesize **`tokyo_mac_top`** with your board clock (set `CLK_HZ` to the real frequency) and constraints on `i_uart_rx` / `o_uart_tx`.
2. Connect a **USB–serial adapter** (or the board’s built-in UART):
   - Adapter **TX** → FPGA **`i_uart_rx`**
   - Adapter **RX** ← FPGA **`o_uart_tx`**
   - Common **GND**
3. Match **`BAUD`** in RTL (default **115200**) to the host script.

### Python client

```bash
pip install -r scripts/requirements.txt

# Linux / macOS — pick your serial device
python scripts/tokyo_mac_client.py --port /dev/ttyUSB0 ping
python scripts/tokyo_mac_client.py --port /dev/ttyUSB0 info
python scripts/tokyo_mac_client.py --port /dev/ttyUSB0 demo

# Windows
python scripts/tokyo_mac_client.py --port COM3 demo
```

Examples:

```bash
python scripts/tokyo_mac_client.py -p /dev/ttyUSB0 set-a 1,2,3,4
python scripts/tokyo_mac_client.py -p /dev/ttyUSB0 set-b 2,2,2,2
python scripts/tokyo_mac_client.py -p /dev/ttyUSB0 run 1
python scripts/tokyo_mac_client.py -p /dev/ttyUSB0 get-sum 0 0
python scripts/tokyo_mac_client.py -p /dev/ttyUSB0 get-all
```

Flow: **`set-a`** / **`set-b`** load the per-row inputs held in the FPGA, **`run`** pulses `i_valid` for N clock cycles, then **`get-sum`** or **`get-all`** reads accumulators (allow a short pipeline delay after `run`; the `demo` command sleeps automatically).

**Note:** `N` is fixed at FPGA build time. Use **`info`** to confirm it matches your matrices.

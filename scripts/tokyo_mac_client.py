#!/usr/bin/env python3
"""
Host client for tokyo_mac FPGA over USB-UART (8N1).

Wiring (FPGA top tokyo_mac_top):
  PC TX  -> FPGA i_uart_rx
  PC RX  <- FPGA o_uart_tx
  GND    <-> GND

Defaults match rtl/tokyo_mac_top.sv: 115200 baud, 8N1.

  pip install -r scripts/requirements.txt
  python scripts/tokyo_mac_client.py --port /dev/ttyUSB0 ping
  python scripts/tokyo_mac_client.py --port COM3 info
  python scripts/tokyo_mac_client.py --port /dev/ttyUSB0 demo
"""

from __future__ import annotations

import argparse
import struct
import sys
import time
from typing import Iterable, List, Sequence

try:
    import serial
except ImportError:
    serial = None  # type: ignore

# Opcodes (must match rtl/uart_host_if.sv)
OPC_PING = 0x01
OPC_INFO = 0x02
OPC_SET_A = 0x10
OPC_SET_B = 0x11
OPC_RUN = 0x12
OPC_GET_SUM = 0x20
OPC_GET_ALL = 0x21

RSP_PONG = 0x55
RSP_ACK = 0x00
RSP_ERR = 0xFF


class TokyoMacError(Exception):
    pass


class TokyoMacClient:
    def __init__(
        self,
        port: str,
        baud: int = 115200,
        timeout: float = 2.0,
        settle_s: float = 0.05,
    ) -> None:
        if serial is None:
            raise TokyoMacError(
                "pyserial is required: pip install -r scripts/requirements.txt"
            )
        self._ser = serial.Serial(
            port=port,
            baudrate=baud,
            bytesize=serial.EIGHTBITS,
            parity=serial.PARITY_NONE,
            stopbits=serial.STOPBITS_ONE,
            timeout=timeout,
        )
        self._settle_s = settle_s
        time.sleep(0.1)

    def close(self) -> None:
        if self._ser.is_open:
            self._ser.close()

    def __enter__(self) -> TokyoMacClient:
        return self

    def __exit__(self, *args: object) -> None:
        self.close()

    def _write(self, data: bytes) -> None:
        self._ser.write(data)
        self._ser.flush()

    def _read_exact(self, n: int) -> bytes:
        buf = bytearray()
        while len(buf) < n:
            chunk = self._ser.read(n - len(buf))
            if not chunk:
                raise TokyoMacError(
                    f"timeout: expected {n} bytes, got {len(buf)}"
                )
            buf.extend(chunk)
        return bytes(buf)

    def _expect_ack(self) -> None:
        b = self._read_exact(1)
        if b[0] == RSP_ACK:
            return
        if b[0] == RSP_ERR:
            raise TokyoMacError("device returned ERR (0xFF)")
        raise TokyoMacError(f"expected ACK, got 0x{b[0]:02x}")

    def ping(self) -> bool:
        self._write(bytes([OPC_PING]))
        return self._read_exact(1)[0] == RSP_PONG

    def info(self) -> tuple[int, int, int]:
        self._write(bytes([OPC_INFO]))
        n, data_w, acc_w = self._read_exact(3)
        return int(n), int(data_w), int(acc_w)

    def set_a(self, values: Sequence[int]) -> None:
        payload = _pack_i8(values)
        self._write(bytes([OPC_SET_A]) + payload)
        self._expect_ack()

    def set_b(self, values: Sequence[int]) -> None:
        payload = _pack_i8(values)
        self._write(bytes([OPC_SET_B]) + payload)
        self._expect_ack()

    def run(self, count: int = 1) -> None:
        if not 1 <= count <= 255:
            raise ValueError("count must be 1..255")
        self._write(bytes([OPC_RUN, count]))
        self._expect_ack()

    def get_sum(self, row: int, col: int) -> int:
        self._write(bytes([OPC_GET_SUM, row & 0xFF, col & 0xFF]))
        raw = self._read_exact(4)
        return struct.unpack("<i", raw)[0]

    def get_all(self, n: int) -> List[List[int]]:
        self._write(bytes([OPC_GET_ALL]))
        raw = self._read_exact(n * n * 4)
        flat = struct.unpack(f"<{n * n}i", raw)
        return [list(flat[r * n : (r + 1) * n]) for r in range(n)]

    def mac_once(
        self,
        a: Sequence[int],
        b: Sequence[int],
        cycles: int = 1,
        pipeline_wait_s: float | None = None,
    ) -> None:
        """Load A/B, pulse RUN, optional wait for systolic pipeline."""
        self.set_a(a)
        self.set_b(b)
        self.run(cycles)
        if pipeline_wait_s is None:
            pipeline_wait_s = self._settle_s * (len(a) * len(a) + 4)
        time.sleep(pipeline_wait_s)


def _pack_i8(values: Sequence[int]) -> bytes:
    out = bytearray()
    for v in values:
        if not -128 <= v <= 127:
            raise ValueError(f"int8 out of range: {v}")
        out.append(v & 0xFF)
    return bytes(out)


def _parse_i8_list(s: str) -> List[int]:
    return [int(x.strip(), 0) for x in s.split(",") if x.strip()]


def main(argv: Iterable[str] | None = None) -> int:
    p = argparse.ArgumentParser(description="tokyo_mac UART host client")
    p.add_argument(
        "--port",
        "-p",
        required=True,
        help="Serial port (e.g. /dev/ttyUSB0, /dev/cu.usbserial-*, COM3)",
    )
    p.add_argument("--baud", "-b", type=int, default=115200)
    p.add_argument("--timeout", type=float, default=2.0)
    sub = p.add_subparsers(dest="cmd", required=True)

    sub.add_parser("ping", help="send PING, expect 0x55")

    sub.add_parser("info", help="read N, DATA_W, ACC_W")

    sp = sub.add_parser("set-a", help="SET_A vector (comma-separated int8)")
    sp.add_argument("values", help="e.g. 1,2,3,4")

    sp = sub.add_parser("set-b", help="SET_B vector")
    sp.add_argument("values", help="e.g. 2,2,2,2")

    sp = sub.add_parser("run", help="RUN with cycle count")
    sp.add_argument("count", type=int, nargs="?", default=1)

    sp = sub.add_parser("get-sum", help="read one accumulator")
    sp.add_argument("row", type=int)
    sp.add_argument("col", type=int)

    sp = sub.add_parser("get-all", help="read full NxN sum matrix")

    sub.add_parser("demo", help="ping, info, one MAC, print PE(0,0) sum")

    args = p.parse_args(list(argv) if argv is not None else None)

    try:
        with TokyoMacClient(args.port, baud=args.baud, timeout=args.timeout) as dev:
            if args.cmd == "ping":
                ok = dev.ping()
                print("PONG" if ok else "unexpected response")
                return 0 if ok else 1

            if args.cmd == "info":
                n, dw, aw = dev.info()
                print(f"N={n} DATA_W={dw} ACC_W={aw}")
                return 0

            if args.cmd == "set-a":
                dev.set_a(_parse_i8_list(args.values))
                print("ACK")
                return 0

            if args.cmd == "set-b":
                dev.set_b(_parse_i8_list(args.values))
                print("ACK")
                return 0

            if args.cmd == "run":
                dev.run(args.count)
                print("ACK")
                return 0

            if args.cmd == "get-sum":
                v = dev.get_sum(args.row, args.col)
                print(v)
                return 0

            if args.cmd == "get-all":
                n, _, _ = dev.info()
                m = dev.get_all(n)
                for r, row in enumerate(m):
                    print(f"row {r}: {row}")
                return 0

            if args.cmd == "demo":
                if not dev.ping():
                    print("PING failed", file=sys.stderr)
                    return 1
                n, dw, aw = dev.info()
                print(f"device: N={n} DATA_W={dw} ACC_W={aw}")
                a = [i + 1 for i in range(n)]
                b = [2] * n
                dev.mac_once(a, b, cycles=1)
                s = dev.get_sum(0, 0)
                print(f"PE(0,0) o_sum = {s}")
                print("(rebuild FPGA with same N as firmware expects)")
                return 0

    except TokyoMacError as e:
        print(f"error: {e}", file=sys.stderr)
        return 1
    except serial.SerialException as e:  # type: ignore[union-attr]
        print(f"serial: {e}", file=sys.stderr)
        return 1

    return 0


if __name__ == "__main__":
    sys.exit(main())

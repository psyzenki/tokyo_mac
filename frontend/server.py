#!/usr/bin/env python3
"""
Web frontend for tokyo_mac: stdlib HTTP server wrapping TokyoMacClient.

    python frontend/server.py                 # http://localhost:8765
    python frontend/server.py --http-port 9000

Requires pyserial (pip install -r scripts/requirements.txt). The browser UI
lives in frontend/index.html.
"""

from __future__ import annotations

import argparse
import json
import sys
import threading
import time
import webbrowser
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT / "scripts"))

from tokyo_mac_client import TokyoMacClient, TokyoMacError  # noqa: E402

try:
    from serial.tools import list_ports
except ImportError:
    list_ports = None

INDEX_HTML = Path(__file__).resolve().parent / "index.html"

# Single shared device handle; UART is one-at-a-time so serialize all access.
_lock = threading.Lock()
_client: TokyoMacClient | None = None
_dev_info: dict = {}


def _ports() -> list[dict]:
    if list_ports is None:
        raise TokyoMacError("pyserial is required: pip install pyserial")
    out = []
    for p in list_ports.comports():
        out.append(
            {
                "device": p.device,
                "description": p.description or "",
                "ftdi": (p.vid == 0x0403) or "FTDI" in (p.manufacturer or ""),
            }
        )
    # FTDI ports first (Cmod A7 uses an FT2232HQ), then alphabetical
    out.sort(key=lambda d: (not d["ftdi"], d["device"]))
    return out


def _connect(port: str, baud: int) -> dict:
    global _client, _dev_info
    _disconnect()
    client = TokyoMacClient(port, baud=baud, timeout=2.0)
    try:
        if not client.ping():
            raise TokyoMacError("device did not answer PING (wrong port or stale bitstream?)")
        n, data_w, acc_w = client.info()
    except Exception:
        client.close()
        raise
    _client = client
    _dev_info = {"port": port, "baud": baud, "n": n, "data_w": data_w, "acc_w": acc_w}
    return _dev_info


def _disconnect() -> None:
    global _client, _dev_info
    if _client is not None:
        _client.close()
    _client = None
    _dev_info = {}


def _require_client() -> TokyoMacClient:
    if _client is None:
        raise TokyoMacError("not connected")
    return _client


def _check_vec(name: str, vec, n: int) -> list[int]:
    if not isinstance(vec, list) or len(vec) != n:
        raise TokyoMacError(f"{name} must be a list of {n} ints")
    for v in vec:
        if not isinstance(v, int) or not -128 <= v <= 127:
            raise TokyoMacError(f"{name} values must be int8 (-128..127)")
    return vec


class Handler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):  # quieter console
        pass

    def _json(self, obj, status: int = 200) -> None:
        body = json.dumps(obj).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _body(self) -> dict:
        length = int(self.headers.get("Content-Length") or 0)
        if length == 0:
            return {}
        return json.loads(self.rfile.read(length))

    def do_GET(self):
        try:
            if self.path in ("/", "/index.html"):
                body = INDEX_HTML.read_bytes()
                self.send_response(200)
                self.send_header("Content-Type", "text/html; charset=utf-8")
                self.send_header("Content-Length", str(len(body)))
                self.end_headers()
                self.wfile.write(body)
                return
            if self.path == "/api/ports":
                with _lock:
                    self._json({"ports": _ports()})
                return
            if self.path == "/api/status":
                with _lock:
                    self._json({"connected": _client is not None, **_dev_info})
                return
            if self.path == "/api/all":
                with _lock:
                    dev = _require_client()
                    self._json({"sum": dev.get_all(_dev_info["n"])})
                return
            self._json({"error": "not found"}, 404)
        except TokyoMacError as e:
            self._json({"error": str(e)}, 400)
        except Exception as e:  # serial errors etc.
            self._json({"error": f"{type(e).__name__}: {e}"}, 500)

    def do_POST(self):
        try:
            req = self._body()
            if self.path == "/api/connect":
                with _lock:
                    info = _connect(req["port"], int(req.get("baud", 115200)))
                    self._json({"connected": True, **info})
                return
            if self.path == "/api/disconnect":
                with _lock:
                    _disconnect()
                    self._json({"connected": False})
                return
            if self.path == "/api/ping":
                with _lock:
                    self._json({"pong": _require_client().ping()})
                return
            if self.path == "/api/mac":
                with _lock:
                    dev = _require_client()
                    n = _dev_info["n"]
                    a = _check_vec("a", req.get("a"), n)
                    b = _check_vec("b", req.get("b"), n)
                    count = int(req.get("count", 1))
                    dev.set_a(a)
                    dev.set_b(b)
                    dev.run(count)
                    time.sleep(0.05)  # systolic pipeline is ~2N cycles @12 MHz; UART dominates
                    self._json({"sum": dev.get_all(n)})
                return
            if self.path == "/api/run":
                with _lock:
                    dev = _require_client()
                    dev.run(int(req.get("count", 1)))
                    time.sleep(0.05)
                    self._json({"sum": dev.get_all(_dev_info["n"])})
                return
            self._json({"error": "not found"}, 404)
        except TokyoMacError as e:
            self._json({"error": str(e)}, 400)
        except (KeyError, ValueError, TypeError) as e:
            self._json({"error": f"bad request: {e}"}, 400)
        except Exception as e:
            self._json({"error": f"{type(e).__name__}: {e}"}, 500)


def main() -> int:
    p = argparse.ArgumentParser(description="tokyo_mac web frontend")
    p.add_argument("--http-port", type=int, default=8765)
    p.add_argument("--no-browser", action="store_true")
    args = p.parse_args()

    srv = ThreadingHTTPServer(("127.0.0.1", args.http_port), Handler)
    url = f"http://localhost:{args.http_port}"
    print(f"tokyo_mac frontend: {url}  (Ctrl+C to stop)")
    if not args.no_browser:
        threading.Timer(0.5, webbrowser.open, args=(url,)).start()
    try:
        srv.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        with _lock:
            _disconnect()
    return 0


if __name__ == "__main__":
    sys.exit(main())

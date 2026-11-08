#!/bin/bash
set -e
mkdir -p /logs/verifier

# Stop any pipeline left running by the agent so verification uses fresh services.
if command -v fuser >/dev/null 2>&1; then
    fuser -k 8080/tcp >/dev/null 2>&1 || true
    fuser -k 9000/tcp >/dev/null 2>&1 || true
fi
pkill -f '/home/user/app/daemon/dpi_daemon' >/dev/null 2>&1 || true
pkill -f '/home/user/app/aggregator/server.py' >/dev/null 2>&1 || true
pkill -f '/home/user/app/emitter/stream.py' >/dev/null 2>&1 || true

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import socket
import struct
import subprocess
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer

import pytest

DAEMON_DIR = "/home/user/app/daemon"
DAEMON_PATH = os.path.join(DAEMON_DIR, "dpi_daemon")
LOG_FILE = "/home/user/app/aggregator/parsed_tlvs.log"


def test_daemon_compiled():
    build = subprocess.run(
        ["make", "clean", "all"],
        cwd=DAEMON_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=30,
    )
    assert build.returncode == 0, f"Daemon failed to build from source:\n{build.stdout}"

    daemon_path = "/home/user/app/daemon/dpi_daemon"
    assert os.path.isfile(daemon_path), f"DPI Daemon executable not found at {daemon_path}. Did the build fail?"
    assert os.access(daemon_path, os.X_OK), f"DPI Daemon at {daemon_path} is not executable."
    with open(daemon_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "dpi_daemon is not a compiled ELF executable"

    with open(os.path.join(DAEMON_DIR, "Makefile"), encoding="utf-8") as f:
        makefile = f.read()
    assert "mock" not in makefile.lower(), "Makefile still references the legacy mock libpcap"
    assert "-lpcap" in makefile, "Makefile does not link against the system libpcap"

    with open(os.path.join(DAEMON_DIR, "parser.c"), encoding="utf-8") as f:
        parser_source = f.read()
    assert re.search(r"#\s*include\s*[<\"]assert\.h[>\"]", parser_source), "parser.c must include assert.h"
    assert re.search(r"\bassert\s*\(", parser_source), "parser.c must assert intermediate length invariants"


def test_parsed_tlvs_metric():
    os.makedirs(os.path.dirname(LOG_FILE), exist_ok=True)
    with open(LOG_FILE, "w", encoding="utf-8"):
        pass

    expected = []
    frames = []
    bad_index = secrets.randbelow(5000)
    for i in range(5000):
        if i == bad_index:
            frames.append(struct.pack("!BH", 1, 0xFFFE) + secrets.token_bytes(10))
        else:
            tlv_type = 1 + secrets.randbelow(250)
            tlv_len = secrets.randbelow(25)
            frames.append(struct.pack("!BH", tlv_type, tlv_len) + secrets.token_bytes(tlv_len))
            expected.append({"tlv_type": tlv_type, "tlv_len": tlv_len})

    observed = []
    observed_lock = threading.Lock()

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            try:
                length = int(self.headers.get("Content-Length", "0"))
                body = self.rfile.read(length)
                item = json.loads(body.decode("utf-8"))
                if isinstance(item, dict):
                    with observed_lock:
                        observed.append(item)
                    with open(LOG_FILE, "a", encoding="utf-8") as f:
                        f.write(json.dumps(item) + "\n")
                self.send_response(200)
                self.send_header("Content-Length", "2")
                self.end_headers()
                self.wfile.write(b"OK")
            except Exception:
                self.send_response(400)
                self.send_header("Content-Length", "0")
                self.end_headers()

        def log_message(self, *args):
            pass

    class ReusableHTTPServer(HTTPServer):
        allow_reuse_address = True

    httpd = ReusableHTTPServer(("127.0.0.1", 8080), Handler)
    http_thread = threading.Thread(target=httpd.serve_forever, daemon=True)
    http_thread.start()

    emitter_socket = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
    emitter_socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    emitter_socket.bind(("127.0.0.1", 9000))
    emitter_socket.listen(1)

    emitter_errors = []

    def emit():
        try:
            conn, _ = emitter_socket.accept()
            with conn:
                for payload in frames:
                    conn.sendall(struct.pack("!I", len(payload)) + payload)
        except Exception as exc:
            emitter_errors.append(exc)
        finally:
            emitter_socket.close()

    emitter_thread = threading.Thread(target=emit, daemon=True)
    emitter_thread.start()

    daemon = None
    try:
        started = time.monotonic()
        daemon = subprocess.Popen(
            [DAEMON_PATH],
            cwd=DAEMON_DIR,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        deadline = started + 5.0
        while time.monotonic() < deadline:
            with observed_lock:
                count = len(observed)
            if count >= len(expected):
                break
            if daemon.poll() is not None and not emitter_thread.is_alive():
                time.sleep(0.05)
            time.sleep(0.01)
    finally:
        if daemon is not None and daemon.poll() is None:
            daemon.terminate()
            try:
                daemon.wait(timeout=1)
            except subprocess.TimeoutExpired:
                daemon.kill()
                daemon.wait(timeout=1)
        httpd.shutdown()
        httpd.server_close()
        emitter_thread.join(timeout=1)

    assert not emitter_errors, f"Daemon disconnected before consuming the test stream: {emitter_errors}"

    with observed_lock:
        actual = list(observed)
    assert actual == expected, (
        "Daemon did not emit the exact TLVs from the randomized stream, or emitted a TLV "
        "for the malicious invalid-length packet."
    )

    log_file = "/home/user/app/aggregator/parsed_tlvs.log"
    assert os.path.isfile(log_file), f"Aggregator log file not found at {log_file}. Did the services run and process packets?"

    with open(log_file, "r", encoding="utf-8") as f:
        lines = f.readlines()

    metric_value = len(lines)
    threshold = 4900

    assert metric_value >= threshold, (
        f"Expected at least {threshold} successfully parsed TLV records, "
        f"but found {metric_value}. The daemon likely hung or crashed "
        f"due to the integer overflow bug before processing the full stream."
    )
    assert metric_value == len(expected), "The log contains fabricated, missing, or duplicate records"
    parsed_lines = [json.loads(line) for line in lines]
    assert parsed_lines == expected, "Aggregator log contents do not match the TLVs actually sent"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

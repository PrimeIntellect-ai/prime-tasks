#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import json
import os
import re
import signal
import socket
import struct
import subprocess
import threading
import time
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

import pytest

CONFIG_PATH = "/home/user/app/config.env"
INGESTER_PATH = "/home/user/app/ingester/ingester"
INGESTER_DIR = "/home/user/app/ingester"
WAL_PATH = "/home/user/app/data/transactions.wal"
EXPECTED_SECRET = "d34db33f_s3cr3t99"


def test_01_config_env_secret():
    assert os.path.exists(CONFIG_PATH), f"File {CONFIG_PATH} is missing."
    with open(CONFIG_PATH, "r") as f:
        content = f.read()
    assert "API_SECRET=d34db33f_s3cr3t99" in content, (
        f"config.env does not contain the correct API_SECRET. Found: {content}"
    )


def test_02_ingester_executable_exists():
    assert os.path.exists(INGESTER_PATH), (
        f"Executable {INGESTER_PATH} is missing. Did you compile the C code?"
    )
    assert os.access(INGESTER_PATH, os.X_OK), f"File {INGESTER_PATH} is not executable."
    with open(INGESTER_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The ingester must be a compiled native executable."


def test_03_recovery_yield_metric():
    try:
        req = urllib.request.Request("http://localhost:5000/metrics")
        with urllib.request.urlopen(req, timeout=5) as response:
            data = json.loads(response.read().decode("utf-8"))
            valid_processed = data.get("processed_count", 0)
    except Exception as e:
        pytest.fail(
            "Failed to retrieve metrics from API on port 5000. Ensure both the API "
            f"and Redis are running. Error: {e}"
        )

    yield_rate = valid_processed / 1000.0
    assert yield_rate >= 0.95, (
        f"Recovery yield {yield_rate} is below the required threshold of 0.95 "
        f"(Processed: {valid_processed}/1000 valid records)"
    )


def _kill_port_5000_listener():
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[1].endswith(":1388") and fields[3] == "0A":
                        inodes.add(fields[9])
        except FileNotFoundError:
            pass

    victims = set()
    for entry in os.listdir("/proc"):
        if not entry.isdigit() or int(entry) == os.getpid():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    victims.add(int(entry))
                    break
        except (FileNotFoundError, PermissionError):
            continue

    for pid in victims:
        try:
            os.kill(pid, signal.SIGTERM)
        except ProcessLookupError:
            pass
    if victims:
        time.sleep(0.5)
    for pid in victims:
        try:
            os.kill(pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
    time.sleep(0.2)


def test_04_execute_ingester_against_derived_wal():
    # Generate unique payloads only at verification time, so a submission must
    # actually parse and recover the WAL rather than inflate a self-reported counter.
    nonce = os.urandom(16).hex()
    payloads = []
    wal = bytearray()
    for i in range(100):
        payload = json.dumps(
            {"transaction_id": f"{nonce}-{i}", "amount": 10000 + i},
            separators=(",", ":"),
            sort_keys=True,
        ).encode("utf-8")
        payloads.append(payload)
        wal += struct.pack("<II", 0xDEADBEEF, len(payload))
        wal += payload

        # A valid implementation must scan through these corrupt records and
        # resume at the next magic header.
        if i % 10 == 4:
            wal += struct.pack("<II", 0xDEADBEEF, 0xFFFFFFFF)
            wal += b"CORRUPT_RECORD_DATA"

    expected = collections.Counter(payloads)
    received = collections.Counter()
    unexpected = []
    lock = threading.Lock()

    class Handler(BaseHTTPRequestHandler):
        def do_POST(self):
            self.connection.settimeout(2)
            try:
                length = int(self.headers.get("Content-Length", "0"))
            except ValueError:
                length = -1

            if length < 0 or length > 4096:
                with lock:
                    unexpected.append((self.path, "invalid length"))
                self.send_response(413)
                self.end_headers()
                return

            body = self.rfile.read(length)
            authorized = self.headers.get("X-API-Key") == EXPECTED_SECRET
            valid = self.path == "/ingest" and authorized and body in expected
            with lock:
                if valid:
                    received[body] += 1
                else:
                    unexpected.append((self.path, authorized, body))

            self.send_response(200 if valid else 400)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            try:
                self.wfile.write(b'{"status":"ok"}' if valid else b'{"error":"invalid"}')
            except BrokenPipeError:
                pass

        def log_message(self, format, *args):
            pass

    class Server(ThreadingHTTPServer):
        allow_reuse_address = True

    with open(WAL_PATH, "rb") as f:
        original_wal = f.read()

    server = None
    thread = None
    try:
        _kill_port_5000_listener()
        server = Server(("127.0.0.1", 5000), Handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()

        with open(WAL_PATH, "wb") as f:
            f.write(wal)

        env = os.environ.copy()
        env["API_SECRET"] = EXPECTED_SECRET
        result = subprocess.run(
            [INGESTER_PATH],
            cwd=INGESTER_DIR,
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )

        assert result.returncode == 0, (
            f"Ingester exited with status {result.returncode}. "
            f"stdout={result.stdout!r}, stderr={result.stderr!r}"
        )
        assert not unexpected, f"Ingester sent invalid or unauthenticated requests: {unexpected[:3]!r}"

        recovered = sum(1 for payload in expected if received[payload] >= 1)
        duplicate_count = sum(max(0, count - 1) for count in received.values())
        assert duplicate_count == 0, f"Ingester submitted {duplicate_count} duplicate records."
        assert recovered >= 95, (
            f"Ingester recovered only {recovered}/100 records from a WAL containing "
            "corrupt size fields; at least 95 are required."
        )
    finally:
        with open(WAL_PATH, "wb") as f:
            f.write(original_wal)
        if server is not None:
            server.shutdown()
            server.server_close()
        if thread is not None:
            thread.join(timeout=2)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

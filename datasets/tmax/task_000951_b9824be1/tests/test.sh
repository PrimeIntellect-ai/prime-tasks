#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import json
import os
from pathlib import Path
import secrets
import signal
import socket
import subprocess
import time

import requests


def stop_old_services():
    subprocess.run(["pkill", "-x", "aggregator"], check=False,
                   stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    for proc in Path("/proc").iterdir():
        if not proc.name.isdigit() or int(proc.name) == os.getpid():
            continue
        try:
            cmdline = (proc / "cmdline").read_bytes().replace(b"\0", b" ")
            if b"api.py" in cmdline:
                os.kill(int(proc.name), signal.SIGTERM)
        except (FileNotFoundError, PermissionError, ProcessLookupError):
            pass
    time.sleep(0.25)


def read_expected_logs():
    expected = []
    for path in Path("/app/logs").iterdir():
        if ".log" not in path.name or not path.is_file():
            continue
        with path.open("r", encoding="utf-8") as f:
            for line_number, line in enumerate(f, 1):
                line = line.rstrip("\n")
                parts = line.split(",", 1)
                assert len(parts) == 2 and parts[1], f"Invalid log line in {path}:{line_number}"
                expected.append((int(parts[0]), parts[1]))
    return expected


def validate_payload(data, expected, source):
    assert isinstance(data, list), f"{source} did not return a JSON array"
    assert len(data) >= 100000, (
        f"Error: Only received {len(data)} logs. Expected at least 100000."
    )
    assert len(data) == len(expected), (
        f"{source} returned {len(data)} logs, but the log files contain {len(expected)}"
    )

    actual = []
    previous = None
    for i, item in enumerate(data):
        assert isinstance(item, dict), f"{source} item {i} is not an object"
        assert "timestamp" in item, f"{source} item {i} has no timestamp"
        assert "message" in item, f"{source} item {i} has no message"
        assert type(item["timestamp"]) is int, f"{source} item {i} has a non-integer timestamp"
        assert isinstance(item["message"], str), f"{source} item {i} has a non-string message"
        if previous is not None and item["timestamp"] < previous:
            raise AssertionError(f"Error: Logs are not strictly sorted at index {i}.")
        previous = item["timestamp"]
        actual.append((item["timestamp"], item["message"]))

    assert collections.Counter(actual) == collections.Counter(expected), (
        f"{source} payload does not match the timestamps and messages in /app/logs"
    )


def fetch_aggregator_directly():
    chunks = []
    with socket.create_connection(("127.0.0.1", 8080), timeout=5.0) as s:
        s.settimeout(5.0)
        while True:
            chunk = s.recv(65536)
            if not chunk:
                break
            chunks.append(chunk)
    return json.loads(b"".join(chunks).decode("utf-8"))


def test_log_aggregator_latency_and_correctness():
    source = Path("/app/aggregator/aggregator.c")
    makefile = Path("/app/aggregator/Makefile")
    binary = Path("/app/aggregator/aggregator")
    start_script = Path("/app/start_services.sh")
    assert source.is_file(), "Missing /app/aggregator/aggregator.c"
    assert makefile.is_file(), "Missing /app/aggregator/Makefile"
    assert start_script.is_file(), "Missing /app/start_services.sh"

    nonce = secrets.token_hex(16)
    probe = Path(f"/app/logs/verifier probe {nonce}.log")
    probe_entries = [
        (secrets.randbelow(32768), f"Verifier unpredictable message {nonce} {i}")
        for i in range(7)
    ]

    try:
        probe.write_text("".join(f"{ts},{msg}\n" for ts, msg in probe_entries), encoding="utf-8")
        expected = read_expected_logs()
        for entry in probe_entries:
            assert entry in expected

        stop_old_services()
        try:
            binary.unlink()
        except FileNotFoundError:
            pass

        build = subprocess.run(
            ["make", "-B"], cwd="/app/aggregator", text=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
        )
        assert build.returncode == 0, f"Aggregator build failed:\n{build.stdout}"
        assert binary.is_file() and os.access(binary, os.X_OK), "Makefile did not create an executable aggregator"
        assert binary.read_bytes()[:4] == b"\x7fELF", "Aggregator is not a compiled ELF executable"

        subprocess.run([str(start_script)], cwd="/app", check=True, timeout=10)
        deadline = time.monotonic() + 5
        while True:
            try:
                ready = requests.get("http://127.0.0.1:5000/__verifier_ready__", timeout=0.2)
                if ready.status_code in (200, 404):
                    break
            except requests.RequestException:
                pass
            assert time.monotonic() < deadline, "Query API did not start within 5 seconds"
            time.sleep(0.05)

        start = time.perf_counter()
        response = requests.get("http://127.0.0.1:5000/logs", timeout=5.0)
        response.raise_for_status()
        data = response.json()
        latency = time.perf_counter() - start

        validate_payload(data, expected, "Query API")
        assert latency <= 0.5, f"Latency {latency:.4f}s exceeded threshold of 0.5s"

        direct_data = fetch_aggregator_directly()
        validate_payload(direct_data, expected, "Aggregator TCP service")
    finally:
        try:
            probe.unlink()
        except FileNotFoundError:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

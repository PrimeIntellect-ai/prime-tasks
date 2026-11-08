#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import socket
import struct
import subprocess
import time
from pathlib import Path

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
SOURCE = Path("/home/user/aggregator/src/main.rs")
ORACLE = "/app/legacy_oracle"


def get_service_pid():
    # First try ss, as in the original verifier.
    try:
        output = subprocess.check_output(["ss", "-lptn"], text=True, stderr=subprocess.DEVNULL)
        for line in output.splitlines():
            if ":8080" in line and "LISTEN" in line and "pid=" in line:
                return int(line.split("pid=", 1)[1].split(",", 1)[0])
    except Exception:
        pass

    # Fall back to mapping the listening socket inode through /proc.
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[1].upper().endswith(":1F90") and fields[3] == "0A":
                        inodes.add(fields[9])
        except OSError:
            pass

    for entry in os.listdir("/proc"):
        if not entry.isdigit():
            continue
        fd_dir = f"/proc/{entry}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(f"{fd_dir}/{fd}")
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    return int(entry)
        except OSError:
            continue
    return None


def oracle_result(values):
    payload = json.dumps(values, separators=(",", ":"))
    completed = subprocess.run(
        [ORACLE], input=payload, text=True, capture_output=True, timeout=3, check=True
    )
    return float(json.loads(completed.stdout)["result"])


def post_values(values, timeout=3):
    response = requests.post(f"{BASE_URL}/aggregate", json={"values": values}, timeout=timeout)
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    data = response.json()
    assert isinstance(data, dict) and "result" in data, "Response JSON missing 'result' key"
    assert isinstance(data["result"], (int, float)), "result must be numeric"
    return float(data["result"])


def assert_matches_oracle(values):
    expected = oracle_result(values)
    actual = post_values(values)
    tolerance = max(1e-12, abs(expected) * 2e-14)
    assert math.isfinite(actual), f"Non-finite result for {values!r}: {actual}"
    assert abs(actual - expected) <= tolerance, (
        f"Oracle mismatch for {values!r}: expected {expected!r}, got {actual!r}"
    )


def test_built_rust_artifact_is_running():
    assert SOURCE.is_file(), "Rust source is missing"
    pid = get_service_pid()
    assert pid is not None, "Could not find PID of the service listening on 8080"
    exe = Path(os.path.realpath(f"/proc/{pid}/exe"))
    expected = {
        Path("/home/user/aggregator/target/debug/aggregator"),
        Path("/home/user/aggregator/target/release/aggregator"),
    }
    assert exe in expected, f"Port 8080 is not served by the built aggregator binary: {exe}"
    assert exe.is_file(), "Built aggregator executable is missing"
    assert exe.stat().st_mtime >= SOURCE.stat().st_mtime, "Running binary predates the repaired source"

    # A detached Tokio task survives cancellation unless it is explicitly aborted.
    source = SOURCE.read_text()
    if "tokio::spawn" in source or "tokio :: spawn" in source:
        cancellation_markers = (".abort()", "AbortHandle", "JoinSet", "abort_on_drop")
        assert any(marker in source for marker in cancellation_markers), (
            "Background work is spawned without explicit cancellation/abort ownership"
        )


def test_health_endpoint():
    try:
        response = requests.get(f"{BASE_URL}/health", timeout=2)
        assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}"
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to {BASE_URL}/health: {exc}")


def test_original_aggregate_precision_case():
    # Preserve the original verifier's assertion.
    result = post_values([10000.0, 3.14159, -10000.0])
    assert abs(result - 3.14159) < 1e-9, (
        f"Precision issue detected. Expected ~3.14159, got {result}"
    )


def test_oracle_equivalent_precision_on_unpredictable_inputs():
    assert os.path.isfile(ORACLE) and os.access(ORACLE, os.X_OK), "Legacy oracle is unavailable"

    # Generate fresh catastrophic-cancellation cases on each verifier run. Select
    # cases where ordinary left-to-right binary64 summation disagrees with the
    # oracle so that merely replacing f32 with a naive f64 sum is insufficient.
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    cases = []
    attempts = 0
    while len(cases) < 12 and attempts < 300:
        attempts += 1
        scale = rng.choice([1e12, 1e13, 1e14, 1e15, 1e16])
        count = rng.randint(5, 120)
        unit = rng.choice([0.001, 0.003, 0.01, 0.03, 0.1, 0.2, 0.7, 1.1, 3.14159])
        smalls = [unit * rng.choice([-3, -2, -1, 1, 2, 3]) for _ in range(count)]
        values = [scale] + smalls + [-scale]
        expected = oracle_result(values)
        naive = sum(values)
        if abs(naive - expected) > max(1e-10, abs(expected) * 1e-13):
            cases.append(values)

    assert len(cases) >= 8, "Failed to construct enough precision-sensitive cases"

    # Include differently ordered and non-cancellation inputs as protocol checks.
    cases.extend([
        [0.1] * rng.randint(17, 43),
        [rng.uniform(-1e6, 1e6) for _ in range(101)],
        [1e100, 1.0, -1e100, 2.0, 3.0],
    ])
    for values in cases:
        assert_matches_oracle(values)


def test_cancellation_leak():
    pid = get_service_pid()
    assert pid is not None, "Could not find PID of the service listening on 8080"

    def get_memory_kb():
        with open(f"/proc/{pid}/status") as f:
            for line in f:
                if line.startswith("VmRSS:"):
                    return int(line.split()[1])
        return 0

    initial_memory = get_memory_kb()

    # Preserve the original malformed-body cancellation probes.
    for _ in range(50):
        try:
            s = socket.create_connection(("127.0.0.1", 8080), timeout=1)
            request = (b"POST /aggregate HTTP/1.1\r\nHost: 127.0.0.1:8080\r\n"
                       b"Content-Length: 100000\r\n\r\n{\"values\": [1.0, ")
            s.sendall(request)
            s.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))
            s.close()
        except OSError:
            pass

    # Send complete, valid bodies before resetting the connection. Unlike the
    # old probes, these can be deserialized and enter aggregate(), so cancellation
    # happens while request processing/background work is active.
    body = json.dumps({"values": [1e12, 0.1, 0.2, 0.3, -1e12]}, separators=(",", ":")).encode()
    request = (
        b"POST /aggregate HTTP/1.1\r\n"
        b"Host: 127.0.0.1:8080\r\n"
        b"Content-Type: application/json\r\n"
        b"Connection: close\r\n"
        + f"Content-Length: {len(body)}\r\n\r\n".encode()
        + body
    )
    for _ in range(300):
        try:
            s = socket.create_connection(("127.0.0.1", 8080), timeout=1)
            s.sendall(request)
            time.sleep(0.002)
            s.setsockopt(socket.SOL_SOCKET, socket.SO_LINGER, struct.pack("ii", 1, 0))
            s.close()
        except OSError:
            pass

    time.sleep(2)
    assert get_service_pid() == pid, "Service exited or was replaced during cancellation testing"
    final_memory = get_memory_kb()
    memory_growth = final_memory - initial_memory
    assert memory_growth < 5000, (
        f"Memory leak detected! VmRSS grew by {memory_growth} KB after aborted requests."
    )
    test_health_endpoint()

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

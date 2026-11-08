#!/bin/bash
set -e
mkdir -p /logs/verifier

# Stop any instance the agent may have left running so the verifier can bind
# the telemetry port and start with a clean log.
pkill -f '[a]ggregator\.py' 2>/dev/null || true
pkill -f '[s]ensor[123]\.py' 2>/dev/null || true
sleep 0.2

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import signal
import socket
import subprocess
import sys
import time

BASE_DIR = "/home/user/sensor_net"
METRICS_LOG = os.path.join(BASE_DIR, "output", "metrics.log")
START_SCRIPT = os.path.join(BASE_DIR, "start.sh")
AGGREGATOR_PY = os.path.join(BASE_DIR, "aggregator.py")


def test_aggregator_modifications():
    """Preserve the original source-level assertions."""
    assert os.path.isfile(AGGREGATOR_PY), f"File {AGGREGATOR_PY} is missing."
    with open(AGGREGATOR_PY, "r") as f:
        content = f.read()

    assert "utf-16" in content.lower(), "aggregator.py does not appear to handle utf-16le encoding."
    assert "100" in content, "aggregator.py does not appear to filter values > 100.0."
    assert "0" in content, "aggregator.py does not appear to filter values < 0.0."


def _port_is_bound():
    # UDP port 9001 is 0x2329. Waiting for the actual bind avoids losing the
    # first datagram merely because Python was still starting.
    try:
        with open("/proc/net/udp", "r") as f:
            return any(line.split()[1].upper().endswith(":2329") for line in f.readlines()[1:])
    except (OSError, IndexError):
        return False


def _stddev(window):
    n = len(window)
    sum_x = sum(window)
    sum_x2 = sum(x ** 2 for x in window)
    variance = (sum_x2 - (sum_x ** 2) / n) / n
    return f"{math.sqrt(variance):.4f}"


def test_decoding_and_filtering_behavior():
    """Exercise the submitted aggregator with verifier-selected messages."""
    if os.path.exists(METRICS_LOG):
        os.remove(METRICS_LOG)

    proc = subprocess.Popen(
        [sys.executable, AGGREGATOR_PY],
        cwd=BASE_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )

    stderr = b""
    try:
        deadline = time.time() + 3
        while time.time() < deadline and not _port_is_bound():
            assert proc.poll() is None, "aggregator.py exited before binding UDP port 9001"
            time.sleep(0.05)
        assert _port_is_bound(), "aggregator.py did not bind UDP port 9001"

        rng = random.SystemRandom()
        valid = [round(rng.uniform(8.0, 92.0), 6) for _ in range(9)]

        # Both encodings carry accepted values. Outliers in both encodings are
        # interspersed with them, so including either outlier changes the count
        # and calculated standard deviations (and the huge value may crash the
        # legacy implementation).
        messages = [
            (1_000_000_000_000.0, "utf-8"),
            (valid[0], "utf-16le"),
            (valid[1], "utf-8"),
            (-12345.0, "utf-16le"),
            (valid[2], "utf-16le"),
            (valid[3], "utf-8"),
            (valid[4], "utf-16le"),
            (100_000.0, "utf-16le"),
            (valid[5], "utf-8"),
            (valid[6], "utf-16le"),
            (valid[7], "utf-8"),
            (valid[8], "utf-16le"),
        ]

        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            for index, (value, encoding) in enumerate(messages):
                payload = json.dumps({"sensor": 1000 + index, "value": value}).encode(encoding)
                sock.sendto(payload, ("127.0.0.1", 9001))
                time.sleep(0.04)
        finally:
            sock.close()

        time.sleep(0.7)
        assert proc.poll() is None, "aggregator.py crashed while processing controlled telemetry"
    finally:
        if proc.poll() is None:
            proc.send_signal(signal.SIGINT)
            try:
                _, stderr = proc.communicate(timeout=3)
            except subprocess.TimeoutExpired:
                proc.kill()
                _, stderr = proc.communicate(timeout=2)
        else:
            _, stderr = proc.communicate(timeout=2)

    assert proc.returncode == 0, (
        f"aggregator.py did not exit cleanly after controlled telemetry; "
        f"code={proc.returncode}, stderr={stderr.decode(errors='replace')}"
    )
    assert os.path.isfile(METRICS_LOG), "aggregator.py did not create metrics.log"

    with open(METRICS_LOG, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    # Nine accepted values produce calculations for window sizes 5 through 9.
    # Outliers must produce no calculations and must not enter the window.
    assert len(lines) == 5, f"Expected exactly 5 controlled calculations, got {len(lines)}: {lines}"

    expected = []
    for n in range(5, 10):
        expected.append((n, _stddev(valid[:n])))

    actual = []
    pattern = re.compile(r"^Count:\s*(\d+),\s*StdDev:\s*([+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?)$")
    for line in lines:
        match = pattern.fullmatch(line)
        assert match, f"Malformed controlled metrics line: {line}"
        actual.append((int(match.group(1)), match.group(2)))

    assert actual == expected, (
        "Metrics do not match the rolling calculations over only the accepted "
        f"0.0-100.0 values. Expected {expected}, got {actual}"
    )


def test_system_runs_stably():
    """Preserve the original end-to-end start.sh runtime assertions."""
    if os.path.exists(METRICS_LOG):
        os.remove(METRICS_LOG)

    process = subprocess.run(
        ["timeout", "10", START_SCRIPT],
        cwd=BASE_DIR,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        check=False,
    )

    assert process.returncode in (0, 124), (
        f"start.sh exited prematurely with code {process.returncode}. "
        f"Stderr: {process.stderr.decode(errors='replace')}"
    )
    assert os.path.isfile(METRICS_LOG), f"Metrics log {METRICS_LOG} was not created."

    with open(METRICS_LOG, "r") as f:
        lines = f.readlines()

    assert len(lines) >= 5, f"Expected at least 5 lines in metrics.log, but found {len(lines)}."
    for line in lines:
        assert "StdDev" in line, f"Malformed line in metrics.log: {line.strip()}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

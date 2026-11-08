#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import re
import json
import importlib.util
from decimal import Decimal

TRACKER_PATH = "/home/user/monitor/uptime_tracker.py"
CORE_PATH = "/app/vendored/pingspinner/core.py"


def load_tracker_module():
    spec = importlib.util.spec_from_file_location("submitted_uptime_tracker", TRACKER_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_syscall_storm_fixed():
    """Run the required million-tick workload and limit select-family syscalls."""
    cmd = [
        "strace", "-e", "select,poll,pselect6,ppoll", "-c",
        "python3", TRACKER_PATH, "--simulate", "1000000"
    ]

    try:
        result = subprocess.run(cmd, capture_output=True, text=True, timeout=30)
    except FileNotFoundError:
        with open(CORE_PATH, "r") as f:
            content = f.read()
        assert "0.0" not in content or "select.select([sock], [], [], 0.0)" not in content, \
            "Syscall storm not fixed: select.select still uses 0.0 timeout spinloop."
        return

    assert result.returncode == 0, \
        f"Million-tick monitor execution failed:\nstdout={result.stdout}\nstderr={result.stderr}"

    syscall_count = 0
    for line in result.stderr.splitlines():
        parts = line.split()
        if len(parts) >= 4 and parts[-1] in ("select", "poll", "pselect6", "ppoll"):
            try:
                syscall_count += int(parts[3])
            except ValueError:
                pass

    assert syscall_count <= 1005, \
        f"Syscall count {syscall_count} exceeds threshold of 1005. The spinloop is likely not fully fixed."


def test_precision_and_boundary_static_fixes():
    """Retain the original source-level assertions."""
    assert os.path.isfile(TRACKER_PATH), f"Missing monitor script at {TRACKER_PATH}"
    with open(TRACKER_PATH, "r") as f:
        content = f.read()

    has_fsum = "fsum" in content
    has_decimal = "Decimal" in content
    assert has_fsum or has_decimal, \
        "Precision loss not fixed: neither math.fsum nor Decimal is used for accumulation."
    assert "pop(1)" not in content, \
        "Off-by-one boundary error not fixed: window still pops index 1."


def test_pingspinner_core_static_fix():
    """Retain the original source-level assertion for the zero-timeout spin."""
    assert os.path.isfile(CORE_PATH), f"Missing vendored library file at {CORE_PATH}"
    with open(CORE_PATH, "r") as f:
        content = f.read()
    assert "select.select([sock], [], [], 0.0)" not in content, \
        "The select.select call still uses a hardcoded 0.0 timeout spinloop."


def test_window_boundary_behavior():
    module = load_tracker_module()
    tracker = module.UptimeTracker(max_size=3)

    for value in (1, 2, 3, 4):
        tracker.add_measurement(value)

    assert len(tracker.window) == 3, "Rolling window no longer honors max_size"
    assert list(tracker.window) == [2, 3, 4], \
        f"Rolling window dropped the wrong boundary element: {list(tracker.window)!r}"


def test_extreme_variance_precision_behavior():
    module = load_tracker_module()
    tracker = module.UptimeTracker(max_size=10)

    tracker.add_measurement(100000000.0)
    for _ in range(1000000):
        tracker.add_measurement(0.0000001)

    expected_downtime = Decimal("100000000.0") + Decimal("0.0000001") * Decimal(1000000)
    actual_downtime = Decimal(str(tracker.total_downtime))
    assert abs(actual_downtime - expected_downtime) <= Decimal("1e-9"), \
        f"Precision degraded under extreme variance: expected {expected_downtime}, got {actual_downtime}"

    expected_sla = (Decimal("1000000000.0") - expected_downtime) / Decimal("1000000000.0") * Decimal(100)
    actual_sla = Decimal(str(tracker.get_sla()))
    assert abs(actual_sla - expected_sla) <= Decimal("1e-12"), \
        f"Incorrect SLA: expected {expected_sla}, got {actual_sla}"


def run_core_probe(source):
    result = subprocess.run(
        ["python3", "-c", source], capture_output=True, text=True, timeout=2
    )
    assert result.returncode == 0, \
        f"wait_for_reply probe failed:\nstdout={result.stdout}\nstderr={result.stderr}"
    return json.loads(result.stdout.strip().splitlines()[-1])


def test_wait_for_reply_blocks_until_timeout():
    probe = r'''
import sys, socket, time, json
sys.path.insert(0, "/app/vendored")
from pingspinner import wait_for_reply
s1, s2 = socket.socketpair()
start = time.monotonic()
value = wait_for_reply(s1, 0.06)
elapsed = time.monotonic() - start
print(json.dumps({"elapsed": elapsed, "is_none": value is None}))
'''
    result = run_core_probe(probe)
    assert result["is_none"], "wait_for_reply must return None when the timeout expires"
    assert result["elapsed"] >= 0.035, \
        f"wait_for_reply returned immediately instead of waiting: {result['elapsed']} seconds"
    assert result["elapsed"] < 0.5, "wait_for_reply substantially exceeded its timeout"


def test_wait_for_reply_returns_delayed_payload():
    probe = r'''
import sys, socket, time, json, threading
sys.path.insert(0, "/app/vendored")
from pingspinner import wait_for_reply
s1, s2 = socket.socketpair()
def sender():
    time.sleep(0.04)
    s2.send(b"delayed-pong")
threading.Thread(target=sender, daemon=True).start()
start = time.monotonic()
value = wait_for_reply(s1, 0.5)
elapsed = time.monotonic() - start
print(json.dumps({"elapsed": elapsed, "payload": None if value is None else value.decode("ascii")}))
'''
    result = run_core_probe(probe)
    assert result["payload"] == "delayed-pong", \
        f"wait_for_reply did not return the delayed socket payload: {result!r}"
    assert 0.02 <= result["elapsed"] < 0.3, \
        f"wait_for_reply did not wake promptly when the socket became ready: {result['elapsed']} seconds"


def test_monitor_script_executes_and_reports_expected_sla():
    result = subprocess.run(
        ["python3", TRACKER_PATH, "--simulate", "1000000"],
        capture_output=True, text=True, timeout=30
    )
    assert result.returncode == 0, \
        f"Monitor script failed:\nstdout={result.stdout}\nstderr={result.stderr}"
    match = re.search(r"SLA:\s*([-+0-9.eE]+)", result.stdout)
    assert match, f"Monitor did not report an SLA value: {result.stdout!r}"

    actual = Decimal(match.group(1))
    expected_downtime = Decimal("0.0000001") * Decimal(1000000)
    expected = (Decimal("1000000000.0") - expected_downtime) / Decimal("1000000000.0") * Decimal(100)
    assert abs(actual - expected) <= Decimal("1e-12"), \
        f"Million-tick SLA is incorrect: expected {expected}, got {actual}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

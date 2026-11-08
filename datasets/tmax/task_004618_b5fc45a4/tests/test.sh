#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import concurrent.futures
import dis
import importlib.util
import json
import math
import os
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import threading
import time

import pytest
from packaging.version import Version

APP_DIR = "/home/user/app"
REQ_FILE = os.path.join(APP_DIR, "requirements.txt")
STATS_FILE = os.path.join(APP_DIR, "stats_calculator.py")
STRESS_TEST_FILE = os.path.join(APP_DIR, "stress_test.sh")


def test_requirements_fixed():
    """Verify requirements.txt is fixed, installable, and does not downgrade scipy."""
    assert os.path.isfile(REQ_FILE), f"{REQ_FILE} does not exist."
    with open(REQ_FILE, "r") as f:
        content = f.read()

    # Preserve the original checks.
    assert "scipy" in content.lower(), "scipy is missing from requirements.txt"
    result = subprocess.run(
        ["pip", "install", "--dry-run", "-r", REQ_FILE],
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, (
        f"pip install failed to resolve dependencies:\n{result.stderr}"
    )

    # Resolve from scratch and inspect the selected scipy distribution, rather
    # than trusting text in requirements.txt or an already-installed package.
    with tempfile.NamedTemporaryFile(suffix=".json") as report:
        resolved = subprocess.run(
            [
                "pip", "install", "--dry-run", "--ignore-installed",
                "--report", report.name, "-r", REQ_FILE,
            ],
            capture_output=True,
            text=True,
            timeout=180,
        )
        assert resolved.returncode == 0, (
            f"fresh dependency resolution failed:\n{resolved.stderr}"
        )
        report.seek(0)
        data = json.load(report)

    scipy_versions = [
        item.get("metadata", {}).get("version")
        for item in data.get("install", [])
        if item.get("metadata", {}).get("name", "").lower() == "scipy"
    ]
    assert scipy_versions, "Dependency resolution did not select scipy."
    assert Version(scipy_versions[0]) >= Version("1.10.1"), (
        f"scipy was downgraded to {scipy_versions[0]}"
    )


def test_stress_test_exists_and_executable():
    """Verify stress_test.sh exists and is executable."""
    assert os.path.isfile(STRESS_TEST_FILE), f"{STRESS_TEST_FILE} does not exist."
    assert os.access(STRESS_TEST_FILE, os.X_OK), f"{STRESS_TEST_FILE} is not executable."


def load_stats_module():
    spec = importlib.util.spec_from_file_location("submitted_stats_calculator", STATS_FILE)
    assert spec and spec.loader
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def test_python_script_fixed():
    """Preserve the locking check and exercise shared updates under forced contention."""
    assert os.path.isfile(STATS_FILE), f"{STATS_FILE} does not exist."
    with open(STATS_FILE, "r") as f:
        content = f.read()

    # Preserve the original assertion.
    has_threading = "threading" in content or "Lock" in content or "multiprocessing" in content
    assert has_threading, "No locking mechanism (e.g., threading.Lock) found in stats_calculator.py."

    module = load_stats_module()
    assert hasattr(module, "StatTracker"), "StatTracker is missing."
    tracker = module.StatTracker()
    add_batch = tracker.add_batch
    instructions = {i.offset: i for i in dis.get_instructions(add_batch)}

    # Yield immediately before shared attributes are stored. Without real
    # synchronization, several threads compute from the same old value and
    # overwrite one another; comments or unused Lock objects do not help.
    def trace(frame, event, arg):
        if event == "call" and frame.f_code is add_batch.__code__:
            frame.f_trace_opcodes = True
            return trace
        if event == "opcode" and frame.f_code is add_batch.__code__:
            instruction = instructions.get(frame.f_lasti)
            if instruction and instruction.opname == "STORE_ATTR" and instruction.argval in {
                "sum_x", "sum_x2", "count"
            }:
                time.sleep(0.004)
        return trace

    old_trace = threading.gettrace()
    threading.settrace(trace)
    batches = [[float(i % 7 + 1)] * 25 for i in range(80)]
    try:
        with concurrent.futures.ThreadPoolExecutor(max_workers=20) as executor:
            list(executor.map(add_batch, batches))
    finally:
        threading.settrace(old_trace)

    expected_sum = sum(sum(batch) for batch in batches)
    expected_sum2 = sum(sum(x * x for x in batch) for batch in batches)
    expected_count = sum(len(batch) for batch in batches)
    assert tracker.count == expected_count, "Concurrent count updates were lost."
    assert tracker.sum_x == pytest.approx(expected_sum), "Concurrent sum_x updates were lost."
    assert tracker.sum_x2 == pytest.approx(expected_sum2), "Concurrent sum_x2 updates were lost."


def test_stats_program_runs_stably():
    """Execute the submitted calculator and validate its observable result."""
    for _ in range(5):
        result = subprocess.run(
            [sys.executable, STATS_FILE],
            cwd=APP_DIR,
            capture_output=True,
            text=True,
            timeout=30,
        )
        assert result.returncode == 0, result.stderr
        assert "Numerical Instability Detected" not in result.stderr
        match = re.search(r"Stddev:\s*([^\s]+)", result.stdout)
        assert match, f"Missing Stddev output: {result.stdout!r}"
        value = float(match.group(1))
        assert math.isfinite(value) and value >= 0


def test_stress_test_execution():
    """Preserve the original successful execution check."""
    result = subprocess.run(
        [STRESS_TEST_FILE],
        cwd=APP_DIR,
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, (
        f"stress_test.sh failed with exit code {result.returncode}.\n"
        f"STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}"
    )
    assert "Race condition reproduced" not in result.stdout, (
        "Stress test output indicates the race condition is still present."
    )


PROBE_SOURCE = r'''#!/usr/bin/env python3
import fcntl
import os
import sys
import time

state_path = os.environ["STRESS_PROBE_STATE"]
mode = os.environ.get("STRESS_PROBE_MODE", "success")

with open(state_path, "r+") as state:
    fcntl.flock(state, fcntl.LOCK_EX)
    values = state.read().strip().split()
    total, active, maximum = map(int, values or ["0", "0", "0"])
    total += 1
    active += 1
    maximum = max(maximum, active)
    run_number = total
    state.seek(0)
    state.truncate()
    state.write(f"{total} {active} {maximum}\n")
    state.flush()
    fcntl.flock(state, fcntl.LOCK_UN)

try:
    if mode == "failure" and run_number == 1:
        print("Numerical Instability Detected", file=sys.stderr, flush=True)
        sys.exit(1)
    time.sleep(0.25 if mode == "success" else 1.0)
finally:
    with open(state_path, "r+") as state:
        fcntl.flock(state, fcntl.LOCK_EX)
        total, active, maximum = map(int, state.read().strip().split())
        active -= 1
        state.seek(0)
        state.truncate()
        state.write(f"{total} {active} {maximum}\n")
        state.flush()
'''


def run_stress_with_probe(mode):
    backup = STATS_FILE + ".verifier_backup"
    state_fd, state_path = tempfile.mkstemp(prefix="stress-state-")
    os.write(state_fd, b"0 0 0\n")
    os.close(state_fd)
    os.replace(STATS_FILE, backup)
    try:
        with open(STATS_FILE, "w") as f:
            f.write(PROBE_SOURCE)
        os.chmod(STATS_FILE, stat.S_IRUSR | stat.S_IWUSR | stat.S_IXUSR |
                            stat.S_IRGRP | stat.S_IXGRP | stat.S_IROTH | stat.S_IXOTH)
        env = os.environ.copy()
        env["STRESS_PROBE_STATE"] = state_path
        env["STRESS_PROBE_MODE"] = mode
        result = subprocess.run(
            [STRESS_TEST_FILE],
            cwd=APP_DIR,
            env=env,
            capture_output=True,
            text=True,
            timeout=180,
        )
        with open(state_path) as f:
            total, active, maximum = map(int, f.read().strip().split())
        return result, total, maximum
    finally:
        if os.path.exists(STATS_FILE):
            os.unlink(STATS_FILE)
        os.replace(backup, STATS_FILE)
        os.unlink(state_path)


def test_stress_test_performs_100_runs_with_20_way_contention():
    result, total, maximum = run_stress_with_probe("success")
    assert result.returncode == 0, result.stderr
    assert total == 100, f"stress_test.sh performed {total} runs instead of 100."
    assert maximum >= 20, (
        f"stress_test.sh reached only {maximum}-way concurrency instead of 20-way contention."
    )


def test_stress_test_detects_marker_on_stderr_and_fails():
    result, total, _ = run_stress_with_probe("failure")
    assert result.returncode == 1, (
        f"stress_test.sh must exit 1 after the stderr marker, got {result.returncode}."
    )
    assert "Race condition reproduced" in result.stdout, (
        "stress_test.sh did not report 'Race condition reproduced' on stdout."
    )
    assert total < 100, "stress_test.sh continued all 100 runs after detecting the error."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

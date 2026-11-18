#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import importlib.util
import os
import re
import secrets
import subprocess
import sys

import pytest


def load_worker():
    worker_path = "/home/user/worker.py"
    assert os.path.isfile(worker_path), f"File {worker_path} does not exist"

    spec = importlib.util.spec_from_file_location("worker", worker_path)
    worker = importlib.util.module_from_spec(spec)
    sys.modules["worker"] = worker
    spec.loader.exec_module(worker)
    assert hasattr(worker, "calculate_weight"), "worker.py is missing calculate_weight function"
    assert callable(worker.calculate_weight), "calculate_weight is not callable"
    return worker


def expected_weight(n):
    if n <= 0:
        return 0
    if n == 1:
        return 1
    if n == 2:
        return 2
    previous, current = 1, 2
    for _ in range(3, n + 1):
        previous, current = current, previous + current
    return current


def test_worker_fixed():
    worker = load_worker()

    try:
        res_neg = worker.calculate_weight(-3)
        assert res_neg == 0, f"Expected calculate_weight(-3) to return 0, but got {res_neg}"

        res_zero = worker.calculate_weight(0)
        assert res_zero == 0, f"Expected calculate_weight(0) to return 0, but got {res_zero}"

        res_pos = worker.calculate_weight(5)
        assert res_pos == 8, f"Expected calculate_weight(5) to return 8, but got {res_pos}"
    except RecursionError:
        pytest.fail("calculate_weight raised a RecursionError, meaning the base case for n <= 0 is still missing or incorrect.")

    # Exercise inputs not known when the submission was written, including large
    # negative values that must return immediately and varied positive values.
    dynamic_inputs = {
        -secrets.randbelow(10**12) - 1,
        -secrets.randbelow(10**18) - 1,
        secrets.randbelow(18) + 6,
        secrets.randbelow(12) + 24,
    }
    dynamic_inputs.update(range(-20, 1))
    dynamic_inputs.update(range(1, 23))

    for n in dynamic_inputs:
        try:
            actual = worker.calculate_weight(n)
        except RecursionError:
            pytest.fail(f"calculate_weight({n}) raised RecursionError")
        assert actual == expected_weight(n), (
            f"calculate_weight({n}) returned {actual}; expected {expected_weight(n)}"
        )


def test_run_after_log_exists_and_run_system_executes():
    path = "/home/user/logs/run_after.log"
    assert os.path.isfile(path), f"File {path} does not exist. Did you run the run_system.py script?"

    with open(path, "r") as f:
        content = f.read()

    assert "TASK_EVENT ID:4 STATUS:SUCCESS RESULT:0" in content, "run_after.log does not contain the expected success event for ID:4"
    assert "TASK_EVENT ID:5 STATUS:SUCCESS RESULT:8" in content, "run_after.log does not contain the expected success event for ID:5"

    # Remove the claimed output and execute the required recovery program. This
    # proves that the repaired worker works through the real operational entrypoint.
    os.remove(path)
    completed = subprocess.run(
        [sys.executable, "/home/user/run_system.py"],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert completed.returncode == 0, (
        f"run_system.py failed with exit code {completed.returncode}.\n"
        f"stdout: {completed.stdout}\nstderr: {completed.stderr}"
    )
    assert os.path.isfile(path), "run_system.py did not recreate run_after.log"

    with open(path, "r") as f:
        rerun_content = f.read()

    assert "TASK_EVENT ID:4 STATUS:SUCCESS RESULT:0" in rerun_content, "run_after.log does not contain the expected success event for ID:4"
    assert "TASK_EVENT ID:5 STATUS:SUCCESS RESULT:8" in rerun_content, "run_after.log does not contain the expected success event for ID:5"
    assert rerun_content.splitlines() == [
        "[2023-10-15T08:05:00] TASK_EVENT ID:4 STATUS:SUCCESS RESULT:0",
        "[2023-10-15T08:06:00] TASK_EVENT ID:5 STATUS:SUCCESS RESULT:8",
    ], "run_system.py produced unexpected run_after.log contents"


def test_diagnostic_report_content():
    report_path = "/home/user/diagnostic_report.txt"
    assert os.path.isfile(report_path), f"File {report_path} does not exist."

    with open(report_path, "r") as f:
        report_raw_lines = f.read().splitlines()

    lines = [line.strip() for line in report_raw_lines if line.strip()]

    expected_lines = [
        "[2023-10-15T08:01:00] TASK_EVENT ID:1 STATUS:QUEUED",
        "[2023-10-15T08:01:30] TASK_EVENT ID:1 STATUS:SUCCESS RESULT:1",
        "[2023-10-15T08:02:00] TASK_EVENT ID:2 STATUS:QUEUED",
        "[2023-10-15T08:02:30] TASK_EVENT ID:2 STATUS:SUCCESS RESULT:2",
        "[2023-10-15T08:03:00] TASK_EVENT ID:3 STATUS:QUEUED",
        "[2023-10-15T08:04:00] TASK_EVENT ID:3 STATUS:FAILED ERROR:RecursionError",
        "[2023-10-15T08:05:00] TASK_EVENT ID:4 STATUS:SUCCESS RESULT:0",
        "[2023-10-15T08:06:00] TASK_EVENT ID:5 STATUS:SUCCESS RESULT:8",
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in diagnostic_report.txt, but got {len(lines)}"
    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch.\nExpected: {expected}\nActual:   {actual}"

    # Independently extract TASK_EVENT records from every current .log file and
    # derive the chronological answer rather than trusting a fixed report alone.
    extracted = []
    timestamp_pattern = re.compile(r"^\[([^\]]+)\]")
    for log_path in sorted(glob.glob("/home/user/logs/*.log")):
        with open(log_path, "r") as log_file:
            for raw_line in log_file.read().splitlines():
                if "TASK_EVENT" not in raw_line:
                    continue
                match = timestamp_pattern.match(raw_line)
                assert match, f"TASK_EVENT line has no leading timestamp: {raw_line}"
                extracted.append((match.group(1), raw_line))

    derived_lines = [line for _, line in sorted(extracted, key=lambda item: item[0])]
    assert report_raw_lines == derived_lines, (
        "diagnostic_report.txt must contain exactly all raw TASK_EVENT lines "
        "from every .log file, sorted strictly by timestamp"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

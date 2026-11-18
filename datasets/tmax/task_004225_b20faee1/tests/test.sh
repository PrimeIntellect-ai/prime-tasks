#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
from datetime import datetime, timedelta, timezone

import pytest

SCRIPT_PATH = "/home/user/malware_analysis/process_logs.sh"
BEACONS_PATH = "/home/user/malware_analysis/beacons.log"
INTERVALS_PATH = "/home/user/malware_analysis/intervals.txt"
TOTAL_PATH = "/home/user/malware_analysis/total_time.log"


def run_script(timeout=5, env=None):
    try:
        return subprocess.run(
            [SCRIPT_PATH],
            capture_output=True,
            text=True,
            timeout=timeout,
            env=env,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Script execution timed out. Infinite loop or bad date binary issue is likely not fixed.")


def test_script_executes_successfully():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."

    result = run_script()
    assert result.returncode == 0, (
        f"Script failed with return code {result.returncode}.\nStderr: {result.stderr}"
    )


def test_intervals_output():
    assert os.path.isfile(INTERVALS_PATH), f"File {INTERVALS_PATH} is missing."

    with open(INTERVALS_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 4, f"Expected 4 intervals, but found {len(lines)}."

    expected_intervals = [1.5, 1.6, 2.7, 4.25]
    for i, (actual, expected) in enumerate(zip(lines, expected_intervals)):
        try:
            actual_float = float(actual)
        except ValueError:
            pytest.fail(f"Line {i+1} in {INTERVALS_PATH} is not a valid float: '{actual}'")

        assert abs(actual_float - expected) < 0.001, (
            f"Interval {i+1} is incorrect. Expected ~{expected}, got {actual_float}."
        )


def test_total_time_output():
    assert os.path.isfile(TOTAL_PATH), f"File {TOTAL_PATH} is missing."

    with open(TOTAL_PATH, "r") as f:
        content = f.read().strip()

    try:
        total_float = float(content)
    except ValueError:
        pytest.fail(f"Content of {TOTAL_PATH} is not a valid float: '{content}'")

    expected_total = 10.05
    assert abs(total_float - expected_total) < 0.001, (
        f"Total time is incorrect. Expected ~{expected_total}, got {total_float}."
    )


def test_processes_unseen_beacon_fixture():
    rng = random.SystemRandom()
    base = datetime(
        2024,
        rng.randint(1, 11),
        rng.randint(1, 25),
        rng.randint(0, 20),
        rng.randint(0, 50),
        rng.randint(0, 20),
        rng.randrange(0, 1000) * 1000,
        tzinfo=timezone.utc,
    )

    interval_ms = [rng.randint(101, 4900) for _ in range(6)]
    timestamps = [base]
    for milliseconds in interval_ms:
        timestamps.append(timestamps[-1] + timedelta(milliseconds=milliseconds))

    fixture_lines = []
    for index, timestamp in enumerate(timestamps):
        milliseconds = timestamp.microsecond // 1000
        if index % 2 == 0:
            rendered = timestamp.strftime("%Y-%m-%d %H:%M:%S") + f".{milliseconds:03d}"
        else:
            rendered = timestamp.strftime("%Y-%m-%dT%H:%M:%S") + f".{milliseconds:03d}Z"
        fixture_lines.append(f"[BEACON] {rendered}")

    with open(BEACONS_PATH, "w") as f:
        f.write("\n".join(fixture_lines) + "\n")

    env = os.environ.copy()
    env["TZ"] = "UTC"
    result = run_script(env=env)
    assert result.returncode == 0, (
        f"Script failed on an unseen beacon fixture with return code {result.returncode}.\n"
        f"Stderr: {result.stderr}"
    )

    assert os.path.isfile(INTERVALS_PATH), f"File {INTERVALS_PATH} is missing."
    with open(INTERVALS_PATH, "r") as f:
        raw_lines = f.read().splitlines()

    assert len(raw_lines) == len(interval_ms), (
        f"Expected {len(interval_ms)} intervals for the unseen fixture, but found {len(raw_lines)}."
    )

    expected_intervals = [milliseconds / 1000.0 for milliseconds in interval_ms]
    for i, (line, expected) in enumerate(zip(raw_lines, expected_intervals), start=1):
        assert line.strip(), f"Interval line {i} is empty."
        try:
            actual = float(line.strip())
        except ValueError:
            pytest.fail(f"Interval line {i} is not a valid float: '{line}'")
        assert abs(actual - expected) < 0.001, (
            f"Interval {i} for the unseen fixture is incorrect. Expected ~{expected}, got {actual}."
        )

    assert os.path.isfile(TOTAL_PATH), f"File {TOTAL_PATH} is missing."
    with open(TOTAL_PATH, "r") as f:
        total_content = f.read().strip()
    try:
        actual_total = float(total_content)
    except ValueError:
        pytest.fail(f"Content of {TOTAL_PATH} is not a valid float: '{total_content}'")

    expected_total = sum(interval_ms) / 1000.0
    assert abs(actual_total - expected_total) < 0.001, (
        f"Total for the unseen fixture is incorrect. Expected ~{expected_total}, got {actual_total}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import importlib.util
import json
import math
import os
import re
import subprocess

import pytz

ROOT = "/home/user/uptime_monitor"
MONITOR_PATH = os.path.join(ROOT, "monitor.py")
FMT = "%Y-%m-%d %H:%M:%S"


def load_monitor():
    assert os.path.isfile(MONITOR_PATH), f"File {MONITOR_PATH} does not exist."
    spec = importlib.util.spec_from_file_location("submitted_monitor", MONITOR_PATH)
    assert spec is not None and spec.loader is not None, "monitor.py is not importable."
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, "calculate_uptime", None)), \
        "monitor.py must define callable calculate_uptime."
    return module


def localize_boundary(tz, value, is_start):
    naive = datetime.datetime.strptime(value, FMT)
    try:
        return tz.localize(naive, is_dst=None)
    except pytz.AmbiguousTimeError:
        # A wall-clock interval starts at the first occurrence of an ambiguous
        # start time and ends at the last occurrence of an ambiguous end time.
        return tz.localize(naive, is_dst=is_start)


def expected_uptime(start, end, downtimes):
    tz = pytz.timezone("US/Eastern")
    start_dt = localize_boundary(tz, start, True)
    end_dt = localize_boundary(tz, end, False)
    elapsed = (end_dt.astimezone(pytz.UTC) - start_dt.astimezone(pytz.UTC)).total_seconds()
    if elapsed == 0:
        return 0.0
    return 100.0 * (1.0 - math.fsum(downtimes) / elapsed)


def test_recovered_ts():
    path = os.path.join(ROOT, "recovered_ts.txt")
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "2023-11-05 01:23:45", \
        f"Expected '2023-11-05 01:23:45', but got '{content}'"

    with open(os.path.join(ROOT, "crash_dump.bin"), "rb") as f:
        dump = f.read()
    matches = re.findall(rb"LAST_PROCESSED_TS: (\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})", dump)
    assert matches, "crash_dump.bin contains no LAST_PROCESSED_TS timestamp."
    assert content == matches[-1].decode("ascii"), \
        "recovered_ts.txt does not contain the last timestamp embedded in crash_dump.bin."


def test_monitor_timezone_behavior():
    calculate_uptime = load_monitor().calculate_uptime
    cases = [
        ("2023-11-05 01:00:00", "2023-11-05 02:00:00", [1.0]),
        ("2023-11-05 00:00:00", "2023-11-05 03:00:00", [0.25, 0.5]),
        ("2024-03-10 00:00:00", "2024-03-10 03:00:00", [0.125, 0.375]),
        ("2024-02-12 09:15:00", "2024-02-12 12:45:00", [0.2, 0.3]),
    ]
    for start, end, downtimes in cases:
        expected = expected_uptime(start, end, downtimes)
        actual = calculate_uptime(start, end, downtimes)
        assert math.isclose(actual, expected, rel_tol=1e-12, abs_tol=1e-12), \
            f"Incorrect uptime for {start} to {end}: expected {expected}, got {actual}"


def test_monitor_tiny_downtime_precision():
    calculate_uptime = load_monitor().calculate_uptime
    downtimes = [0.0000001] * 10_000_000
    expected = expected_uptime(
        "2024-02-12 00:00:00", "2024-02-12 01:00:00", downtimes
    )
    actual = calculate_uptime(
        "2024-02-12 00:00:00", "2024-02-12 01:00:00", downtimes
    )
    assert math.fsum(downtimes) == 1.0
    assert actual == expected, \
        f"Tiny downtime fractions were not summed robustly: expected {expected}, got {actual}"


def test_report_json():
    result = subprocess.run(
        ["python3", "generate_report.py"],
        cwd=ROOT,
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, \
        f"generate_report.py failed:\n{result.stdout}\n{result.stderr}"

    path = os.path.join(ROOT, "report.json")
    assert os.path.isfile(path), f"File {path} does not exist. Did you run generate_report.py?"
    with open(path, "r") as f:
        data = json.load(f)

    assert "uptime_percentage" in data, "report.json missing 'uptime_percentage' key."

    expected_uptime_value = 100.0 * (1.0 - (1.0 / 14400.0))
    actual_uptime = data["uptime_percentage"]

    assert math.isclose(actual_uptime, expected_uptime_value, rel_tol=1e-9), \
        f"Expected uptime_percentage to be close to {expected_uptime_value}, but got {actual_uptime}. " \
        "Check your DST calculation and floating point summation."


def test_pytest_suite():
    test_file = os.path.join(ROOT, "test_monitor.py")
    assert os.path.isfile(test_file), f"File {test_file} does not exist."

    collected = subprocess.run(
        ["pytest", "--collect-only", "-q", test_file],
        cwd=ROOT,
        capture_output=True,
        text=True,
        timeout=120,
    )
    assert collected.returncode == 0, \
        f"Could not collect tests from {test_file}:\n{collected.stdout}\n{collected.stderr}"
    test_nodes = [line for line in collected.stdout.splitlines() if "::" in line]
    assert len(test_nodes) >= 2, f"Expected at least two pytest tests in {test_file}."

    result = subprocess.run(
        ["pytest", test_file],
        cwd=ROOT,
        capture_output=True,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, \
        f"pytest on {test_file} failed with output:\n{result.stdout}\n{result.stderr}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

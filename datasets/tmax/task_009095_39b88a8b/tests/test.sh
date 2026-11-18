#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import math
import pytest

def test_cpp_source_exists():
    assert os.path.exists("/home/user/config_tracker.cpp"), "/home/user/config_tracker.cpp does not exist."
    assert os.path.isfile("/home/user/config_tracker.cpp"), "/home/user/config_tracker.cpp is not a file."

def test_executable_exists():
    assert os.path.exists("/home/user/config_tracker"), "/home/user/config_tracker executable does not exist."
    assert os.access("/home/user/config_tracker", os.X_OK), "/home/user/config_tracker is not executable."

def compute_expected_output(input_lines):
    from collections import defaultdict

    windows = defaultdict(list)
    counts = defaultdict(int)
    output_lines = []

    # Skip header
    for line in input_lines[1:]:
        line = line.strip()
        if not line:
            continue
        parts = line.split(',')
        if len(parts) != 4:
            continue
        timestamp = parts[0]
        service = parts[1]
        metric_value = float(parts[3])

        counts[service] += 1
        windows[service].append(metric_value)
        if len(windows[service]) > 3:
            windows[service].pop(0)

        if counts[service] % 2 == 0:
            window = windows[service]
            n = len(window)
            mean = sum(window) / n
            variance = sum((x - mean) ** 2 for x in window) / n
            stddev = math.sqrt(variance)

            if stddev == 0.0:
                z_score = 0.0
            else:
                z_score = (metric_value - mean) / stddev

            output_lines.append(f"{service},{timestamp},{metric_value:.4f},{mean:.4f},{stddev:.4f},{z_score:.4f}")

    return output_lines

def test_tracker_output_file():
    input_file = "/home/user/config_updates.csv"
    output_file = "/home/user/tracker_output.csv"

    assert os.path.exists(output_file), f"{output_file} does not exist."

    with open(input_file, "r") as f:
        input_lines = f.readlines()

    expected_lines = compute_expected_output(input_lines)

    with open(output_file, "r") as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {output_file}, but got {len(actual_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Line {i+1} in {output_file} does not match.\nExpected: {expected}\nActual:   {actual}"

def test_tracker_logic_with_custom_input():
    custom_input = """timestamp,service_name,metric_name,metric_value
1,api,latency,100.0
2,api,latency,110.0
3,api,latency,120.0
4,api,latency,130.0
5,api,latency,140.0
"""
    expected_lines = compute_expected_output(custom_input.strip().split('\n'))

    proc = subprocess.run(
        ["/home/user/config_tracker"],
        input=custom_input,
        text=True,
        capture_output=True
    )

    assert proc.returncode == 0, "Execution of /home/user/config_tracker failed."

    actual_lines = [line.strip() for line in proc.stdout.split('\n') if line.strip()]

    assert len(actual_lines) == len(expected_lines), "Executable did not produce the correct number of output lines for custom input."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Output mismatch for custom input at line {i+1}.\nExpected: {expected}\nActual:   {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

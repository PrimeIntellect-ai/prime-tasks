#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import math
import pytest
from collections import deque

def calc_stats(window):
    if len(window) < 2:
        return window[0] if len(window) == 1 else 0.0, 0.0
    mean = sum(window) / len(window)
    variance = sum((x - mean) ** 2 for x in window) / (len(window) - 1)
    return mean, math.sqrt(variance)

def test_cpp_source_exists():
    """Verify that the C++ source file was created."""
    source_path = '/home/user/detector.cpp'
    assert os.path.exists(source_path), f"Source file {source_path} is missing."
    assert os.path.isfile(source_path), f"{source_path} is not a file."

def test_executable_exists():
    """Verify that the executable was compiled."""
    exe_path = '/home/user/detector'
    assert os.path.exists(exe_path), f"Executable {exe_path} is missing."
    assert os.path.isfile(exe_path), f"{exe_path} is not a file."
    assert os.access(exe_path, os.X_OK), f"Executable {exe_path} does not have execute permissions."

def test_output_csv_exists():
    """Verify that the output CSV file was created."""
    output_path = '/home/user/processed_vibration.csv'
    assert os.path.exists(output_path), f"Output file {output_path} is missing."
    assert os.path.isfile(output_path), f"{output_path} is not a file."

def test_output_csv_content():
    """Verify the content of the processed CSV matches the expected calculations."""
    input_path = '/home/user/vibration_log.csv'
    output_path = '/home/user/processed_vibration.csv'

    assert os.path.exists(input_path), f"Input file {input_path} is missing."
    assert os.path.exists(output_path), f"Output file {output_path} is missing."

    expected = []
    windows = { 'M_01': deque(maxlen=10), 'M_02': deque(maxlen=10), 'M_03': deque(maxlen=10) }

    with open(input_path, 'r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            ts = row['Timestamp']
            mid = row['MachineID']
            val = float(row['VibrationValue'])

            win = windows[mid]
            if len(win) < 2:
                mu, sigma = val, 0.0
            else:
                mu, sigma = calc_stats(win)

            z = 0.0 if sigma == 0 else (val - mu) / sigma
            is_anomaly = 1 if abs(z) > 3.0 else 0

            expected.append(f"{ts},{mid},{val:.4f},{mu:.4f},{sigma:.4f},{z:.4f},{is_anomaly}")
            win.append(val)

    with open(output_path, 'r', newline='') as f:
        lines = [line.strip() for line in f.readlines()]

    assert len(lines) > 0, f"Output file {output_path} is empty."

    expected_header = "Timestamp,MachineID,VibrationValue,RollingMean,RollingStd,ZScore,IsAnomaly"
    assert lines[0] == expected_header, f"Header mismatch. Expected: {expected_header}, Got: {lines[0]}"

    assert len(lines) - 1 == len(expected), \
        f"Row count mismatch. Expected {len(expected)} rows of data, got {len(lines) - 1}."

    for i, exp in enumerate(expected):
        assert lines[i+1] == exp, \
            f"Data mismatch at line {i+2}.\nExpected: {exp}\nGot:      {lines[i+1]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

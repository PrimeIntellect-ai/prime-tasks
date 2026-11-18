#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import math
import subprocess
import pytest

RAW_DATA_PATH = '/home/user/raw_sensor.csv'
CLEAN_DATA_PATH = '/home/user/clean_data.csv'
REPORT_PATH = '/home/user/report.txt'
VENV_PATH = '/home/user/venv'
PROCESS_SCRIPT_PATH = '/home/user/process.py'

def test_venv_and_packages():
    """Verify virtual environment exists and pandas/scipy are installed."""
    assert os.path.exists(VENV_PATH), f"Virtual environment not found at {VENV_PATH}"
    python_bin = os.path.join(VENV_PATH, 'bin', 'python')
    assert os.path.exists(python_bin), f"Python executable not found in venv at {python_bin}"

    # Check if pandas and scipy are importable
    result = subprocess.run([python_bin, '-c', 'import pandas; import scipy'], capture_output=True)
    assert result.returncode == 0, "Failed to import pandas or scipy in the virtual environment. Are they installed?"

def test_process_script_exists():
    """Verify the process script exists."""
    assert os.path.isfile(PROCESS_SCRIPT_PATH), f"Process script not found at {PROCESS_SCRIPT_PATH}"

def compute_expected_data():
    """Helper to compute expected clean data and report values from raw data."""
    if not os.path.exists(RAW_DATA_PATH):
        pytest.fail(f"Raw data file missing: {RAW_DATA_PATH}")

    raw_rows = []
    with open(RAW_DATA_PATH, 'r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            raw_rows.append({
                'timestamp': row['timestamp'],
                'sensor_id': row['sensor_id'],
                'reading': float(row['reading'])
            })

    # Group by sensor_id
    groups = {}
    for r in raw_rows:
        sid = r['sensor_id']
        groups.setdefault(sid, []).append(r['reading'])

    # Compute mean and std (ddof=0)
    stats = {}
    for sid, vals in groups.items():
        n = len(vals)
        mean = sum(vals) / n
        variance = sum((x - mean) ** 2 for x in vals) / n
        std = math.sqrt(variance)
        stats[sid] = {'mean': mean, 'std': std}

    # Filter
    clean_rows = []
    sensor_max = {}
    for r in raw_rows:
        sid = r['sensor_id']
        val = r['reading']
        z = (val - stats[sid]['mean']) / stats[sid]['std']
        if abs(z) <= 3.0:
            clean_rows.append(r)
            if sid not in sensor_max or val > sensor_max[sid]:
                sensor_max[sid] = val

    return len(raw_rows), len(clean_rows), sensor_max.get('1', 0.0), sensor_max.get('2', 0.0), clean_rows

def test_clean_data_csv():
    """Verify the cleaned data CSV matches expected filtering."""
    assert os.path.isfile(CLEAN_DATA_PATH), f"Clean data file not found at {CLEAN_DATA_PATH}"

    _, expected_clean_count, _, _, expected_clean_rows = compute_expected_data()

    actual_clean_rows = []
    with open(CLEAN_DATA_PATH, 'r', newline='') as f:
        reader = csv.DictReader(f)
        for row in reader:
            actual_clean_rows.append({
                'timestamp': row['timestamp'],
                'sensor_id': row['sensor_id'],
                'reading': float(row['reading'])
            })

    assert len(actual_clean_rows) == expected_clean_count, \
        f"Expected {expected_clean_count} rows in clean data, got {len(actual_clean_rows)}"

    # Compare rows (ignoring float precision issues by rounding to 4 decimals or checking exact match if strings)
    for expected, actual in zip(expected_clean_rows, actual_clean_rows):
        assert expected['timestamp'] == actual['timestamp'], "Timestamp mismatch in clean data"
        assert expected['sensor_id'] == actual['sensor_id'], "Sensor ID mismatch in clean data"
        assert math.isclose(expected['reading'], actual['reading'], rel_tol=1e-5), \
            f"Reading mismatch: expected {expected['reading']}, got {actual['reading']}"

def test_report_txt():
    """Verify the report text matches expected format and values."""
    assert os.path.isfile(REPORT_PATH), f"Report file not found at {REPORT_PATH}"

    orig_count, clean_count, s1_max, s2_max, _ = compute_expected_data()

    expected_lines = [
        f"Total original records: {orig_count}",
        f"Total cleaned records: {clean_count}",
        f"Sensor 1 max clean reading: {s1_max:.2f}",
        f"Sensor 2 max clean reading: {s2_max:.2f}"
    ]

    with open(REPORT_PATH, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), \
        f"Expected {len(expected_lines)} lines in report, got {len(actual_lines)}"

    for i, (expected, actual) in enumerate(zip(expected_lines, actual_lines)):
        assert actual == expected, f"Report line {i+1} mismatch. Expected: '{expected}', Got: '{actual}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

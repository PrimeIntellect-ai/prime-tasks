#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import re
import hashlib
import pytest

LOG_FILE = '/home/user/sensor_data.log'
OUTPUT_FILE = '/home/user/processed_coordinates.txt'

def test_output_file_exists():
    assert os.path.exists(OUTPUT_FILE), f"Output file {OUTPUT_FILE} is missing."
    assert os.path.isfile(OUTPUT_FILE), f"{OUTPUT_FILE} is not a file."

def test_processed_coordinates_correctness():
    assert os.path.exists(LOG_FILE), f"Log file {LOG_FILE} is missing, cannot validate."

    with open(LOG_FILE, 'r') as f:
        log_content = f.read()

    # Regex to extract the exact coordinate string and its numeric components
    pattern = r'\{x:\s*([+-]?\d+(?:\.\d+)?),\s*y:\s*([+-]?\d+(?:\.\d+)?),\s*z:\s*([+-]?\d+(?:\.\d+)?)\}'
    matches = re.finditer(pattern, log_content)

    unique_coords = {}
    for match in matches:
        coord_str = match.group(0)
        x, y, z = float(match.group(1)), float(match.group(2)), float(match.group(3))
        r2 = x**2 + y**2 + z**2
        hash_hex = hashlib.sha256(coord_str.encode('utf-8')).hexdigest()
        if hash_hex not in unique_coords:
            unique_coords[hash_hex] = r2

    # Sort by R^2 descending
    expected_sorted = sorted(unique_coords.items(), key=lambda item: item[1], reverse=True)

    assert os.path.exists(OUTPUT_FILE), f"Output file {OUTPUT_FILE} is missing."
    with open(OUTPUT_FILE, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(expected_sorted), (
        f"Expected {len(expected_sorted)} deduplicated coordinates, but found {len(lines)} lines in output. "
        "Ensure deduplication is working correctly."
    )

    for i, (line, (exp_hash, exp_r2)) in enumerate(zip(lines, expected_sorted)):
        parts = line.split()
        assert len(parts) == 2, f"Line {i+1} is malformed. Expected format '<hash> <r2>', got: '{line}'"

        act_hash, act_r2_str = parts

        assert act_hash == exp_hash, (
            f"Line {i+1}: Hash mismatch or incorrect sorting. "
            f"Expected hash {exp_hash} (for R^2 ~ {exp_r2}), got {act_hash}."
        )

        try:
            act_r2 = float(act_r2_str)
        except ValueError:
            pytest.fail(f"Line {i+1}: Could not parse R^2 value '{act_r2_str}' as a number.")

        assert abs(act_r2 - exp_r2) < 1e-6, (
            f"Line {i+1}: R^2 value mismatch. Expected approx {exp_r2}, got {act_r2}."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

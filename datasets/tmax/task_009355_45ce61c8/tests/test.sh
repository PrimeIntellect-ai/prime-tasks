#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import math
import re
import pytest

def test_output_file_exists():
    """Test that the output.txt file exists."""
    output_path = "/home/user/output.txt"
    assert os.path.isfile(output_path), f"Missing output file: {output_path}"

def test_output_contents():
    """Test that output.txt contains the correct results based on data.csv."""
    data_path = "/home/user/data.csv"
    output_path = "/home/user/output.txt"

    assert os.path.isfile(data_path), f"Missing dataset file: {data_path}"
    assert os.path.isfile(output_path), f"Missing output file: {output_path}"

    # Recompute expected values from data.csv
    W_lin = [0.5, 1.5, -0.5]
    B_lin = 1.0
    W_log = [-1.0, 0.5, 2.0]
    B_log = -0.5

    linear_sum = 0.0
    logistic_pos = 0

    with open(data_path, 'r') as f:
        for line in f:
            parts = line.strip().split(',')
            if len(parts) != 3:
                continue
            x0, x1, x2 = map(float, parts)

            # Linear Regression
            y = W_lin[0]*x0 + W_lin[1]*x1 + W_lin[2]*x2 + B_lin
            linear_sum += y

            # Logistic Regression
            z = W_log[0]*x0 + W_log[1]*x1 + W_log[2]*x2 + B_log
            p = 1.0 / (1.0 + math.exp(-z))
            if p >= 0.5:
                logistic_pos += 1

    expected_sum_str = f"Linear Sum: {linear_sum:.2f}"
    expected_count_str = f"Logistic Positives: {logistic_pos}"

    with open(output_path, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 3, f"output.txt must contain exactly 3 lines, found {len(lines)}"

    assert lines[0] == expected_sum_str, f"Line 1 incorrect. Expected '{expected_sum_str}', got '{lines[0]}'"
    assert lines[1] == expected_count_str, f"Line 2 incorrect. Expected '{expected_count_str}', got '{lines[1]}'"

    time_pattern = re.compile(r"^Benchmark Time: \d+\.\d{4}s$")
    assert time_pattern.match(lines[2]), f"Line 3 format incorrect. Expected 'Benchmark Time: <TIME>s' with 4 decimal places, got '{lines[2]}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math
import pytest

def test_report_file_exists():
    report_path = "/home/user/report.json"
    assert os.path.isfile(report_path), f"The file {report_path} does not exist. The task is incomplete."

def test_report_content():
    report_path = "/home/user/report.json"

    try:
        with open(report_path, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {report_path} does not contain valid JSON.")

    # Check for required keys
    assert "most_similar_pair" in data, "The key 'most_similar_pair' is missing from report.json."
    assert "lr_acc_correlation" in data, "The key 'lr_acc_correlation' is missing from report.json."

    # Validate most_similar_pair
    pair = data["most_similar_pair"]
    assert isinstance(pair, list), "'most_similar_pair' must be a list."
    assert len(pair) == 2, "'most_similar_pair' must contain exactly two experiment IDs."

    # Check that they are sorted alphabetically
    assert pair == sorted(pair), "'most_similar_pair' must be sorted alphabetically."

    # Check exact match
    expected_pair = ["exp_A", "exp_B"]
    assert pair == expected_pair, f"Expected 'most_similar_pair' to be {expected_pair}, but got {pair}."

    # Validate lr_acc_correlation
    correlation = data["lr_acc_correlation"]
    assert isinstance(correlation, (int, float)), "'lr_acc_correlation' must be a number."

    expected_correlation = 0.8919
    assert math.isclose(correlation, expected_correlation, abs_tol=0.00015), \
        f"Expected 'lr_acc_correlation' to be approximately {expected_correlation}, but got {correlation}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

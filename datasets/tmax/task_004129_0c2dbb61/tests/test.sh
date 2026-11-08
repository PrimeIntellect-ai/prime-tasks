#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def compute_expected_truth():
    """
    Recompute the expected aggregated data based on the generation script logic.
    """
    expected = {}
    # The generation script creates three files with 10000, 15000, and 20000 lines respectively.
    for lines in [10000, 15000, 20000]:
        for i in range(1, lines + 1):
            # Status logic
            if i % 5 == 0:
                continue  # ERROR
            if i % 7 == 0:
                continue  # WARN

            # OK status
            sensor = f"SENSOR_{i % 3 + 1}"

            # Value logic: $(( (i * 13) % 100 )).$(( i % 10 ))
            val_str = f"{(i * 13) % 100}.{i % 10}"
            val = float(val_str)

            if sensor not in expected:
                expected[sensor] = {"sum": 0.0, "count": 0}

            expected[sensor]["sum"] += val
            expected[sensor]["count"] += 1

    # Round sums to 2 decimal places as per instructions
    for sensor in expected:
        expected[sensor]["sum"] = round(expected[sensor]["sum"], 2)

    return expected

def test_results_directory_exists():
    """Check if the results directory was created."""
    dir_path = "/home/user/results"
    assert os.path.isdir(dir_path), f"Expected directory {dir_path} to exist."

def test_summary_json_exists():
    """Check if the summary.json file exists."""
    file_path = "/home/user/results/summary.json"
    assert os.path.isfile(file_path), f"Expected file {file_path} to exist."

def test_summary_json_content():
    """Check if the summary.json contains the correct aggregated data."""
    file_path = "/home/user/results/summary.json"

    with open(file_path, "r") as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} does not contain valid JSON.")

    expected_data = compute_expected_truth()

    # Check that the keys match
    assert set(actual_data.keys()) == set(expected_data.keys()), \
        f"Expected sensors {list(expected_data.keys())}, but got {list(actual_data.keys())}."

    # Check counts and sums
    for sensor, expected_stats in expected_data.items():
        actual_stats = actual_data[sensor]

        assert "count" in actual_stats, f"Missing 'count' for {sensor}."
        assert "sum" in actual_stats, f"Missing 'sum' for {sensor}."

        actual_count = actual_stats["count"]
        expected_count = expected_stats["count"]
        assert actual_count == expected_count, \
            f"Incorrect count for {sensor}. Expected {expected_count}, got {actual_count}."

        actual_sum = actual_stats["sum"]
        expected_sum = expected_stats["sum"]
        # Allow small floating point tolerance just in case, though it should match exactly when rounded to 2 decimal places
        assert abs(actual_sum - expected_sum) < 0.011, \
            f"Incorrect sum for {sensor}. Expected {expected_sum}, got {actual_sum}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

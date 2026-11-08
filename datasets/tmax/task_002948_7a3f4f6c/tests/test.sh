#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv

def test_fixed_variances_file_exists():
    file_path = "/home/user/fixed_variances.csv"
    assert os.path.isfile(file_path), f"The output file {file_path} does not exist."

def test_fixed_variances_content():
    file_path = "/home/user/fixed_variances.csv"

    expected_results = {
        "101": "0.025000",
        "105": "0.000100",
        "110": "0.000667"
    }

    actual_results = {}
    with open(file_path, "r", newline="") as f:
        reader = csv.reader(f)
        for row in reader:
            if not row:
                continue
            assert len(row) == 2, f"Invalid row format in CSV: {row}. Expected 2 columns."
            job_id, variance = row
            actual_results[job_id.strip()] = variance.strip()

    assert len(actual_results) == len(expected_results), (
        f"Expected {len(expected_results)} rows in {file_path}, but found {len(actual_results)}."
    )

    for job_id, expected_var in expected_results.items():
        assert job_id in actual_results, f"Job ID {job_id} is missing from the output."
        actual_var = actual_results[job_id]

        # Check exact string match to ensure 6 decimal places formatting
        assert actual_var == expected_var, (
            f"Incorrect variance for Job {job_id}. "
            f"Expected {expected_var}, got {actual_var}."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

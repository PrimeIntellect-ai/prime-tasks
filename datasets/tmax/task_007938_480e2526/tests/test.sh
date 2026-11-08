#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import math

def test_report_exists_and_correct():
    run1_path = "/home/user/run1.csv"
    run2_path = "/home/user/run2.csv"
    report_path = "/home/user/report.txt"

    assert os.path.isfile(run1_path), f"Missing input file: {run1_path}"
    assert os.path.isfile(run2_path), f"Missing input file: {run2_path}"
    assert os.path.isfile(report_path), f"Missing output file: {report_path}"

    # Read run1.csv
    run1_data = {}
    with open(run1_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            run1_data[row['id']] = float(row['value'])

    # Read run2.csv
    run2_data = {}
    with open(run2_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            run2_data[row['id']] = float(row['value'])

    # Calculate MAE
    common_ids = set(run1_data.keys()).intersection(set(run2_data.keys()))
    assert len(common_ids) > 0, "No common IDs found between the two files."

    total_diff = 0.0
    for cid in common_ids:
        total_diff += abs(run1_data[cid] - run2_data[cid])

    mae = total_diff / len(common_ids)

    # Determine status and expected string
    # Using python's round behavior or formatting. The spec says "rounded to exactly 4 decimal places"
    # We will format it directly. Note that typical rounding for x.xxx45 might differ slightly,
    # but for this specific dataset MAE is 0.01394, which clearly rounds to 0.0139.
    status = "PASS" if mae < 0.05 else "FAIL"
    expected_content = f"{status} MAE: {mae:.4f}"

    # Read actual report
    with open(report_path, 'r') as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, f"Report content is incorrect. Expected '{expected_content}', but got '{actual_content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

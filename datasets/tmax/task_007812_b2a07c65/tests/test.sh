#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

def test_campaign_posteriors_csv():
    file_path = "/home/user/campaign_posteriors.csv"
    assert os.path.exists(file_path), f"Output file {file_path} is missing."

    expected_rows = [
        ['campaign_id', 'posterior_mean', 'lower_95', 'upper_95'],
        ['C001', '0.1049', '0.0635', '0.1560'],
        ['C003', '0.1502', '0.1305', '0.1709'],
        ['C004', '0.0519', '0.0343', '0.0734'],
        ['C006', '0.1416', '0.1066', '0.1813']
    ]

    with open(file_path, 'r', newline='') as f:
        reader = csv.reader(f)
        actual_rows = list(reader)

    assert len(actual_rows) > 0, f"File {file_path} is empty."

    # Check header
    assert actual_rows[0] == expected_rows[0], f"Header in {file_path} is incorrect. Expected {expected_rows[0]}, got {actual_rows[0]}."

    # Check data rows
    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows) - 1} data rows, but got {len(actual_rows) - 1}."

    for i, (actual, expected) in enumerate(zip(actual_rows[1:], expected_rows[1:]), start=1):
        assert actual == expected, f"Row {i} is incorrect. Expected {expected}, got {actual}. Check sorting and rounding."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

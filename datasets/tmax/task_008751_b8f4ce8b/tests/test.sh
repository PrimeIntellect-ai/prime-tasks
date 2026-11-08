#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

CSV_FILE = "/home/user/drift_metrics.csv"
SCRIPT_FILE = "/home/user/analyze_configs.py"

def test_script_exists():
    assert os.path.isfile(SCRIPT_FILE), f"The script {SCRIPT_FILE} was not found."

def test_csv_exists():
    assert os.path.isfile(CSV_FILE), f"The output file {CSV_FILE} was not found."

def test_csv_content():
    expected_rows = [
        ["Date", "Jaccard_Index"],
        ["20231002", "0.4444"],
        ["20231003", "0.7778"]
    ]

    actual_rows = []
    with open(CSV_FILE, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        for row in reader:
            if row:  # Ignore empty lines if any
                actual_rows.append(row)

    assert actual_rows == expected_rows, f"The content of {CSV_FILE} does not match the expected output. Got {actual_rows}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

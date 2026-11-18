#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

TRAIN_CLEAN_CSV = "/home/user/train_clean.csv"
REPORT_TXT = "/home/user/report.txt"

def test_train_clean_csv_exists():
    assert os.path.isfile(TRAIN_CLEAN_CSV), f"Missing expected output file: {TRAIN_CLEAN_CSV}"

def test_report_txt_exists():
    assert os.path.isfile(REPORT_TXT), f"Missing expected output file: {REPORT_TXT}"

def test_train_clean_csv_content():
    expected_header = "ID,X,Y"
    expected_rows = {
        "1,2.5,4.0",
        "2,3.1,1.5",
        "3,7.0,2.2",
        "5,1.2,8.4",
        "6,9.1,2.0",
        "8,6.0,1.1",
        "9,3.3,3.3",
        "10,8.2,2.5",
        "11,5.0,5.0",
        "13,7.5,1.2",
        "14,4.1,4.2"
    }

    with open(TRAIN_CLEAN_CSV, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) > 0, f"{TRAIN_CLEAN_CSV} is empty"
    assert lines[0] == expected_header, f"{TRAIN_CLEAN_CSV} has incorrect header. Expected '{expected_header}', got '{lines[0]}'"

    actual_rows = set(lines[1:])

    missing_rows = expected_rows - actual_rows
    extra_rows = actual_rows - expected_rows

    assert not missing_rows, f"{TRAIN_CLEAN_CSV} is missing expected rows: {missing_rows}"
    assert not extra_rows, f"{TRAIN_CLEAN_CSV} contains unexpected rows: {extra_rows}"
    assert len(lines[1:]) == len(expected_rows), f"{TRAIN_CLEAN_CSV} has duplicate rows"

def test_report_txt_content():
    expected_lines = [
        "Leaked IDs: 4",
        "Clean Sum of Products: 147.54"
    ]

    with open(REPORT_TXT, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 2, f"{REPORT_TXT} should contain exactly 2 lines (ignoring empty lines)"
    assert lines[0] == expected_lines[0], f"First line of {REPORT_TXT} is incorrect. Expected '{expected_lines[0]}', got '{lines[0]}'"
    assert lines[1] == expected_lines[1], f"Second line of {REPORT_TXT} is incorrect. Expected '{expected_lines[1]}', got '{lines[1]}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

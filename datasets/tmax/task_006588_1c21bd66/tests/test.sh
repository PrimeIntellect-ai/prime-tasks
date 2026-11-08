#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

ANALYSIS_DIR = "/home/user/analysis"
VALID_DIR = os.path.join(ANALYSIS_DIR, "valid")
INVALID_DIR = os.path.join(ANALYSIS_DIR, "invalid")

COMBINED_CSV = os.path.join(VALID_DIR, "combined.csv")
REJECTED_CSV = os.path.join(INVALID_DIR, "rejected.csv")
SUMMARY_TSV = os.path.join(ANALYSIS_DIR, "summary.tsv")

EXPECTED_VALID_ROWS = {
    "1,heat,0.85,SUCCESS",
    "2,cold,0.12,SUCCESS",
    "5,acid,0.99,SUCCESS",
    "6,heat,0.65,SUCCESS",
    "7,cold,0.88,SUCCESS",
    "8,acid,0.45,SUCCESS"
}

EXPECTED_INVALID_ROWS = {
    "3,heat,1.50,SUCCESS",
    "4,acid,-0.10,ERROR",
    "9,cold,0.50,ERROR"
}

EXPECTED_SUMMARY = [
    "acid\t0.72",
    "cold\t0.50",
    "heat\t0.75"
]

def test_directory_structure():
    assert os.path.isdir(ANALYSIS_DIR), f"Directory {ANALYSIS_DIR} is missing."
    assert os.path.isdir(VALID_DIR), f"Directory {VALID_DIR} is missing."
    assert os.path.isdir(INVALID_DIR), f"Directory {INVALID_DIR} is missing."

def test_combined_csv():
    assert os.path.isfile(COMBINED_CSV), f"File {COMBINED_CSV} is missing."
    with open(COMBINED_CSV, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert set(lines) == EXPECTED_VALID_ROWS, f"Contents of {COMBINED_CSV} do not match the expected valid rows."
    assert len(lines) == len(EXPECTED_VALID_ROWS), f"Duplicate rows or incorrect row count in {COMBINED_CSV}."

def test_rejected_csv():
    assert os.path.isfile(REJECTED_CSV), f"File {REJECTED_CSV} is missing."
    with open(REJECTED_CSV, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert set(lines) == EXPECTED_INVALID_ROWS, f"Contents of {REJECTED_CSV} do not match the expected invalid rows."
    assert len(lines) == len(EXPECTED_INVALID_ROWS), f"Duplicate rows or incorrect row count in {REJECTED_CSV}."

def test_summary_tsv():
    assert os.path.isfile(SUMMARY_TSV), f"File {SUMMARY_TSV} is missing."
    with open(SUMMARY_TSV, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines == EXPECTED_SUMMARY, f"Contents of {SUMMARY_TSV} do not match expected aggregated results or are not sorted correctly."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

def test_c_source_file_exists():
    source_path = "/home/user/extract_centrality.c"
    assert os.path.isfile(source_path), f"C source file is missing: {source_path}"

def test_compiled_binary_exists():
    binary_path = "/home/user/extract_centrality"
    assert os.path.isfile(binary_path), f"Compiled binary is missing: {binary_path}"
    assert os.access(binary_path, os.X_OK), f"File at {binary_path} is not executable"

def test_output_csv_exists():
    csv_path = "/home/user/out_degree.csv"
    assert os.path.isfile(csv_path), f"Output CSV file is missing: {csv_path}"

def test_output_csv_contents():
    csv_path = "/home/user/out_degree.csv"
    assert os.path.isfile(csv_path), f"Output CSV file is missing: {csv_path}"

    expected_rows = [
        ["node_id", "out_degree"],
        ["104", "4"],
        ["101", "3"],
        ["100", "2"],
        ["102", "2"]
    ]

    actual_rows = []
    with open(csv_path, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        for row in reader:
            if row:  # skip empty lines if any
                actual_rows.append(row)

    assert actual_rows == expected_rows, (
        f"CSV contents do not match expected output.\n"
        f"Expected: {expected_rows}\n"
        f"Actual: {actual_rows}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

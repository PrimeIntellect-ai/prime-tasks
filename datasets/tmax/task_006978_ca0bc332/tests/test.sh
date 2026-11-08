#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv

def test_summary_csv_exists():
    """Verify that the dataset_summary.csv file has been created."""
    path = "/home/user/dataset_summary.csv"
    assert os.path.exists(path), f"{path} is missing. Did you generate the summary file?"
    assert os.path.isfile(path), f"{path} is not a valid file."

def test_summary_csv_content():
    """Verify that the contents of dataset_summary.csv match the expected output."""
    expected_file = "/tests/expected_summary.csv"
    actual_file = "/home/user/dataset_summary.csv"

    assert os.path.exists(expected_file), f"Verifier file {expected_file} is missing."
    assert os.path.exists(actual_file), f"Task output file {actual_file} is missing."

    with open(expected_file, 'r', encoding='utf-8') as f:
        expected_lines = [line.strip() for line in f.readlines() if line.strip()]

    with open(actual_file, 'r', encoding='utf-8') as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(actual_lines) > 0, f"{actual_file} is empty."

    # Check header
    assert actual_lines[0] == "filename,type,metadata", "The CSV header is incorrect."

    # Check contents
    assert actual_lines == expected_lines, (
        f"The contents of {actual_file} do not match the expected output.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )

def test_dataset_directory_exists():
    """Verify that the dataset was extracted to the correct directory."""
    path = "/home/user/dataset"
    assert os.path.exists(path), f"{path} directory is missing. Did you extract the tarball correctly?"
    assert os.path.isdir(path), f"{path} should be a directory."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

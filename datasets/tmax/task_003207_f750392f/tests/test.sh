#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import pytest

SCRIPT_PATH = "/home/user/generate_report.sh"
CSV_PATH = "/home/user/team_sales_report.csv"

EXPECTED_CSV = """Employee Name,Department Name,Personal Sales,Total Team Sales
Alice,Executive,0,570
Bob,Sales,100,550
Charlie,Sales,50,450
Dave,Sales,250,250
Eve,Sales,150,150
Frank,Marketing,0,20
Grace,Marketing,20,20
Heidi,Engineering,0,0"""

def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script missing at {SCRIPT_PATH}"
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script at {SCRIPT_PATH} is not executable"

def test_script_execution_and_output():
    # Execute the script to ensure it generates the output
    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"Script execution failed with error:\n{result.stderr}"

    # Check if CSV was generated
    assert os.path.isfile(CSV_PATH), f"CSV file missing at {CSV_PATH}"

    # Read and compare CSV contents
    with open(CSV_PATH, "r") as f:
        actual_csv = f.read().strip()

    expected_csv_stripped = EXPECTED_CSV.strip()

    # Compare lines to give a clear diff in case of failure
    actual_lines = actual_csv.splitlines()
    expected_lines = expected_csv_stripped.splitlines()

    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in CSV, but got {len(actual_lines)}."
    )

    for i, (actual_line, expected_line) in enumerate(zip(actual_lines, expected_lines)):
        assert actual_line == expected_line, (
            f"Mismatch at line {i + 1}:\n"
            f"Expected: {expected_line}\n"
            f"Actual:   {actual_line}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

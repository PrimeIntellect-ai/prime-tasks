#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import csv

def test_script_exists_and_executable():
    script_path = "/home/user/analyze_network.sh"
    assert os.path.exists(script_path), f"Script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"Script {script_path} is not executable."

def test_script_execution_and_output():
    script_path = "/home/user/analyze_network.sh"
    output_path = "/home/user/flagged_paths.csv"

    # Remove output if it exists to ensure the script generates it dynamically
    if os.path.exists(output_path):
        os.remove(output_path)

    result = subprocess.run([script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed to execute. Return code: {result.returncode}. stderr: {result.stderr}"

    assert os.path.exists(output_path), f"Output file {output_path} was not created by the script."

    with open(output_path, "r") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "Output CSV is empty."

    expected_header = ["region", "start_node", "mid_node", "end_node", "total_amount", "region_rank"]
    assert rows[0] == expected_header, f"Header mismatch. Expected {expected_header}, got {rows[0]}"

    expected_data = {
        ("NA", "7", "8", "9", 11000.0, "1"),
        ("EU", "1", "5", "6", 5000.0, "1"),
        ("EU", "4", "5", "6", 3100.0, "2"),
        ("EU", "4", "2", "3", 1800.0, "3"),
        ("APAC", "10", "11", "12", 1000.0, "1")
    }

    actual_data = set()
    for row in rows[1:]:
        assert len(row) == 6, f"Row does not have 6 columns: {row}"
        try:
            amount = float(row[4])
        except ValueError:
            amount = None

        actual_data.add((row[0], row[1], row[2], row[3], amount, row[5]))

    assert actual_data == expected_data, f"Data mismatch.\nExpected: {expected_data}\nGot: {actual_data}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import gzip
import pytest

DUMP_PATH = "/home/user/robot_dump.log.gz"
GCODE_DIR = "/home/user/archived_gcode"
CSV_PATH = "/home/user/critical_errors.csv"

def get_expected_data():
    expected_csv_lines = []
    expected_gcode_blocks = []

    with gzip.open(DUMP_PATH, 'rt') as f:
        in_gcode = False
        current_gcode = []
        for line in f:
            stripped = line.strip()

            # Handle GCode blocks
            if stripped == "[GCODE_START]":
                in_gcode = True
                current_gcode = []
                continue
            elif stripped == "[GCODE_END]":
                in_gcode = False
                expected_gcode_blocks.append("\n".join(current_gcode))
                continue

            if in_gcode:
                current_gcode.append(stripped)

            # Handle CRITICAL logs
            if " CRITICAL " in line:
                # The timestamp is the first word, the message is everything after " CRITICAL "
                parts = line.split(" CRITICAL ", 1)
                if len(parts) == 2:
                    timestamp = parts[0].split()[0]
                    message = parts[1].strip()
                    expected_csv_lines.append(f"{timestamp},{message}")

    return expected_csv_lines, expected_gcode_blocks

def test_archived_gcode_directory_exists():
    assert os.path.exists(GCODE_DIR), f"Directory {GCODE_DIR} does not exist."
    assert os.path.isdir(GCODE_DIR), f"{GCODE_DIR} is not a directory."

def test_critical_errors_csv():
    expected_csv_lines, _ = get_expected_data()

    assert os.path.exists(CSV_PATH), f"CSV file {CSV_PATH} does not exist."
    assert os.path.isfile(CSV_PATH), f"{CSV_PATH} is not a file."

    with open(CSV_PATH, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_csv_lines, "The contents of the CSV file do not match the expected critical errors."

def test_gcode_files():
    _, expected_gcode_blocks = get_expected_data()

    assert os.path.exists(GCODE_DIR) and os.path.isdir(GCODE_DIR), f"Directory {GCODE_DIR} is missing."

    actual_files = [f for f in os.listdir(GCODE_DIR) if os.path.isfile(os.path.join(GCODE_DIR, f))]
    expected_filenames = [f"job_{i+1}.gcode" for i in range(len(expected_gcode_blocks))]

    # Check that the exact expected files are present
    assert set(actual_files) == set(expected_filenames), f"Expected files {expected_filenames} in {GCODE_DIR}, but found {actual_files}."

    for i, expected_block in enumerate(expected_gcode_blocks):
        filename = f"job_{i+1}.gcode"
        filepath = os.path.join(GCODE_DIR, filename)

        with open(filepath, 'r') as f:
            actual_content = f.read().strip()

        assert actual_content == expected_block, f"The contents of {filename} do not match the expected GCode block."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

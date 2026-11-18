#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_filtered_extrusion_file():
    expected_lines = [
        "G1 X20 Y20 E0.3",
        "G1 X10 Y20 E0.4",
        "G1 X5 Y5 E0.5",
        "G1 X15 Y15 E0.7"
    ]
    file_path = "/home/user/dataset/filtered_extrusion.gcode"
    assert os.path.exists(file_path), f"File {file_path} does not exist. The script must create this file."

    with open(file_path, "r") as f:
        lines = f.read().splitlines()

    # Strip any trailing whitespace as required by the prompt
    lines = [line.rstrip() for line in lines]
    # Ignore trailing blank lines if present
    while lines and not lines[-1]:
        lines.pop()

    assert lines == expected_lines, f"Content of {file_path} is incorrect. Expected {expected_lines}, got {lines}."

def test_summary_file():
    file_path = "/home/user/dataset/summary.txt"
    assert os.path.exists(file_path), f"File {file_path} does not exist. The script must create this file."

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content == "4", f"Content of {file_path} is incorrect. Expected '4', got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

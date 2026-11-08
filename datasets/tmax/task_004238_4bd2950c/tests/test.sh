#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_analysis_result_exists():
    """Check if the analysis result file was created."""
    file_path = "/home/user/analysis_result.txt"
    assert os.path.isfile(file_path), f"The file {file_path} was not created."

def test_analysis_result_contents():
    """Verify the contents of the analysis result file."""
    file_path = "/home/user/analysis_result.txt"
    assert os.path.isfile(file_path), f"The file {file_path} does not exist."

    with open(file_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "Total_MW: 75900.0",
        "Max_Abs_Derivative: 90.0",
        "Dominant_Freq_Index: 300"
    ]

    assert len(lines) == 3, f"Expected exactly 3 lines of output, found {len(lines)}."

    for i, expected in enumerate(expected_lines):
        assert lines[i] == expected, f"Line {i+1} mismatch. Expected '{expected}', got '{lines[i]}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_invalid_lines_recorded():
    file_path = "/home/user/invalid_lines.txt"
    assert os.path.isfile(file_path), f"Expected output file {file_path} is missing."

    with open(file_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = ["2", "5"]
    assert lines == expected_lines, f"Expected invalid line numbers {expected_lines}, but got {lines}."

def test_rolling_averages_output():
    file_path = "/home/user/rolling_averages.jsonl"
    assert os.path.isfile(file_path), f"Expected output file {file_path} is missing."

    parsed_lines = []
    with open(file_path, "r") as f:
        for i, line in enumerate(f):
            if not line.strip():
                continue
            try:
                parsed_lines.append(json.loads(line))
            except json.JSONDecodeError:
                pytest.fail(f"Line {i+1} in {file_path} is not valid JSON.")

    expected_output = [
        {"valid_index": 0, "rolling_avg": 10.0},
        {"valid_index": 1, "rolling_avg": 12.5},
        {"valid_index": 2, "rolling_avg": 18.33},
        {"valid_index": 3, "rolling_avg": 19.0},
        {"valid_index": 4, "rolling_avg": 20.0}
    ]

    assert len(parsed_lines) == len(expected_output), f"Expected {len(expected_output)} valid records, but got {len(parsed_lines)}."

    for i, (actual, expected) in enumerate(zip(parsed_lines, expected_output)):
        assert actual == expected, f"Mismatch at valid_index {i}. Expected {expected}, got {actual}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

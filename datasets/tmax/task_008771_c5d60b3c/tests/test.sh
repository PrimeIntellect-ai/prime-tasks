#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_result_file_exists():
    file_path = "/home/user/result.txt"
    assert os.path.exists(file_path), f"File {file_path} is missing. The task requires creating this file."

def test_result_file_content():
    file_path = "/home/user/result.txt"
    assert os.path.exists(file_path), f"File {file_path} is missing."

    with open(file_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {file_path}, but found {len(lines)}."

    expected_line_1 = "SRV-003"
    expected_line_2 = "SRV-001"

    assert lines[0] == expected_line_1, f"Expected first line to be '{expected_line_1}', but got '{lines[0]}'. This should be the server with the highest failure score."
    assert lines[1] == expected_line_2, f"Expected second line to be '{expected_line_2}', but got '{lines[1]}'. This should be the server most similar to SRV-999."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

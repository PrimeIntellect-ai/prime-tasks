#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

RESULT_PATH = '/home/user/path_result.txt'

def test_result_file_exists():
    assert os.path.exists(RESULT_PATH), f"Result file {RESULT_PATH} does not exist."
    assert os.path.isfile(RESULT_PATH), f"{RESULT_PATH} is not a file."

def test_result_file_content():
    with open(RESULT_PATH, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 2, f"Result file {RESULT_PATH} should contain at least two lines."

    expected_path = "AlphaCore,NodeD,NodeE,OmegaRelay"
    expected_weight = "17"

    assert lines[0] == expected_path, f"Line 1 is incorrect. Expected '{expected_path}', got '{lines[0]}'."
    assert lines[1] == expected_weight, f"Line 2 is incorrect. Expected '{expected_weight}', got '{lines[1]}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

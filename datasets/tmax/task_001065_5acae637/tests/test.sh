#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_result_file_exists():
    path = "/home/user/result.txt"
    assert os.path.isfile(path), f"Missing expected output file: {path}"

def test_result_accuracy():
    path = "/home/user/result.txt"
    with open(path, "r") as f:
        content = f.read().strip()

    assert content, f"File {path} is empty."

    try:
        agent_val = float(content)
    except ValueError:
        pytest.fail(f"Could not parse the content of {path} as a float. Content: '{content}'")

    truth = 35.0
    error = abs(agent_val - truth)
    threshold = 0.01

    assert error <= threshold, f"Agent value {agent_val} differs from truth {truth} by {error}, which exceeds the threshold of {threshold}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

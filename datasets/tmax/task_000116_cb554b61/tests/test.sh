#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pytest

def test_redacted_logs_accuracy():
    expected_path = "/tests/hidden_expected_logs.txt"
    actual_path = "/home/user/redacted_logs.txt"

    assert os.path.isfile(expected_path), f"Missing reference file: {expected_path}"
    assert os.path.isfile(actual_path), f"Missing output file: {actual_path}. Did you create the output file at the specified path?"

    with open(expected_path, "r") as f:
        expected = f.read().splitlines()

    with open(actual_path, "r") as f:
        actual = f.read().splitlines()

    assert len(expected) > 0, "Reference file is empty."
    assert len(actual) > 0, "Output file is empty."

    correct = 0
    for i in range(min(len(expected), len(actual))):
        if expected[i] == actual[i]:
            correct += 1

    accuracy = correct / len(expected)

    assert accuracy >= 0.95, f"Accuracy {accuracy:.4f} is below the 0.95 threshold. Correct matching lines: {correct}/{len(expected)}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

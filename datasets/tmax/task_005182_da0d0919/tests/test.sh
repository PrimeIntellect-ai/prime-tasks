#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_redacted_logs_accuracy():
    agent_file = "/home/user/redacted_logs.txt"
    expected_file = "/app/.hidden/expected_logs.txt"

    assert os.path.isfile(agent_file), f"Agent output file missing: {agent_file}"
    assert os.path.isfile(expected_file), f"Expected truth file missing: {expected_file}"

    with open(agent_file, 'r', encoding='utf-8') as f1, open(expected_file, 'r', encoding='utf-8') as f2:
        agent_lines = f1.readlines()
        expected_lines = f2.readlines()

    assert len(agent_lines) == len(expected_lines), (
        f"Line count mismatch: expected {len(expected_lines)}, got {len(agent_lines)}"
    )

    if not expected_lines:
        pytest.skip("Expected logs file is empty.")

    correct = sum(1 for a, e in zip(agent_lines, expected_lines) if a == e)
    accuracy = correct / len(expected_lines)

    assert accuracy >= 0.99, (
        f"Redaction accuracy too low: {accuracy:.4f} (Target >= 0.99). "
        f"Matched {correct} out of {len(expected_lines)} lines."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

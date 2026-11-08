#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def test_summary_mse():
    agent_path = "/home/user/summary.txt"
    truth_path = "/tests/golden_summary.txt"

    assert os.path.isfile(agent_path), f"Agent output file missing: {agent_path}"
    assert os.path.isfile(truth_path), f"Golden truth file missing: {truth_path}"

    with open(agent_path, 'r') as f:
        try:
            agent_lines = [float(x.strip()) for x in f.readlines() if x.strip()]
        except ValueError:
            pytest.fail("Agent output contains non-float values.")

    with open(truth_path, 'r') as f:
        truth_lines = [float(x.strip()) for x in f.readlines() if x.strip()]

    assert len(agent_lines) == 2, f"Agent output must contain exactly 2 lines, found {len(agent_lines)}"
    assert len(truth_lines) == 2, "Golden truth file is corrupted."

    mse = sum((a - t)**2 for a, t in zip(agent_lines, truth_lines)) / 2.0

    assert mse <= 0.001, f"MSE {mse} exceeds threshold 0.001. Agent lines: {agent_lines}, Truth lines: {truth_lines}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

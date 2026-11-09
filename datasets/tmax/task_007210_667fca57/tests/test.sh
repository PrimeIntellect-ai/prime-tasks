#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_corrupted_runs_file():
    filepath = "/home/user/corrupted_runs.txt"
    assert os.path.isfile(filepath), f"File {filepath} does not exist. You must create it."

    with open(filepath, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_runs = ["RUN-002", "RUN-004", "RUN-005"]
    assert lines == expected_runs, f"Contents of {filepath} are incorrect. Expected {expected_runs}, got {lines}."

def test_closest_issue_file():
    filepath = "/home/user/closest_issue.txt"
    assert os.path.isfile(filepath), f"File {filepath} does not exist. You must create it."

    with open(filepath, 'r') as f:
        content = f.read().strip()

    expected_run = "RUN-004"
    assert content == expected_run, f"Contents of {filepath} are incorrect. Expected '{expected_run}', got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_cycle_tasks_output():
    filepath = "/home/user/cycle_tasks.txt"
    assert os.path.isfile(filepath), f"Expected output file {filepath} does not exist."

    expected_tasks = [
        "AggregateMetrics",
        "JoinData",
        "TransformUsers"
    ]

    with open(filepath, "r") as f:
        content = f.read().splitlines()

    # Strip any trailing whitespace from lines just in case
    content = [line.strip() for line in content if line.strip()]

    assert content == expected_tasks, (
        f"Contents of {filepath} do not match the expected output.\n"
        f"Expected: {expected_tasks}\n"
        f"Got: {content}"
    )

def test_deadlocked_descriptions_output():
    filepath = "/home/user/deadlocked_descriptions.txt"
    assert os.path.isfile(filepath), f"Expected output file {filepath} does not exist."

    expected_descriptions = [
        "Calculates daily metrics",
        "Cleans user data",
        "Joins users and orders"
    ]

    with open(filepath, "r") as f:
        content = f.read().splitlines()

    # Strip any trailing whitespace from lines just in case
    content = [line.strip() for line in content if line.strip()]

    assert content == expected_descriptions, (
        f"Contents of {filepath} do not match the expected output.\n"
        f"Expected: {expected_descriptions}\n"
        f"Got: {content}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

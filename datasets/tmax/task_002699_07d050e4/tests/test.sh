#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

SHORTEST_PATH_FILE = '/home/user/shortest_path.txt'
INFLUENCED_FILE = '/home/user/influenced_by_1.txt'

def test_shortest_path_file():
    """Check if the shortest_path.txt file exists and has the correct content."""
    assert os.path.isfile(SHORTEST_PATH_FILE), f"File not found: {SHORTEST_PATH_FILE}"

    with open(SHORTEST_PATH_FILE, 'r') as f:
        content = f.read().strip()

    expected_path = "100,6,4,1"
    assert content == expected_path, f"Expected shortest path '{expected_path}', but got '{content}'"

def test_influenced_by_1_file():
    """Check if the influenced_by_1.txt file exists and has the correct content."""
    assert os.path.isfile(INFLUENCED_FILE), f"File not found: {INFLUENCED_FILE}"

    with open(INFLUENCED_FILE, 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = ["2", "3", "4", "5", "6", "7", "100"]
    assert lines == expected_lines, f"Expected influenced IDs {expected_lines}, but got {lines}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

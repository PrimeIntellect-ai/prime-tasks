#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def test_solution_file():
    solution_path = '/home/user/solution.txt'
    assert os.path.exists(solution_path), "The solution file /home/user/solution.txt does not exist."

    with open(solution_path, 'r') as f:
        content = f.read().strip()

    expected = "2023-10-01T10:03:00Z cache service 4"
    assert content == expected, f"Expected the solution file to contain '{expected}', but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

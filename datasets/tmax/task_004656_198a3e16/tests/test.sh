#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

TOP_LONGEST_PATH = "/home/user/top_longest.csv"
DEPENDENCIES_PATH = "/home/user/upstream_dependencies.txt"

def test_top_longest_csv():
    """Check if top_longest.csv exists and has the correct content."""
    assert os.path.isfile(TOP_LONGEST_PATH), f"File not found: {TOP_LONGEST_PATH}"

    with open(TOP_LONGEST_PATH, "r") as f:
        content = f.read().strip()

    expected_lines = [
        "cache-prod,9,120",
        "cache-prod,8,100",
        "db-prod,2,1500",
        "db-prod,1,1000",
        "web-prod,6,600",
        "web-prod,5,500"
    ]

    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert actual_lines == expected_lines, (
        f"Content of {TOP_LONGEST_PATH} is incorrect.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )

def test_upstream_dependencies_txt():
    """Check if upstream_dependencies.txt exists and has the correct content."""
    assert os.path.isfile(DEPENDENCIES_PATH), f"File not found: {DEPENDENCIES_PATH}"

    with open(DEPENDENCIES_PATH, "r") as f:
        content = f.read().strip()

    expected_content = "2,4,11,13"

    assert content == expected_content, (
        f"Content of {DEPENDENCIES_PATH} is incorrect.\n"
        f"Expected: {expected_content}\n"
        f"Actual: {content}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

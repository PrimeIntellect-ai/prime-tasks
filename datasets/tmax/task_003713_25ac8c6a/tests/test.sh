#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_change_metrics_exists():
    assert os.path.isfile("/home/user/change_metrics.csv"), "The output file /home/user/change_metrics.csv does not exist."

def test_change_metrics_content():
    expected_lines = [
        "transition,changes,rolling_avg",
        "v1-v2,2,2.0",
        "v2-v3,3,2.5",
        "v3-v4,3,3.0"
    ]

    with open("/home/user/change_metrics.csv", "r", encoding="utf-8") as f:
        content = f.read().strip().splitlines()

    assert len(content) == len(expected_lines), f"Expected {len(expected_lines)} lines in change_metrics.csv, but found {len(content)}."

    for i, (actual, expected) in enumerate(zip(content, expected_lines)):
        assert actual.strip() == expected, f"Line {i+1} of change_metrics.csv is incorrect. Expected '{expected}', got '{actual.strip()}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

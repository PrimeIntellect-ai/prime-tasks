#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_graph_stats_csv_exists():
    """Test that /home/user/graph_stats.csv exists."""
    file_path = "/home/user/graph_stats.csv"
    assert os.path.isfile(file_path), f"Output file {file_path} was not created."

def test_graph_stats_csv_content():
    """Test that /home/user/graph_stats.csv has the correct computed metrics."""
    file_path = "/home/user/graph_stats.csv"
    assert os.path.isfile(file_path), f"Output file {file_path} was not created."

    expected_lines = [
        "node_id,department,out_degree,total_bytes,rank,cumulative_bytes",
        "A,Sales,3,500,1,500",
        "D,Engineering,3,500,2,1000",
        "B,Engineering,2,700,3,1700",
        "E,Sales,1,400,4,2100",
        "C,HR,1,50,5,2150"
    ]

    with open(file_path, "r") as f:
        actual_content = f.read().strip()

    actual_lines = [line.strip() for line in actual_content.splitlines() if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} rows, but got {len(actual_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Row {i+1} mismatch. Expected: '{expected}', Got: '{actual}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import subprocess
import pytest

def test_analyze_graph_script_exists():
    assert os.path.isfile('/home/user/analyze_graph.py'), "The script /home/user/analyze_graph.py does not exist."

def test_script_execution_and_output():
    script_path = '/home/user/analyze_graph.py'
    results_path = '/home/user/results.csv'

    # Remove results.csv if it exists from previous runs
    if os.path.exists(results_path):
        os.remove(results_path)

    # Run the script with threshold 50
    result = subprocess.run(['python3', script_path, '50'], capture_output=True, text=True)
    assert result.returncode == 0, f"Script execution failed with error:\n{result.stderr}"

    # Check that results.csv was created
    assert os.path.isfile(results_path), f"The output file {results_path} was not created."

    # Read the generated CSV
    with open(results_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        rows = list(reader)

    expected_rows = [
        ['start_node', 'end_node', 'total_size', 'latest_timestamp'],
        ['2', '5', '65', '2023-10-05T08:10:00'],
        ['2', '5', '55', '2023-10-05T08:10:00'],
        ['1', '5', '100', '2023-10-04T14:15:00'],
        ['2', '6', '65', '2023-10-03T09:30:00'],
        ['10', '5', '60', '2023-10-02T11:05:00']
    ]

    assert len(rows) > 0, "The results.csv file is empty."
    assert rows[0] == expected_rows[0], f"Header row is incorrect. Expected {expected_rows[0]}, got {rows[0]}"
    assert len(rows) == len(expected_rows), f"Expected {len(expected_rows)-1} result rows, got {len(rows)-1}."

    for i, (expected, actual) in enumerate(zip(expected_rows, rows)):
        assert actual == expected, f"Row {i} mismatch. Expected {expected}, got {actual}"

def test_parameterized_query_used():
    script_path = '/home/user/analyze_graph.py'
    with open(script_path, 'r', encoding='utf-8') as f:
        content = f.read()

    # A basic heuristic to ensure parameterized queries are used in sqlite3
    # Look for the presence of standard sqlite parameter markers
    assert "?" in content or ":" in content, "The script does not appear to use parameterized queries (missing '?' or ':name' markers)."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

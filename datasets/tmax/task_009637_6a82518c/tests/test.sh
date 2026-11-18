#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv

def test_top_connectors_exists():
    assert os.path.isfile('/home/user/top_connectors.csv'), "The output file /home/user/top_connectors.csv does not exist."

def test_top_connectors_content():
    expected_rows = [
        ['department', 'employee_id', 'name', 'bridge_score'],
        ['Engineering', '1', 'Alice', '2'],
        ['Marketing', '6', 'Frank', '1'],
        ['Sales', '3', 'Charlie', '4']
    ]

    file_path = '/home/user/top_connectors.csv'
    assert os.path.isfile(file_path), "The output file /home/user/top_connectors.csv does not exist."

    with open(file_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        actual_rows = [row for row in reader if any(field.strip() for field in row)]

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows (including header), but got {len(actual_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, but got {actual}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

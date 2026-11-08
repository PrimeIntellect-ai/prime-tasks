#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import pytest

def test_validation_errors_csv():
    file_path = "/home/user/validation_errors.csv"
    assert os.path.isfile(file_path), f"The file {file_path} does not exist."

    with open(file_path, 'r', newline='') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, f"{file_path} is empty."

    # Check header
    assert rows[0] == ["source_id", "target_id", "cost"], "Header in validation_errors.csv is incorrect."

    # Check contents
    expected_invalid_edges = [
        ["999", "106", "5"],
        ["104", "888", "10"]
    ]

    data_rows = rows[1:]
    assert len(data_rows) == len(expected_invalid_edges), f"Expected {len(expected_invalid_edges)} invalid edges, but found {len(data_rows)}."

    for expected in expected_invalid_edges:
        assert expected in data_rows, f"Expected invalid edge {expected} not found in validation_errors.csv."

def test_shortest_path_json():
    file_path = "/home/user/shortest_path.json"
    assert os.path.isfile(file_path), f"The file {file_path} does not exist."

    with open(file_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{file_path} is not a valid JSON file.")

    assert "path" in data, "The JSON file is missing the 'path' key."
    assert "total_cost" in data, "The JSON file is missing the 'total_cost' key."

    expected_path = [101, 103, 104, 105, 106, 107]
    expected_cost = 29

    assert data["path"] == expected_path, f"Expected path {expected_path}, but got {data['path']}."
    assert data["total_cost"] == expected_cost, f"Expected total_cost {expected_cost}, but got {data['total_cost']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

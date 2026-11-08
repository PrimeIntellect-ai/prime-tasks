#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import json
import pytest

CSV_PATH = "/home/user/employees.csv"
JSON_PATH = "/home/user/hierarchy.json"

def compute_expected_hierarchy(csv_path):
    employees = {}

    with open(csv_path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            emp_id = int(row["ID"])
            employees[emp_id] = {
                "id": emp_id,
                "name": row["Name"],
                "manager_id": int(row["ManagerID"]) if row["ManagerID"].strip() else None
            }

    # Compute depths
    def get_depth(emp_id):
        manager_id = employees[emp_id]["manager_id"]
        if manager_id is None:
            return 0
        return 1 + get_depth(manager_id)

    expected = []
    for emp_id in sorted(employees.keys()):
        expected.append({
            "id": emp_id,
            "name": employees[emp_id]["name"],
            "depth": get_depth(emp_id)
        })

    return expected

def test_hierarchy_json_exists():
    """Test that the output JSON file exists."""
    assert os.path.exists(JSON_PATH), f"The file {JSON_PATH} does not exist. Did you create it?"
    assert os.path.isfile(JSON_PATH), f"The path {JSON_PATH} is not a file."

def test_hierarchy_json_valid_and_correct():
    """Test that the JSON file is valid, has the correct types, is sorted, and has correct depths."""
    assert os.path.exists(CSV_PATH), f"Input CSV {CSV_PATH} is missing."

    with open(JSON_PATH, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"The file {JSON_PATH} is not valid JSON: {e}")

    assert isinstance(data, list), f"The JSON root must be an array, got {type(data).__name__}."

    expected_data = compute_expected_hierarchy(CSV_PATH)

    assert len(data) == len(expected_data), f"Expected {len(expected_data)} records, got {len(data)}."

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        # Check types
        assert isinstance(actual.get("id"), int), f"Record at index {i}: 'id' must be an integer."
        assert isinstance(actual.get("name"), str), f"Record at index {i}: 'name' must be a string."
        assert isinstance(actual.get("depth"), int), f"Record at index {i}: 'depth' must be an integer."

        # Check exact values
        assert actual["id"] == expected["id"], f"Record at index {i}: Expected 'id' {expected['id']}, got {actual.get('id')}. The array must be sorted by ID ascending."
        assert actual["name"] == expected["name"], f"Record at index {i}: Expected 'name' {expected['name']}, got {actual.get('name')}."
        assert actual["depth"] == expected["depth"], f"Record at index {i}: Expected 'depth' {expected['depth']} for {actual['name']}, got {actual.get('depth')}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

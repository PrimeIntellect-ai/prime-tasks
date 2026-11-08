#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import pytest

def build_expected_tree(csv_path):
    employees = {}

    with open(csv_path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            emp_id = int(row["emp_id"])
            manager_id = int(row["manager_id"]) if row["manager_id"] else None
            cost = int(row["cost"])

            employees[emp_id] = {
                "emp_id": emp_id,
                "emp_name": row["emp_name"],
                "cost": cost,
                "manager_id": manager_id,
                "subordinates": []
            }

    # Build hierarchy
    root_employees = []
    for emp_id, emp in employees.items():
        if emp["manager_id"] is None:
            root_employees.append(emp)
        else:
            employees[emp["manager_id"]]["subordinates"].append(emp)

    def compute_cost_and_clean(node):
        total_cost = node["cost"]
        for sub in node["subordinates"]:
            total_cost += compute_cost_and_clean(sub)

        node["total_team_cost"] = total_cost
        # Sort subordinates by emp_id
        node["subordinates"].sort(key=lambda x: x["emp_id"])
        # Remove manager_id as it's not in the output schema
        del node["manager_id"]

        return total_cost

    # Process all roots
    for root in root_employees:
        compute_cost_and_clean(root)

    root_employees.sort(key=lambda x: x["emp_id"])
    return root_employees

def test_org_chart_json_exists_and_correct():
    csv_path = "/home/user/employees.csv"
    json_path = "/home/user/org_chart.json"

    assert os.path.isfile(json_path), f"Expected output file {json_path} is missing."

    with open(json_path, "r", encoding="utf-8") as f:
        try:
            actual_json = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} is not valid JSON.")

    expected_json = build_expected_tree(csv_path)

    assert actual_json == expected_json, "The generated org_chart.json does not match the expected hierarchical structure and computed costs."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import sqlite3
import pytest

OUTPUT_PATH = "/home/user/manager_costs.jsonl"
DB_PATH = "/home/user/company.db"

def compute_expected_costs():
    """Compute the expected costs directly from the database."""
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("SELECT id, reports_to, document FROM personnel")
    rows = c.fetchall()
    conn.close()

    # Build adjacency list and base costs
    reports = {}
    costs = {}

    for row in rows:
        emp_id, reports_to, document = row

        if emp_id not in reports:
            reports[emp_id] = []

        if reports_to is not None:
            if reports_to not in reports:
                reports[reports_to] = []
            reports[reports_to].append(emp_id)

        try:
            doc = json.loads(document)
            comp = doc.get("compensation", {})
            base = float(comp.get("base", 0.0))
            bonus = float(comp.get("bonus", 0.0))
            costs[emp_id] = base + bonus
        except Exception:
            costs[emp_id] = 0.0

    # Recursive function to calculate tree cost and size
    def get_tree_totals(emp_id):
        total_cost = costs[emp_id]
        total_size = 1
        for report in reports.get(emp_id, []):
            child_cost, child_size = get_tree_totals(report)
            total_cost += child_cost
            total_size += child_size
        return total_cost, total_size

    expected_results = []
    for emp_id in sorted(costs.keys()):
        total_cost, total_size = get_tree_totals(emp_id)
        expected_results.append({
            "manager_id": emp_id,
            "total_tree_cost": total_cost,
            "tree_size": total_size
        })

    return expected_results

def test_output_file_exists():
    """Test that the output JSONL file exists."""
    assert os.path.exists(OUTPUT_PATH), f"Output file {OUTPUT_PATH} is missing."
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} is not a file."

def test_output_file_contents():
    """Test that the output JSONL file contains the correct data in the correct order."""
    expected = compute_expected_costs()

    assert os.path.exists(OUTPUT_PATH), f"Output file {OUTPUT_PATH} is missing."

    actual = []
    with open(OUTPUT_PATH, 'r') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                obj = json.loads(line)
                actual.append(obj)
            except json.JSONDecodeError:
                pytest.fail(f"Line {line_num} in {OUTPUT_PATH} is not valid JSON: {line}")

    assert len(actual) == len(expected), f"Expected {len(expected)} lines in {OUTPUT_PATH}, found {len(actual)}."

    for i, (act, exp) in enumerate(zip(actual, expected)):
        assert "manager_id" in act, f"Line {i+1} missing 'manager_id'."
        assert "total_tree_cost" in act, f"Line {i+1} missing 'total_tree_cost'."
        assert "tree_size" in act, f"Line {i+1} missing 'tree_size'."

        assert act["manager_id"] == exp["manager_id"], f"Line {i+1} manager_id mismatch: expected {exp['manager_id']}, got {act['manager_id']}. Ensure lines are sorted by manager_id."
        assert act["tree_size"] == exp["tree_size"], f"Line {i+1} for manager_id {exp['manager_id']} tree_size mismatch: expected {exp['tree_size']}, got {act['tree_size']}."
        assert abs(act["total_tree_cost"] - exp["total_tree_cost"]) < 1e-6, f"Line {i+1} for manager_id {exp['manager_id']} total_tree_cost mismatch: expected {exp['total_tree_cost']}, got {act['total_tree_cost']}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

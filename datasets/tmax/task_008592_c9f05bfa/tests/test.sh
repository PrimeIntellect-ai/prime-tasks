#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import json
import pytest
from collections import defaultdict

def get_cohort(employees_file, root_id):
    managers = defaultdict(list)
    with open(employees_file, "r", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            managers[row["manager_id"]].append(row["emp_id"])

    cohort = set()
    queue = [root_id]
    while queue:
        current = queue.pop(0)
        cohort.add(current)
        queue.extend(managers.get(current, []))
    return cohort

def get_expected_aggregations(access_logs_file, cohort):
    with open(access_logs_file, "r") as f:
        logs = json.load(f)

    aggs = defaultdict(lambda: {"total_accesses": 0, "latest_access": ""})
    for log in logs:
        if log["emp_id"] in cohort:
            sys = log["system_name"]
            aggs[sys]["total_accesses"] += 1
            if log["access_time"] > aggs[sys]["latest_access"]:
                aggs[sys]["latest_access"] = log["access_time"]

    results = []
    for sys, data in aggs.items():
        results.append({
            "system_name": sys,
            "total_accesses": data["total_accesses"],
            "latest_access": data["latest_access"]
        })

    results.sort(key=lambda x: (-x["total_accesses"], x["system_name"]))
    return results

def test_audit_results_exists():
    output_file = "/home/user/audit_results.csv"
    assert os.path.isfile(output_file), f"Output file {output_file} is missing. The script did not generate it."

def test_audit_results_content():
    employees_file = "/home/user/employees.csv"
    access_logs_file = "/home/user/access_logs.json"
    output_file = "/home/user/audit_results.csv"

    assert os.path.isfile(employees_file), f"Input file {employees_file} is missing."
    assert os.path.isfile(access_logs_file), f"Input file {access_logs_file} is missing."
    assert os.path.isfile(output_file), f"Output file {output_file} is missing."

    cohort = get_cohort(employees_file, "MGR-042")
    expected_results = get_expected_aggregations(access_logs_file, cohort)

    with open(output_file, "r", newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["system_name", "total_accesses", "latest_access"], \
            f"Incorrect headers in {output_file}. Expected ['system_name', 'total_accesses', 'latest_access'], got {header}"

        actual_results = []
        for row in reader:
            assert len(row) == 3, f"Invalid row length in {output_file}: {row}"
            actual_results.append({
                "system_name": row[0],
                "total_accesses": int(row[1]),
                "latest_access": row[2]
            })

    assert len(actual_results) == len(expected_results), \
        f"Expected {len(expected_results)} rows in {output_file}, but found {len(actual_results)}."

    for i, (actual, expected) in enumerate(zip(actual_results, expected_results)):
        assert actual["system_name"] == expected["system_name"], \
            f"Row {i+1} system_name mismatch. Expected {expected['system_name']}, got {actual['system_name']}"
        assert actual["total_accesses"] == expected["total_accesses"], \
            f"Row {i+1} total_accesses mismatch for {actual['system_name']}. Expected {expected['total_accesses']}, got {actual['total_accesses']}"
        assert actual["latest_access"] == expected["latest_access"], \
            f"Row {i+1} latest_access mismatch for {actual['system_name']}. Expected {expected['latest_access']}, got {actual['latest_access']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

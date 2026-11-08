#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest
from collections import defaultdict

def test_compliance_report_exists():
    """Verify that the compliance_report.json file exists."""
    assert os.path.isfile("/home/user/compliance_report.json"), "The file /home/user/compliance_report.json does not exist."

def test_compliance_report_content():
    """Verify that the compliance_report.json contains the correctly aggregated data."""
    input_file = "/home/user/data/users.jsonl"
    output_file = "/home/user/compliance_report.json"

    assert os.path.isfile(input_file), f"Input file {input_file} is missing."
    assert os.path.isfile(output_file), f"Output file {output_file} is missing."

    # Compute expected result from input file
    departments_data = defaultdict(lambda: {"total_accesses": 0, "unique_roles": set()})

    with open(input_file, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            record = json.loads(line)
            dept = record.get("department")
            roles = record.get("roles", [])
            access_logs = record.get("access_logs", [])

            departments_data[dept]["total_accesses"] += len(access_logs)
            for role in roles:
                departments_data[dept]["unique_roles"].add(role)

    expected_report = []
    for dept in sorted(departments_data.keys()):
        expected_report.append({
            "department": dept,
            "total_accesses": departments_data[dept]["total_accesses"],
            "unique_roles": sorted(list(departments_data[dept]["unique_roles"]))
        })

    # Read actual result
    with open(output_file, "r") as f:
        try:
            actual_report = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {output_file} does not contain valid JSON.")

    # Assert type and structure
    assert isinstance(actual_report, list), "The root of the JSON file must be an array."

    # Assert content
    assert actual_report == expected_report, f"The compliance report data is incorrect. Expected: {expected_report}, but got: {actual_report}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

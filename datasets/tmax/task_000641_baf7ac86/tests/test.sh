#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json

def test_audit_report_exists():
    assert os.path.isfile("/home/user/audit_report.json"), "The output file /home/user/audit_report.json does not exist."

def test_audit_report_content():
    report_path = "/home/user/audit_report.json"
    assert os.path.isfile(report_path), "The output file /home/user/audit_report.json does not exist."

    with open(report_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, "The file /home/user/audit_report.json does not contain valid JSON."

    assert isinstance(data, list), "The JSON output must be an array of objects."

    expected_data = [
        {"employee": "Bob", "shortest_path": 2},
        {"employee": "Charlie", "shortest_path": 2},
        {"employee": "Alice", "shortest_path": 3},
        {"employee": "Diana", "shortest_path": 4}
    ]

    assert len(data) == len(expected_data), f"Expected {len(expected_data)} records, but got {len(data)}."

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert isinstance(actual, dict), f"Item at index {i} is not a JSON object."
        assert "employee" in actual, f"Item at index {i} is missing the 'employee' key."
        assert "shortest_path" in actual, f"Item at index {i} is missing the 'shortest_path' key."

        assert actual["employee"] == expected["employee"], f"Expected employee '{expected['employee']}' at index {i}, but got '{actual['employee']}'."
        assert actual["shortest_path"] == expected["shortest_path"], f"Expected shortest_path {expected['shortest_path']} for {actual['employee']}, but got {actual['shortest_path']}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

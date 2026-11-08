#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pytest


def test_debug_report_exists_and_valid():
    report_path = "/home/user/debug_report.json"
    expected_path = "/tests/.expected_solution.json"

    assert os.path.isfile(report_path), f"File {report_path} does not exist. You must save your findings in this file."
    assert os.path.isfile(expected_path), f"Expected solution file {expected_path} is missing from the test environment."

    with open(expected_path) as f:
        expected = json.load(f)

    with open(report_path) as f:
        try:
            actual = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {report_path} does not contain valid JSON.")

    assert "crashing_function" in actual, "Missing 'crashing_function' key in JSON report."
    assert "leaking_commit_hash" in actual, "Missing 'leaking_commit_hash' key in JSON report."
    assert "leaked_struct_name" in actual, "Missing 'leaked_struct_name' key in JSON report."

    assert actual["crashing_function"] == expected["crashing_function"], f"Incorrect crashing function. Expected {expected['crashing_function']}, got {actual['crashing_function']}"
    assert actual["leaking_commit_hash"] == expected["leaking_commit_hash"], f"Incorrect leaking commit hash. Expected {expected['leaking_commit_hash']}, got {actual['leaking_commit_hash']}"
    assert actual["leaked_struct_name"] == expected["leaked_struct_name"], f"Incorrect leaked struct name. Expected {expected['leaked_struct_name']}, got {actual['leaked_struct_name']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_audit_report_exists_and_correct():
    report_path = "/home/user/audit_report.json"
    assert os.path.isfile(report_path), f"The file {report_path} does not exist."

    with open(report_path, "r") as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {report_path} does not contain valid JSON.")

    assert "hidden_ubos" in report_data, "The JSON report is missing the 'hidden_ubos' key."
    assert "top_intermediaries" in report_data, "The JSON report is missing the 'top_intermediaries' key."

    expected_hidden_ubos = [
        "I_1 owns 60.0% of C_3",
        "I_1 owns 60.0% of C_4",
        "I_1 owns 48.0% of C_5",
        "I_1 owns 48.0% of C_6",
        "I_2 owns 26.0% of C_5",
        "I_2 owns 26.0% of C_6",
        "I_3 owns 26.0% of C_5",
        "I_3 owns 26.0% of C_6"
    ]

    expected_top_intermediaries = [
        "C_3",
        "C_4"
    ]

    actual_hidden_ubos = report_data["hidden_ubos"]
    actual_top_intermediaries = report_data["top_intermediaries"]

    assert isinstance(actual_hidden_ubos, list), "'hidden_ubos' should be a list."
    assert isinstance(actual_top_intermediaries, list), "'top_intermediaries' should be a list."

    assert sorted(actual_hidden_ubos) == sorted(expected_hidden_ubos), f"Expected hidden_ubos to be {expected_hidden_ubos}, but got {actual_hidden_ubos}."
    assert actual_hidden_ubos == expected_hidden_ubos, "The 'hidden_ubos' list is not sorted correctly."

    assert actual_top_intermediaries == expected_top_intermediaries, f"Expected top_intermediaries to be {expected_top_intermediaries}, but got {actual_top_intermediaries}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

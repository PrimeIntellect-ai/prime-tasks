#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_report_json_exists():
    report_path = "/home/user/investigation/report.json"
    assert os.path.isfile(report_path), f"The report file {report_path} does not exist."

def test_report_json_content():
    report_path = "/home/user/investigation/report.json"
    assert os.path.isfile(report_path), "Cannot check content because report.json does not exist."

    try:
        with open(report_path, "r") as f:
            report_data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail("The file report.json does not contain valid JSON.")

    expected_data = {
        "exfiltration_ip": "203.0.113.88",
        "malicious_csp": "script-src 'unsafe-eval' https://c2.attacker.com;",
        "redirected_port": 1337,
        "suid_binary": "updater_daemon"
    }

    assert isinstance(report_data, dict), "The JSON root must be an object (dictionary)."

    # Check keys and values
    for key, expected_value in expected_data.items():
        assert key in report_data, f"Missing key '{key}' in report.json."
        assert report_data[key] == expected_value, f"Incorrect value for '{key}'. Expected {expected_value}, got {report_data[key]}."

    # Check for extra keys
    extra_keys = set(report_data.keys()) - set(expected_data.keys())
    assert not extra_keys, f"Found unexpected keys in report.json: {extra_keys}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

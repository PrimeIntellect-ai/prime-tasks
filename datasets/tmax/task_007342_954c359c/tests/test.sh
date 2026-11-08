#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import pytest

REPORT_PATH = "/home/user/diagnostic_report.json"

def test_diagnostic_report_exists():
    assert os.path.exists(REPORT_PATH), f"Diagnostic report not found at {REPORT_PATH}"
    assert os.path.isfile(REPORT_PATH), f"Path {REPORT_PATH} is not a file"

def test_diagnostic_report_content():
    assert os.path.exists(REPORT_PATH), f"Diagnostic report not found at {REPORT_PATH}"

    with open(REPORT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT_PATH} is not valid JSON")

    assert isinstance(data, dict), "The JSON root must be an object (dictionary)"

    expected_keys = {"malicious_ip", "payload_hex", "fatal_signal"}
    missing_keys = expected_keys - set(data.keys())
    assert not missing_keys, f"Missing keys in JSON report: {missing_keys}"

    assert data["malicious_ip"] == "172.16.45.99", \
        f"Expected malicious_ip to be '172.16.45.99', but got '{data['malicious_ip']}'"

    expected_hex = b"CRASH_ME_NOW".hex().lower()
    actual_hex = str(data["payload_hex"]).lower()
    assert actual_hex == expected_hex, \
        f"Expected payload_hex to be '{expected_hex}', but got '{actual_hex}'"

    actual_signal = str(data["fatal_signal"]).upper()
    assert actual_signal == "SIGSEGV", \
        f"Expected fatal_signal to be 'SIGSEGV', but got '{actual_signal}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

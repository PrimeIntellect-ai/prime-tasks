#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import json
import os
import pytest

REPORT_PATH = "/home/user/report.json"

def test_report_exists_and_is_file():
    """Verify that the report.json file exists."""
    assert os.path.exists(REPORT_PATH), f"Report file {REPORT_PATH} does not exist."
    assert os.path.isfile(REPORT_PATH), f"Report path {REPORT_PATH} is not a file."

def test_report_is_valid_json():
    """Verify that the report.json file contains valid JSON."""
    with open(REPORT_PATH, "r") as f:
        try:
            json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"File {REPORT_PATH} does not contain valid JSON. Error: {e}")

def test_report_structure():
    """Verify the JSON report contains exactly the required keys."""
    with open(REPORT_PATH, "r") as f:
        data = json.load(f)

    expected_keys = {"targeted_port", "compromised_file", "cwe_id"}
    actual_keys = set(data.keys())

    missing = expected_keys - actual_keys
    extra = actual_keys - expected_keys

    assert not missing, f"Report is missing required keys: {missing}"
    assert not extra, f"Report contains extra keys: {extra}"

def test_report_targeted_port():
    """Verify the targeted_port correctly identifies the most dropped port."""
    with open(REPORT_PATH, "r") as f:
        data = json.load(f)

    port = data.get("targeted_port")
    assert isinstance(port, int), f"targeted_port must be an integer, got {type(port).__name__}"
    assert port == 8082, f"targeted_port is incorrect. Expected 8082, got {port}."

def test_report_compromised_file():
    """Verify the compromised_file correctly identifies the tampered service."""
    with open(REPORT_PATH, "r") as f:
        data = json.load(f)

    filename = data.get("compromised_file")
    assert isinstance(filename, str), f"compromised_file must be a string, got {type(filename).__name__}"
    assert filename == "data_service.py", f"compromised_file is incorrect. Expected 'data_service.py', got '{filename}'."

def test_report_cwe_id():
    """Verify the cwe_id correctly identifies the OS command injection vulnerability."""
    with open(REPORT_PATH, "r") as f:
        data = json.load(f)

    cwe = data.get("cwe_id")
    assert isinstance(cwe, str), f"cwe_id must be a string, got {type(cwe).__name__}"
    assert cwe.upper() == "CWE-78", f"cwe_id is incorrect. Expected 'CWE-78' (OS Command Injection), got '{cwe}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import hashlib
import re
import pytest

REPORT_PATH = "/home/user/audit_report.json"
BINARY_PATH = "/home/user/bin/network-diagnostic"
LOG_PATH = "/home/user/logs/auth.log"

def get_expected_key():
    with open(BINARY_PATH, "rb") as f:
        content = f.read()

    prefix = b"__AUTH_KEY_V2__="
    idx = content.find(prefix)
    if idx == -1:
        pytest.fail(f"Could not find prefix {prefix} in {BINARY_PATH} during test setup.")

    start = idx + len(prefix)
    end = content.find(b'\x00', start)
    if end == -1:
        end = len(content)

    return content[start:end].decode('utf-8', errors='ignore')

def get_expected_token(key):
    plaintext = key + "system_auditor"
    return hashlib.sha256(plaintext.encode('utf-8')).hexdigest()

def get_expected_ips():
    ips = set()
    pattern = re.compile(r"Successful diagnostic override from IP:\s*([0-9\.]+)")
    with open(LOG_PATH, "r") as f:
        for line in f:
            match = pattern.search(line)
            if match:
                ips.add(match.group(1))
    return sorted(list(ips))

@pytest.fixture
def report_data():
    assert os.path.exists(REPORT_PATH), f"The audit report is missing: {REPORT_PATH}"
    assert os.path.isfile(REPORT_PATH), f"The path is not a file: {REPORT_PATH}"

    try:
        with open(REPORT_PATH, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The audit report at {REPORT_PATH} is not valid JSON.")

    return data

def test_report_structure(report_data):
    expected_keys = {"extracted_key", "valid_token", "compromised_ips"}
    actual_keys = set(report_data.keys())
    assert actual_keys == expected_keys, f"Report JSON keys are incorrect. Expected {expected_keys}, got {actual_keys}"

def test_extracted_key(report_data):
    expected_key = get_expected_key()
    actual_key = report_data.get("extracted_key")
    assert actual_key == expected_key, f"Extracted key is incorrect. Expected '{expected_key}', got '{actual_key}'"

def test_valid_token(report_data):
    expected_key = get_expected_key()
    expected_token = get_expected_token(expected_key)
    actual_token = report_data.get("valid_token")
    assert actual_token == expected_token, f"Valid token is incorrect. Expected '{expected_token}', got '{actual_token}'"

def test_compromised_ips(report_data):
    expected_ips = get_expected_ips()
    actual_ips = report_data.get("compromised_ips")

    assert isinstance(actual_ips, list), "compromised_ips must be a list"
    assert actual_ips == expected_ips, f"Compromised IPs are incorrect or not sorted properly. Expected {expected_ips}, got {actual_ips}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

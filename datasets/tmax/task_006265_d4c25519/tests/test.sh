#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

REPORT_PATH = "/home/user/incident_report.json"

def test_incident_report_exists():
    assert os.path.exists(REPORT_PATH), f"The report file {REPORT_PATH} does not exist."
    assert os.path.isfile(REPORT_PATH), f"The path {REPORT_PATH} is not a file."

def test_incident_report_valid_json():
    with open(REPORT_PATH, "r") as f:
        try:
            json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"The report file {REPORT_PATH} does not contain valid JSON: {e}")

def test_incident_report_contents():
    with open(REPORT_PATH, "r") as f:
        report = json.load(f)

    # Check required keys
    required_keys = ["bad_commit_message", "crashing_payload", "originating_service", "timestamp"]
    for key in required_keys:
        assert key in report, f"Missing required key '{key}' in the incident report."

    # Validate bad_commit_message
    expected_commit_msg = "Feature: extract payload processing to function"
    assert report["bad_commit_message"].strip() == expected_commit_msg, \
        f"Expected bad_commit_message to be '{expected_commit_msg}', got '{report['bad_commit_message']}'"

    # Validate crashing_payload (allow with or without trailing newline)
    expected_payload = "CRASH_TRIGGER_OVERSIZED_PAYLOAD_AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA"
    actual_payload = report["crashing_payload"].strip()
    assert actual_payload == expected_payload, \
        f"Expected crashing_payload to be '{expected_payload}', got '{actual_payload}'"

    # Validate originating_service
    expected_service = "beta"
    assert report["originating_service"].strip() == expected_service, \
        f"Expected originating_service to be '{expected_service}', got '{report['originating_service']}'"

    # Validate timestamp
    expected_timestamp = "2023-11-01T10:15:33Z"
    assert report["timestamp"].strip() == expected_timestamp, \
        f"Expected timestamp to be '{expected_timestamp}', got '{report['timestamp']}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

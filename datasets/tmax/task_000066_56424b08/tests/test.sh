#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pytest

REPORT_PATH = '/home/user/audit_report.json'
EXPECTED_KEYS = {
    'open_redirect_line',
    'sqli_line',
    'next_predicted_token',
}
EXPECTED_VALUES = {
    'open_redirect_line': 15,
    'sqli_line': 23,
    'next_predicted_token': 61966,
}

def test_audit_report_exists():
    assert os.path.isfile(REPORT_PATH), f'The audit report file {REPORT_PATH} was not found.'

def test_audit_report_content():
    assert os.path.isfile(REPORT_PATH), 'Missing audit report.'

    with open(REPORT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail('The file /home/user/audit_report.json does not contain valid JSON.')

    assert isinstance(data, dict), 'The audit report must be a JSON object.'
    assert set(data.keys()) == EXPECTED_KEYS, 'The JSON report must contain exactly the specified keys.'

    assert 'open_redirect_line' in data, "Key 'open_redirect_line' is missing from the JSON report."
    assert 'sqli_line' in data, "Key 'sqli_line' is missing from the JSON report."
    assert 'next_predicted_token' in data, "Key 'next_predicted_token' is missing from the JSON report."

    for key in EXPECTED_KEYS:
        assert type(data[key]) is int, f"Value for '{key}' must be an integer."

    assert data['open_redirect_line'] == EXPECTED_VALUES['open_redirect_line'], f"Expected open_redirect_line to be 15, got {data['open_redirect_line']}."
    assert data['sqli_line'] == EXPECTED_VALUES['sqli_line'], f"Expected sqli_line to be 23, got {data['sqli_line']}."
    assert data['next_predicted_token'] == EXPECTED_VALUES['next_predicted_token'], f"Expected next_predicted_token to be 61966, got {data['next_predicted_token']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

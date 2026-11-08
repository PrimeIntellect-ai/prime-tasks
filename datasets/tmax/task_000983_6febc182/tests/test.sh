#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import base64
import re
import pytest

REPORT_PATH = '/home/user/forensics_report.txt'
LOG_PATH = '/home/user/evidence/app.log'

def test_report_exists():
    """Test that the forensics report was created."""
    assert os.path.isfile(REPORT_PATH), f"The report file {REPORT_PATH} does not exist."

def test_report_cwe():
    """Test that the correct CWE is identified in the report."""
    with open(REPORT_PATH, 'r') as f:
        content = f.read()

    assert "CWE: CWE-601" in content, "The report does not contain the correct CWE (CWE-601) or is not formatted correctly."

def test_report_leaked_key():
    """Test that the leaked token key is correctly extracted and reported."""
    # Derive the key from the log file to ensure test remains faithful
    assert os.path.isfile(LOG_PATH), f"Log file {LOG_PATH} is missing."
    with open(LOG_PATH, 'r') as f:
        log_content = f.read()

    # Extract base64 token from log
    match = re.search(r'token=([A-Za-z0-9+/=]+)', log_content)
    assert match is not None, "Could not find token in app.log"
    b64_token = match.group(1)

    # Decode and parse token
    token_json = base64.b64decode(b64_token).decode('utf-8')
    token_data = json.loads(token_json)
    expected_key = token_data.get("key")

    with open(REPORT_PATH, 'r') as f:
        report_content = f.read()

    expected_line = f"Leaked Token Key: {expected_key}"
    assert expected_line in report_content, f"The report does not contain the correct leaked token key. Expected line: '{expected_line}'"

def test_report_decrypted_content():
    """Test that the decrypted content is correctly reported."""
    # Since cryptography is not in stdlib, we use the known truth value for the decrypted content
    expected_plaintext = "FLAG{0p3n_r3d1r3ct_l34d5_t0_f3rn3t_d3crypt!0n}"

    with open(REPORT_PATH, 'r') as f:
        report_content = f.read()

    expected_line = f"Decrypted Content: {expected_plaintext}"
    assert expected_line in report_content, f"The report does not contain the correct decrypted content. Expected line: '{expected_line}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

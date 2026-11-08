#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import stat
import hashlib
import pytest

REPORT_PATH = "/home/user/incident_report.json"
FILE_PATH = "/home/user/compromised/shell.py"

def test_incident_report_exists():
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} does not exist."

def test_incident_report_content():
    with open(REPORT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT_PATH} is not valid JSON.")

    assert "attacker_ip" in data, "Missing 'attacker_ip' in report."
    assert data["attacker_ip"] == "192.168.137.42", f"Incorrect attacker_ip: {data['attacker_ip']}"

    assert "session_cookie" in data, "Missing 'session_cookie' in report."
    assert data["session_cookie"] == "admin_super_secret_992", f"Incorrect session_cookie: {data['session_cookie']}"

    assert "xss_attempt_count" in data, "Missing 'xss_attempt_count' in report."
    assert data["xss_attempt_count"] == 2, f"Incorrect xss_attempt_count: {data['xss_attempt_count']}"

    # Calculate hash dynamically based on the expected file content
    expected_content = b"import os; os.system('/bin/bash')\n"
    expected_hash = hashlib.sha256(expected_content).hexdigest()

    assert "malicious_file_hash" in data, "Missing 'malicious_file_hash' in report."
    assert data["malicious_file_hash"] == expected_hash, f"Incorrect malicious_file_hash: {data['malicious_file_hash']}"

def test_file_permissions():
    assert os.path.isfile(FILE_PATH), f"Malicious file {FILE_PATH} is missing."
    st = os.stat(FILE_PATH)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0, f"Permissions for {FILE_PATH} are not 000. Found: {oct(perms)}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

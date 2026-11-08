#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest
import subprocess

EVIDENCE_DIR = "/home/user/evidence"
PROCESS_LIST = os.path.join(EVIDENCE_DIR, "process_list.txt")
WEB_LOG = os.path.join(EVIDENCE_DIR, "web_access.log")
REDACTED_LOG = os.path.join(EVIDENCE_DIR, "web_access_redacted.log")
ROGUE_CA = os.path.join(EVIDENCE_DIR, "rogue_ca.pem")
CERTS_DIR = os.path.join(EVIDENCE_DIR, "certs")
REPORT_FILE = "/home/user/report.json"

def get_expected_token():
    """Dynamically extract the token from the process list as the student would."""
    if not os.path.exists(PROCESS_LIST):
        pytest.fail(f"Required file missing: {PROCESS_LIST}")

    with open(PROCESS_LIST, "r") as f:
        for line in f:
            if "exfiltrate.sh" in line and "--auth-token" in line:
                parts = line.split()
                try:
                    idx = parts.index("--auth-token")
                    return parts[idx + 1]
                except (ValueError, IndexError):
                    continue
    pytest.fail("Could not derive the expected token from process_list.txt. Setup may be corrupted.")

def get_expected_malicious_cert():
    """Dynamically find which cert is signed by the rogue CA using openssl."""
    if not os.path.exists(ROGUE_CA) or not os.path.exists(CERTS_DIR):
        pytest.fail("Missing rogue CA or certs directory for validation.")

    for filename in os.listdir(CERTS_DIR):
        if filename.endswith(".pem"):
            cert_path = os.path.join(CERTS_DIR, filename)
            # Use openssl verify to check if the cert was signed by the rogue CA
            result = subprocess.run(
                ["openssl", "verify", "-CAfile", ROGUE_CA, cert_path],
                capture_output=True,
                text=True
            )
            if result.returncode == 0 and "OK" in result.stdout:
                return filename
    pytest.fail("Could not find any certificate signed by the rogue CA in the setup.")

@pytest.fixture(scope="module")
def expected_data():
    return {
        "token": get_expected_token(),
        "malicious_cert": get_expected_malicious_cert()
    }

def test_report_exists_and_valid_json():
    assert os.path.isfile(REPORT_FILE), f"Report file missing at {REPORT_FILE}"
    try:
        with open(REPORT_FILE, "r") as f:
            json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {REPORT_FILE} does not contain valid JSON.")

def test_report_contents(expected_data):
    with open(REPORT_FILE, "r") as f:
        report = json.load(f)

    assert "leaked_token" in report, "Report JSON is missing the 'leaked_token' key."
    assert "malicious_cert_file" in report, "Report JSON is missing the 'malicious_cert_file' key."

    actual_token = report["leaked_token"]
    expected_token = expected_data["token"]
    assert actual_token == expected_token, f"Incorrect leaked_token. Expected '{expected_token}', got '{actual_token}'."

    actual_cert = report["malicious_cert_file"]
    expected_cert = expected_data["malicious_cert"]
    assert actual_cert == expected_cert, f"Incorrect malicious_cert_file. Expected '{expected_cert}', got '{actual_cert}'."

def test_redacted_log_exists_and_correct(expected_data):
    assert os.path.isfile(REDACTED_LOG), f"Redacted log file missing at {REDACTED_LOG}"
    assert os.path.isfile(WEB_LOG), f"Original log file missing at {WEB_LOG}"

    expected_token = expected_data["token"]

    with open(WEB_LOG, "r") as f:
        original_lines = f.readlines()

    with open(REDACTED_LOG, "r") as f:
        redacted_lines = f.readlines()

    assert len(original_lines) == len(redacted_lines), \
        f"Line count mismatch: Original has {len(original_lines)} lines, redacted has {len(redacted_lines)} lines."

    for i, (orig, redacted) in enumerate(zip(original_lines, redacted_lines), 1):
        if expected_token in orig:
            expected_redacted_line = orig.replace(expected_token, "[REDACTED]")
            assert redacted == expected_redacted_line, \
                f"Line {i} was not correctly redacted. Expected token to be replaced with '[REDACTED]' exactly."
            assert expected_token not in redacted, \
                f"Line {i} still contains the leaked token!"
        else:
            assert redacted == orig, \
                f"Line {i} was modified but did not contain the leaked token. It should be an exact copy."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

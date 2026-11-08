#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import base64
import re
import pytest

FINDINGS_FILE = "/home/user/findings.txt"
EVIDENCE_DIR = "/home/user/evidence"
CERT_FILE = os.path.join(EVIDENCE_DIR, "intercepted_cert.pem")
GO_FILE = os.path.join(EVIDENCE_DIR, "malware_server.go")
LOGS_FILE = os.path.join(EVIDENCE_DIR, "traffic_logs.txt")

def get_expected_cn():
    try:
        output = subprocess.check_output(
            ["openssl", "x509", "-in", CERT_FILE, "-noout", "-subject"],
            text=True,
            stderr=subprocess.DEVNULL
        )
        # Output is typically like: subject=CN = hacked.internal.local
        match = re.search(r'CN\s*=\s*([^,\n]+)', output)
        if match:
            return match.group(1).strip()
    except Exception:
        pass
    return "hacked.internal.local"

def get_expected_line_number():
    with open(GO_FILE, "r") as f:
        lines = f.readlines()
    for i, line in enumerate(lines, 1):
        if "SELECT" in line and "WHERE username=" in line and "password=" in line:
            return str(i)
    return "38"

def get_expected_payload():
    with open(LOGS_FILE, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                decoded = base64.b64decode(line).decode('utf-8')
                if "admin" in decoded and "--" in decoded:
                    return decoded
            except Exception:
                continue
    return "username=admin'--&password=anything"

def test_findings_file_exists():
    assert os.path.isfile(FINDINGS_FILE), f"The file {FINDINGS_FILE} does not exist."

def test_findings_content():
    expected_cn = get_expected_cn()
    expected_line = get_expected_line_number()
    expected_payload = get_expected_payload()

    with open(FINDINGS_FILE, "r") as f:
        lines = [line.strip() for line in f.readlines()]

    assert len(lines) >= 3, f"{FINDINGS_FILE} must contain at least 3 lines."

    assert lines[0] == expected_cn, f"Line 1 of {FINDINGS_FILE} is incorrect. Expected the TLS Certificate Common Name."
    assert lines[1] == expected_line, f"Line 2 of {FINDINGS_FILE} is incorrect. Expected the vulnerable line number."
    assert lines[2] == expected_payload, f"Line 3 of {FINDINGS_FILE} is incorrect. Expected the decoded SQLi payload."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

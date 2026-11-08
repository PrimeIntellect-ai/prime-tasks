#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_report_exists():
    assert os.path.isfile('/home/user/report.txt'), "The report file /home/user/report.txt does not exist."

def test_report_contents():
    with open('/home/user/report.txt', 'r') as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_dict = {}
    for line in lines:
        if '=' in line:
            key, val = line.split('=', 1)
            expected_dict[key] = val

    assert "PAYLOAD_DECODED" in expected_dict, "PAYLOAD_DECODED is missing from the report."
    assert expected_dict["PAYLOAD_DECODED"] == "target_bin=system_backup", f"PAYLOAD_DECODED is incorrect: {expected_dict['PAYLOAD_DECODED']}"

    assert "SUID_BIN_PATH" in expected_dict, "SUID_BIN_PATH is missing from the report."
    assert expected_dict["SUID_BIN_PATH"] == "/home/user/incident/bin/system_backup", f"SUID_BIN_PATH is incorrect: {expected_dict['SUID_BIN_PATH']}"

    assert "CERT_VALID" in expected_dict, "CERT_VALID is missing from the report."
    assert expected_dict["CERT_VALID"] == "YES", f"CERT_VALID is incorrect: {expected_dict['CERT_VALID']}"

    assert "CERT_CN" in expected_dict, "CERT_CN is missing from the report."
    assert expected_dict["CERT_CN"] == "malicious-node.local", f"CERT_CN is incorrect: {expected_dict['CERT_CN']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

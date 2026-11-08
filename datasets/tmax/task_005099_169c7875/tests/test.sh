#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_report_json_exists():
    report_path = "/home/user/report.json"
    assert os.path.isfile(report_path), f"The file {report_path} was not created."

def test_report_json_content():
    report_path = "/home/user/report.json"
    assert os.path.isfile(report_path), f"The file {report_path} was not created."

    with open(report_path, 'r') as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {report_path} does not contain valid JSON.")

    expected_keys = ["open_redirect_cwe", "crypto_cwe", "decrypted_url", "privesc_binary"]
    for key in expected_keys:
        assert key in report_data, f"The key '{key}' is missing from {report_path}."

    assert report_data["open_redirect_cwe"] == "CWE-601", \
        f"Expected 'open_redirect_cwe' to be 'CWE-601', got '{report_data['open_redirect_cwe']}'."

    assert report_data["crypto_cwe"] == "CWE-327", \
        f"Expected 'crypto_cwe' to be 'CWE-327', got '{report_data['crypto_cwe']}'."

    assert report_data["decrypted_url"] == "https://evil-corp.xyz/login_bypass", \
        f"Expected 'decrypted_url' to be 'https://evil-corp.xyz/login_bypass', got '{report_data['decrypted_url']}'."

    assert report_data["privesc_binary"] == "/usr/bin/find", \
        f"Expected 'privesc_binary' to be '/usr/bin/find', got '{report_data['privesc_binary']}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

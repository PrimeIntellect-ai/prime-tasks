#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_rotation_report_exists_and_valid():
    path = "/home/user/rotation_report.json"
    assert os.path.isfile(path), f"Missing {path}. The report file was not created."

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {path} does not contain valid JSON.")

    assert "old_password" in data, "The JSON is missing the 'old_password' key."
    assert data["old_password"] == "nukes", "The recovered old password is incorrect."

    assert "new_password" in data, "The JSON is missing the 'new_password' key."
    assert data["new_password"] == "super_secret_p4ssw0rd_99", "The extracted new password is incorrect."

    assert "malicious_ips" in data, "The JSON is missing the 'malicious_ips' key."
    expected_ips = ["10.0.0.5", "172.16.0.4", "203.0.113.42"]

    assert isinstance(data["malicious_ips"], list), "'malicious_ips' must be a list."
    assert data["malicious_ips"] == expected_ips, (
        f"The 'malicious_ips' list is incorrect or not properly sorted. "
        f"Expected {expected_ips}, got {data['malicious_ips']}."
    )

def test_no_unencrypted_files_left_behind():
    # The student is instructed not to leave behind unencrypted sensitive files.
    # We check common locations where they might have decrypted the config.
    common_decrypted_paths = [
        "/home/user/new_config.txt",
        "/home/user/new_config.dec",
        "/home/user/config.txt"
    ]
    for p in common_decrypted_paths:
        assert not os.path.exists(p), f"Sensitive unencrypted file left behind at {p}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import stat
import pytest

REPORT_PATH = "/home/user/audit_report.json"
TARGET_DIR = "/home/user/audit_target"
LOG_FILE = "/home/user/audit_target/logs/auth.log"

def get_world_writable_files(directory):
    world_writable = []
    for root, _, files in os.walk(directory):
        for file in files:
            filepath = os.path.join(root, file)
            if os.path.isfile(filepath):
                st = os.stat(filepath)
                if bool(st.st_mode & stat.S_IWOTH):
                    world_writable.append(filepath)
    return sorted(world_writable)

def get_attacker_ip(log_path, token):
    if not os.path.exists(log_path):
        return None
    with open(log_path, "r") as f:
        for line in f:
            if token in line and "SUCCESS" in line:
                # Extract IP. Example line:
                # 2023-10-12 10:15:33 [INFO] User login attempt with token: B4ckd00r_T0k3n_9921 from IP: 203.0.113.42 - SUCCESS
                parts = line.split("from IP: ")
                if len(parts) > 1:
                    ip_part = parts[1].split(" - ")[0].strip()
                    return ip_part
    return None

def test_report_exists():
    assert os.path.isfile(REPORT_PATH), f"The audit report was not found at {REPORT_PATH}."

def test_report_format_and_keys():
    assert os.path.isfile(REPORT_PATH), "Report missing."
    with open(REPORT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("The audit report is not a valid JSON file.")

    expected_keys = {"world_writable_files", "hardcoded_token", "attacker_ip"}
    actual_keys = set(data.keys())
    assert expected_keys.issubset(actual_keys), f"The JSON report is missing required keys. Expected: {expected_keys}, Found: {actual_keys}"

def test_report_content():
    assert os.path.isfile(REPORT_PATH), "Report missing."
    with open(REPORT_PATH, "r") as f:
        data = json.load(f)

    # 1. Check world-writable files
    expected_ww_files = get_world_writable_files(TARGET_DIR)
    actual_ww_files = data.get("world_writable_files", [])
    assert isinstance(actual_ww_files, list), "'world_writable_files' must be a list."
    assert actual_ww_files == expected_ww_files, f"Incorrect world-writable files. Expected {expected_ww_files}, got {actual_ww_files}."

    # 2. Check hardcoded token
    # The token is hardcoded in the setup script
    expected_token = "B4ckd00r_T0k3n_9921"
    actual_token = data.get("hardcoded_token")
    assert actual_token == expected_token, f"Incorrect hardcoded token. Expected '{expected_token}', got '{actual_token}'."

    # 3. Check attacker IP
    expected_ip = get_attacker_ip(LOG_FILE, expected_token)
    actual_ip = data.get("attacker_ip")
    assert expected_ip is not None, "Could not derive expected IP from the log file."
    assert actual_ip == expected_ip, f"Incorrect attacker IP. Expected '{expected_ip}', got '{actual_ip}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

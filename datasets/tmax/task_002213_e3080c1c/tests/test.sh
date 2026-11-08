#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import stat
import pytest
from collections import defaultdict

def test_suspicious_ips_log():
    auth_log_path = "/home/user/auth.log"
    suspicious_ips_log_path = "/home/user/audit/suspicious_ips.log"

    assert os.path.isfile(auth_log_path), f"Original log file {auth_log_path} is missing."
    assert os.path.isfile(suspicious_ips_log_path), f"Output file {suspicious_ips_log_path} is missing."

    # Recompute suspicious IPs
    failed_attempts = defaultdict(int)
    with open(auth_log_path, "r") as f:
        for line in f:
            match = re.search(r"Failed password for (root|admin) from (\S+)", line)
            if match:
                ip = match.group(2)
                failed_attempts[ip] += 1

    expected_ips = sorted([ip for ip, count in failed_attempts.items() if count > 3])

    with open(suspicious_ips_log_path, "r") as f:
        actual_ips = [line.strip() for line in f if line.strip()]

    assert actual_ips == expected_ips, f"Expected suspicious IPs {expected_ips}, but got {actual_ips}."

def test_ssh_key_permissions_and_log():
    ssh_mock_dir = "/home/user/.ssh_mock"
    fixed_keys_log_path = "/home/user/audit/fixed_keys.log"

    assert os.path.isdir(ssh_mock_dir), f"{ssh_mock_dir} is missing."
    assert os.path.isfile(fixed_keys_log_path), f"Output file {fixed_keys_log_path} is missing."

    # Check current permissions
    for filename in os.listdir(ssh_mock_dir):
        if filename.endswith(".key"):
            filepath = os.path.join(ssh_mock_dir, filename)
            st = os.stat(filepath)
            mode = stat.S_IMODE(st.st_mode)
            assert mode == 0o600, f"File {filepath} should have permissions 600, but has {oct(mode)}."

    # Check fixed_keys.log
    # Based on setup, id_rsa.key and id_ecdsa.key needed fixing
    expected_fixed_keys = ["id_ecdsa.key", "id_rsa.key"]

    with open(fixed_keys_log_path, "r") as f:
        actual_fixed_keys = [line.strip() for line in f if line.strip()]

    assert actual_fixed_keys == expected_fixed_keys, f"Expected fixed keys log to contain {expected_fixed_keys}, but got {actual_fixed_keys}."

def test_hardened_sshd_config():
    original_config_path = "/home/user/audit_sshd_config"
    hardened_config_path = "/home/user/audit/hardened_sshd_config"

    assert os.path.isfile(original_config_path), f"Original config {original_config_path} is missing."
    assert os.path.isfile(hardened_config_path), f"Hardened config {hardened_config_path} is missing."

    with open(original_config_path, "r") as f:
        original_lines = f.readlines()

    expected_lines = []
    for line in original_lines:
        if line.strip().startswith("PermitRootLogin"):
            expected_lines.append(line.replace("yes", "no"))
        elif line.strip().startswith("PasswordAuthentication"):
            expected_lines.append(line.replace("yes", "no"))
        else:
            expected_lines.append(line)

    with open(hardened_config_path, "r") as f:
        actual_lines = f.readlines()

    assert actual_lines == expected_lines, "Hardened sshd_config does not match expected output exactly."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

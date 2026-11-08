#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import stat
import hashlib
import pytest

REPORT_PATH = "/home/user/audit_report.txt"
BASE_DIR = "/home/user/deploy_system"

def get_world_writable_files(base_dir):
    world_writable = []
    for root, _, files in os.walk(base_dir):
        for file in files:
            filepath = os.path.join(root, file)
            if not os.path.islink(filepath):
                st = os.stat(filepath)
                if st.st_mode & stat.S_IWOTH:
                    world_writable.append(filepath)
    return sorted(world_writable)

def get_tampered_cert(base_dir):
    hash_file = os.path.join(base_dir, "cert_hashes.sha256")
    if not os.path.exists(hash_file):
        return None

    with open(hash_file, "r") as f:
        lines = f.readlines()

    for line in lines:
        expected_hash, filename = line.strip().split(maxsplit=1)
        # The hash file was created inside certs dir, so filename might be just the basename or start with *
        filename = filename.lstrip("*")
        cert_path = os.path.join(base_dir, "certs", filename)

        if os.path.exists(cert_path):
            with open(cert_path, "rb") as cf:
                actual_hash = hashlib.sha256(cf.read()).hexdigest()
            if actual_hash != expected_hash:
                return filename
    return None

def test_audit_report_exists():
    assert os.path.isfile(REPORT_PATH), f"Audit report missing at {REPORT_PATH}"

def test_audit_report_line_count():
    with open(REPORT_PATH, "r") as f:
        lines = [line.strip('\n') for line in f.readlines()]
    assert len(lines) == 4, f"Audit report must have exactly 4 lines, found {len(lines)}"

def test_audit_report_line_1_vulnerable_script():
    with open(REPORT_PATH, "r") as f:
        lines = [line.strip('\n') for line in f.readlines()]
    assert lines[0] == "verify_token.sh", f"Line 1 is incorrect. Expected 'verify_token.sh', got '{lines[0]}'"

def test_audit_report_line_2_vulnerable_code():
    with open(REPORT_PATH, "r") as f:
        lines = [line.strip('\n') for line in f.readlines()]
    expected_line = 'if [ "$ALG" == "none" ]; then'
    assert lines[1] == expected_line, f"Line 2 is incorrect. Expected '{expected_line}', got '{lines[1]}'"

def test_audit_report_line_3_world_writable_files():
    with open(REPORT_PATH, "r") as f:
        lines = [line.strip('\n') for line in f.readlines()]

    expected_files = get_world_writable_files(BASE_DIR)
    expected_line = ",".join(expected_files)

    assert lines[2] == expected_line, f"Line 3 is incorrect. Expected '{expected_line}', got '{lines[2]}'"

def test_audit_report_line_4_tampered_cert():
    with open(REPORT_PATH, "r") as f:
        lines = [line.strip('\n') for line in f.readlines()]

    expected_cert = get_tampered_cert(BASE_DIR) or "client.pem"

    assert lines[3] == expected_cert, f"Line 4 is incorrect. Expected '{expected_cert}', got '{lines[3]}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

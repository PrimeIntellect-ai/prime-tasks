#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import stat
import hashlib
import pytest

SERVICES_DIR = "/home/user/services"
VULNERABLE_SCRIPT = os.path.join(SERVICES_DIR, "sys_backup.sh")
CRACKED_PWD_FILE = "/home/user/cracked_password.txt"
AUDIT_LOG_FILE = "/home/user/audit_log.txt"

def test_cracked_password_file():
    assert os.path.isfile(CRACKED_PWD_FILE), f"File {CRACKED_PWD_FILE} does not exist."
    with open(CRACKED_PWD_FILE, "r") as f:
        content = f.read().strip()
    assert content == "admin8374", f"Expected cracked password 'admin8374', but got '{content}'."

def test_script_permissions():
    assert os.path.isfile(VULNERABLE_SCRIPT), f"Script {VULNERABLE_SCRIPT} does not exist."
    st = os.stat(VULNERABLE_SCRIPT)
    perms = stat.S_IMODE(st.st_mode)
    assert perms == 0o755, f"Permissions of {VULNERABLE_SCRIPT} should be 755, but got {oct(perms)}."

def test_script_content_credentials():
    assert os.path.isfile(VULNERABLE_SCRIPT), f"Script {VULNERABLE_SCRIPT} does not exist."
    with open(VULNERABLE_SCRIPT, "r") as f:
        content = f.read()

    # The new password is SecureBackup2024!
    new_pwd_hash = hashlib.sha256(b"SecureBackup2024!").hexdigest()
    expected_line = f'NEW_SECRET_HASH="{new_pwd_hash}"'

    assert expected_line in content, f"Script does not contain the expected NEW_SECRET_HASH variable with the new SHA-256 hash."
    assert "SECRET_HASH=" not in content.replace("NEW_SECRET_HASH=", ""), "The old SECRET_HASH variable was not properly removed or renamed."

def test_audit_log_checksum():
    assert os.path.isfile(VULNERABLE_SCRIPT), f"Script {VULNERABLE_SCRIPT} does not exist."
    assert os.path.isfile(AUDIT_LOG_FILE), f"File {AUDIT_LOG_FILE} does not exist."

    # Compute actual sha256 of the modified script
    with open(VULNERABLE_SCRIPT, "rb") as f:
        script_data = f.read()
    actual_checksum = hashlib.sha256(script_data).hexdigest()

    expected_audit_content = f"CHECKSUM: {actual_checksum}"

    with open(AUDIT_LOG_FILE, "r") as f:
        audit_content = f.read().strip()

    assert audit_content == expected_audit_content, f"Audit log does not contain the correct checksum. Expected '{expected_audit_content}', got '{audit_content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

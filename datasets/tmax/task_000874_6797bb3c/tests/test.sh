#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import stat

TARGET_FILE = "/home/user/compromised_users.txt"

def test_compromised_users_file_exists():
    """Verify that the output file was created at the exact required path."""
    assert os.path.exists(TARGET_FILE), f"The file {TARGET_FILE} does not exist."
    assert os.path.isfile(TARGET_FILE), f"The path {TARGET_FILE} exists but is not a regular file."

def test_compromised_users_file_permissions():
    """Verify that the output file has strictly 600 permissions."""
    assert os.path.exists(TARGET_FILE), f"Cannot check permissions: {TARGET_FILE} does not exist."

    file_stat = os.stat(TARGET_FILE)
    permissions = stat.S_IMODE(file_stat.st_mode)

    # 0o600 is the octal representation of -rw-------
    assert permissions == 0o600, (
        f"Incorrect permissions on {TARGET_FILE}. "
        f"Expected 600 (octal), but got {oct(permissions).replace('0o', '')}."
    )

def test_compromised_users_file_contents():
    """
    Verify that the output file contains the correct usernames, 
    sorted alphabetically, with no duplicates.
    """
    assert os.path.exists(TARGET_FILE), f"Cannot check contents: {TARGET_FILE} does not exist."

    with open(TARGET_FILE, "r") as f:
        content = f.read().strip()

    lines = [line.strip() for line in content.splitlines() if line.strip()]

    # Based on the setup script:
    # T1: admin (evil.com, future) -> Valid
    # T2: bob_the_builder (attacker.net, future) -> Valid
    # T3: alice_wonder (evil.com, past) -> Invalid (expired)
    # T4: charlie_root (app.local, future) -> Invalid (not an open redirect)
    # T5: zack_admin (phishing-site.org, future) -> Valid
    expected_users = ["admin", "bob_the_builder", "zack_admin"]

    assert lines == expected_users, (
        f"The contents of {TARGET_FILE} do not match the expected output.\n"
        f"Expected (sorted): {expected_users}\n"
        f"Actual: {lines}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

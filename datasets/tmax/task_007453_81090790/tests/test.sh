#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import stat
import subprocess
import pytest

TOKEN_PATH = "/home/user/admin_token.jwt"
VERIFY_SCRIPT = "/home/user/verify.py"

def test_admin_token_exists():
    """Test that the admin_token.jwt file exists."""
    assert os.path.exists(TOKEN_PATH), f"Target file does not exist: {TOKEN_PATH}"
    assert os.path.isfile(TOKEN_PATH), f"Target is not a file: {TOKEN_PATH}"

def test_admin_token_permissions():
    """Test that the admin_token.jwt file has exactly 0400 permissions."""
    assert os.path.exists(TOKEN_PATH), f"Target file does not exist: {TOKEN_PATH}"
    file_stat = os.stat(TOKEN_PATH)
    permissions = stat.S_IMODE(file_stat.st_mode)
    assert permissions == 0o400, f"Permissions of {TOKEN_PATH} are {oct(permissions)}, expected 0o400"

def test_verify_script_success():
    """Test that the verify script grants admin access when run with the token."""
    assert os.path.exists(TOKEN_PATH), f"Target file does not exist: {TOKEN_PATH}"
    assert os.path.exists(VERIFY_SCRIPT), f"Verify script does not exist: {VERIFY_SCRIPT}"

    result = subprocess.run(
        ["python3", VERIFY_SCRIPT, TOKEN_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True
    )

    assert result.returncode == 0, f"Verify script failed with exit code {result.returncode}. Output: {result.stdout} {result.stderr}"
    assert "Access granted: admin" in result.stdout, f"Verify script did not grant admin access. Output: {result.stdout}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

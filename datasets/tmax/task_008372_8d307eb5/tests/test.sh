#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import stat
import pytest

def test_client_key_permissions_fixed():
    key_path = '/home/user/certs/client.key'
    assert os.path.exists(key_path), f"Client key {key_path} is missing."

    st = os.stat(key_path)
    perms = stat.S_IMODE(st.st_mode)

    # Secure permissions mean no access for group or others.
    # Usually 0o600 (owner read/write) or 0o400 (owner read).
    assert not (perms & stat.S_IRWXG), f"Group permissions are still set on {key_path}: {oct(perms)}"
    assert not (perms & stat.S_IRWXO), f"Others permissions are still set on {key_path}: {oct(perms)}"
    assert (perms & stat.S_IRUSR), f"Owner must have at least read access to {key_path}: {oct(perms)}"

def test_extracted_flag_file_exists():
    flag_path = '/home/user/extracted_flag.txt'
    assert os.path.isfile(flag_path), f"The file {flag_path} does not exist. The flag was not saved."

def test_extracted_flag_contents():
    flag_path = '/home/user/extracted_flag.txt'
    assert os.path.isfile(flag_path), f"The file {flag_path} does not exist."

    with open(flag_path, 'r') as f:
        content = f.read().strip()

    expected_flag = "SECURE_FLAG_{mTLS_and_c0mmand_inj3ction_m4ster}"
    assert expected_flag in content, f"The extracted flag is incorrect. Found: {content}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_expired_cn_file():
    """Test that the expired_cn.txt file contains the correct Common Name."""
    target_file = "/home/user/expired_cn.txt"

    assert os.path.exists(target_file), f"The file {target_file} does not exist. Did you create it?"
    assert os.path.isfile(target_file), f"The path {target_file} is not a file."

    with open(target_file, "r") as f:
        content = f.read().strip()

    expected_cn = "evil.bastion.local"
    assert content == expected_cn, f"The content of {target_file} is incorrect. Expected '{expected_cn}', but got '{content}'."

def test_backdoor_payload_file():
    """Test that the backdoor_payload.json file contains the correct decoded JSON payload."""
    target_file = "/home/user/backdoor_payload.json"

    assert os.path.exists(target_file), f"The file {target_file} does not exist. Did you create it?"
    assert os.path.isfile(target_file), f"The path {target_file} is not a file."

    with open(target_file, "r") as f:
        content = f.read().strip()

    expected_payload = '{"user":"backdoor","role":"system"}'
    assert content == expected_payload, f"The content of {target_file} is incorrect. Expected '{expected_payload}', but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

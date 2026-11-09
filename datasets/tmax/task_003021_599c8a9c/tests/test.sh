#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_payload_file_exists():
    assert os.path.isfile("/home/user/payload.txt"), "The /home/user/payload.txt file is missing."

def test_payload_file_content():
    expected_content = "client3.crt:F4llb4ck_Adm1n_992#"

    with open("/home/user/payload.txt", "r") as f:
        content = f.read().strip()

    assert content == expected_content, f"The content of payload.txt is incorrect. Expected '{expected_content}', got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

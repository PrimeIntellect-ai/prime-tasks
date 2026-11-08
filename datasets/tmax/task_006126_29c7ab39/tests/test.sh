#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_recovery_log_exists():
    log_path = "/home/user/recovery.log"
    assert os.path.isfile(log_path), f"The required file {log_path} does not exist."

def test_recovery_log_content():
    log_path = "/home/user/recovery.log"
    assert os.path.isfile(log_path), f"The required file {log_path} does not exist."

    with open(log_path, "r") as f:
        content = f.read().strip()

    expected_content = "TXN=TXN-8849-ACBD-1102, KEY=sk_live_77a91b34f829c011x"

    assert content == expected_content, (
        f"The content of {log_path} is incorrect.\n"
        f"Expected: '{expected_content}'\n"
        f"Found: '{content}'"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

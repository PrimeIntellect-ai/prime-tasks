#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_flag_extracted_correctly():
    """Verify that the secret flag was successfully extracted and saved to /home/user/flag.txt."""
    flag_path = "/home/user/flag.txt"

    assert os.path.exists(flag_path), f"Flag file not found at {flag_path}. The task requires saving the flag to this path."
    assert os.path.isfile(flag_path), f"{flag_path} is not a file."

    with open(flag_path, 'r') as f:
        content = f.read().strip()

    expected_flag = "FLAG{lin3ar_crypt4nalys1s_byp4ss_succ3ss}"

    assert expected_flag in content, f"The expected flag was not found in {flag_path}. Content found: {content}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

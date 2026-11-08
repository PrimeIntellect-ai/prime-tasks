#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import hashlib
import pytest

def test_exploit_url_exists_and_correct():
    exploit_file = "/home/user/exploit_url.txt"
    assert os.path.isfile(exploit_file), f"Output file {exploit_file} does not exist."

    secret = "auth_s3cr3t_2023!"
    target_url = "http://attacker.com/steal"

    # Recompute the expected signature to match the task's logic
    expected_sig = hashlib.md5((secret + target_url).encode()).hexdigest()
    expected_full_url = f"http://localhost:8080/login?redirect={target_url}&sig={expected_sig}"

    with open(exploit_file, 'r') as f:
        actual_content = f.read().strip()

    assert actual_content == expected_full_url, (
        f"The crafted URL in {exploit_file} is incorrect.\n"
        f"Expected: {expected_full_url}\n"
        f"Got: {actual_content}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

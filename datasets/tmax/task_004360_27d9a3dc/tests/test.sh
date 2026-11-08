#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_leaked_token_extracted():
    """Test that the authorization token was correctly extracted and saved."""
    token_file = "/home/user/leaked_token.txt"
    assert os.path.isfile(token_file), f"The file {token_file} does not exist."

    with open(token_file, "r") as f:
        content = f.read().strip()

    expected_token = "sec_v2_9f8e7d6c5b4a3_prod"
    assert content == expected_token, f"The extracted token is incorrect. Expected '{expected_token}', but got '{content}'."

def test_target_domain_extracted():
    """Test that the target domain was correctly extracted and saved."""
    domain_file = "/home/user/target_domain.txt"
    assert os.path.isfile(domain_file), f"The file {domain_file} does not exist."

    with open(domain_file, "r") as f:
        content = f.read().strip()

    expected_domain = "data.exfiltration-api.local"
    assert content == expected_domain, f"The extracted target domain is incorrect. Expected '{expected_domain}', but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

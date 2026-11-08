#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_report_txt_content():
    path = "/home/user/report.txt"
    assert os.path.exists(path), f"File {path} does not exist. Did you create the report?"

    with open(path, "r") as f:
        content = f.read().strip()

    expected_content = "192.168.5.99 stolen_token_xyz987"
    assert content == expected_content, f"Content of {path} is incorrect. Expected '{expected_content}', got '{content}'."

def test_policy_json_updated():
    path = "/home/user/policy.json"
    assert os.path.exists(path), f"File {path} does not exist."

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{path} is no longer valid JSON.")

    assert "blocked_ips" in data, f"{path} is missing the 'blocked_ips' key."
    assert isinstance(data["blocked_ips"], list), f"'blocked_ips' in {path} should be a list."

    blocked_ips = data["blocked_ips"]
    assert "1.2.3.4" in blocked_ips, "The original blocked IP '1.2.3.4' was removed from policy.json."
    assert "192.168.5.99" in blocked_ips, "The attacker's IP '192.168.5.99' was not added to 'blocked_ips' in policy.json."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

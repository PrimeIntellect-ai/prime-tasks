#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_findings_json_exists():
    assert os.path.isfile("/home/user/findings.json"), "The file /home/user/findings.json does not exist."

def test_findings_json_content():
    try:
        with open("/home/user/findings.json", "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail("The file /home/user/findings.json is not valid JSON.")
    except Exception as e:
        pytest.fail(f"Could not read /home/user/findings.json: {e}")

    assert "auth_token" in data, "The 'auth_token' key is missing in findings.json."
    assert data["auth_token"] == "super_secret_token_99", "The 'auth_token' value is incorrect."

    assert "target_suid_binary" in data, "The 'target_suid_binary' key is missing in findings.json."
    assert data["target_suid_binary"] == "/home/user/bin/backup_agent", "The 'target_suid_binary' value is incorrect."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

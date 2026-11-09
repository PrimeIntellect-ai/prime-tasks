#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json

def test_rotation_success_file():
    """Verify that the rotation success confirmation was captured correctly."""
    path = "/home/user/rotation_success.txt"
    assert os.path.isfile(path), f"File {path} does not exist. The confirmation was not saved."

    with open(path, "r") as f:
        content = f.read().strip()

    expected_confirmation = "ROTATED_8429_SUCCESS"
    assert content == expected_confirmation, f"Expected confirmation '{expected_confirmation}' in {path}, but got '{content}'."

def test_waf_rules_file():
    """Verify that the WAF rules JSON file is created with the correct structure."""
    path = "/home/user/waf_rules.json"
    assert os.path.isfile(path), f"File {path} does not exist. The WAF rule was not drafted."

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {path} does not contain valid JSON."

    expected_data = {
        "rules": [
            {
                "endpoint": "/admin/rotate_secret",
                "allowed_ips": ["127.0.0.1"],
                "action": "drop_others"
            }
        ]
    }

    assert data == expected_data, f"JSON content in {path} does not match the expected WAF rules structure."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

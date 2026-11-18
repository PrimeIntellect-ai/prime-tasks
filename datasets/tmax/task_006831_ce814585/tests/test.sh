#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_rotation_report_exists_and_correct():
    report_path = "/home/user/rotation_report.json"

    assert os.path.isfile(report_path), f"The report file {report_path} was not found."

    with open(report_path, "r") as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {report_path} does not contain valid JSON.")

    expected_keys = {"valid_api_key", "cracked_password", "cwe_id"}
    actual_keys = set(report_data.keys())

    missing_keys = expected_keys - actual_keys
    assert not missing_keys, f"The report is missing the following keys: {missing_keys}"

    assert report_data["valid_api_key"] == "f9b8c7d6e5", "The valid_api_key is incorrect. Did you find the key associated with the 200 status code?"
    assert report_data["cracked_password"] == "backup2023", "The cracked_password is incorrect. Did you crack the SHA256 hash correctly using the wordlist?"
    assert report_data["cwe_id"].upper() == "CWE-798", "The cwe_id is incorrect. Look up the standard CWE identifier for 'Use of Hard-coded Credentials'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

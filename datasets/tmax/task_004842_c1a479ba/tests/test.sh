#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_policy_report_exists_and_valid():
    report_path = "/home/user/policy_report.json"
    assert os.path.isfile(report_path), f"File {report_path} is missing."

    with open(report_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {report_path} is not a valid JSON file.")

    expected_keys = {"weak_crypto_cwe", "buffer_overflow_cwe", "decoded_payload"}
    assert set(data.keys()) == expected_keys, f"JSON keys in {report_path} do not match the expected keys. Found {list(data.keys())}."

def test_policy_report_values():
    report_path = "/home/user/policy_report.json"
    assert os.path.isfile(report_path), f"File {report_path} is missing."

    with open(report_path, "r") as f:
        data = json.load(f)

    expected_payload = "ELEVATE_TO_SYSTEM_R00T"
    assert data.get("decoded_payload") == expected_payload, f"Incorrect decoded_payload. Expected '{expected_payload}'."

    expected_weak_crypto_cwes = {"CWE-327"}
    assert data.get("weak_crypto_cwe") in expected_weak_crypto_cwes, f"Incorrect weak_crypto_cwe. Expected one of {expected_weak_crypto_cwes}."

    expected_buffer_overflow_cwes = {"CWE-120", "CWE-121", "CWE-119", "CWE-242"}
    assert data.get("buffer_overflow_cwe") in expected_buffer_overflow_cwes, f"Incorrect buffer_overflow_cwe. Expected one of {expected_buffer_overflow_cwes}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

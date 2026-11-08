#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_resolution_json_exists():
    path = "/home/user/resolution.json"
    assert os.path.isfile(path), f"Expected {path} to exist."

def test_resolution_json_content():
    path = "/home/user/resolution.json"
    assert os.path.isfile(path), f"Expected {path} to exist."

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{path} is not a valid JSON file.")

    assert "recovered_config" in data, "Missing 'recovered_config' key in resolution.json"
    assert "decoded_payload" in data, "Missing 'decoded_payload' key in resolution.json"

    config = data["recovered_config"]
    assert isinstance(config, dict), "'recovered_config' must be a JSON object (dictionary)."
    assert config.get("max_retries") == 5, "Expected 'max_retries' to be 5 in recovered_config"
    assert config.get("timeout") == 30, "Expected 'timeout' to be 30 in recovered_config"

    payload = data["decoded_payload"]
    assert isinstance(payload, str), "'decoded_payload' must be a string."
    expected_payload = '{"event":"critical_failure"}'
    assert payload == expected_payload, f"Expected 'decoded_payload' to be '{expected_payload}', got '{payload}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

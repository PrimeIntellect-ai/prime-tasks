#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import pytest


def get_expected_values():
    # Fixed oracle values are supplied only with the verifier, after the agent runs.
    # Do not derive them from the agent-modifiable repository.
    return "SECRET-99xJ2-44mAq-11bZw", "/v3/telemetry/ingest"


def test_fix_info_json_exists_and_valid():
    target_file = "/home/user/fix_info.json"
    assert os.path.isfile(target_file), f"Expected output file not found at {target_file}. Did you create it?"

    with open(target_file, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {target_file} does not contain valid JSON.")

    assert isinstance(data, dict), f"The JSON in {target_file} must be an object/dictionary."
    assert "api_key" in data, f"The JSON file {target_file} is missing the 'api_key' key."
    assert "endpoint" in data, f"The JSON file {target_file} is missing the 'endpoint' key."


def test_fix_info_json_contents():
    target_file = "/home/user/fix_info.json"
    if not os.path.isfile(target_file):
        pytest.skip("Output file missing, skipping content validation.")

    with open(target_file, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.skip("Output file is not valid JSON, skipping content validation.")

    expected_api_key, expected_endpoint = get_expected_values()

    actual_api_key = data.get("api_key")
    actual_endpoint = data.get("endpoint")

    assert actual_api_key == expected_api_key, (
        f"Incorrect api_key recovered. Expected '{expected_api_key}', but got '{actual_api_key}'."
    )

    assert actual_endpoint == expected_endpoint, (
        f"Incorrect endpoint recovered. Expected '{expected_endpoint}', but got '{actual_endpoint}'."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

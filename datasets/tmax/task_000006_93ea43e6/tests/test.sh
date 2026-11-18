#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_api_gateway_config_json_exists():
    """Test that the final JSON configuration file exists."""
    config_path = "/home/user/api_gateway_config.json"
    assert os.path.exists(config_path), f"The file {config_path} does not exist. Did you save the output to the correct path?"
    assert os.path.isfile(config_path), f"{config_path} must be a file."

def test_api_gateway_config_content():
    """Test that the final JSON configuration contains the correct reconstructed state."""
    config_path = "/home/user/api_gateway_config.json"
    assert os.path.exists(config_path), f"The file {config_path} does not exist."

    try:
        with open(config_path, 'r') as f:
            actual_config = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {config_path} does not contain valid JSON.")

    expected_config = {
        "port": "443",
        "timeout": "60",
        "host": "0.0.0.0",
        "banner": "Welcome to API Gateway!"
    }

    assert actual_config == expected_config, (
        f"The reconstructed configuration does not match the expected final state.\n"
        f"Expected: {expected_config}\n"
        f"Actual: {actual_config}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

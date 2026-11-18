#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_valid_traffic_log():
    valid_log_path = "/home/user/valid_traffic.log"
    expected_log_path = "/tests/.expected_valid_traffic.log"

    assert os.path.exists(valid_log_path), f"Missing {valid_log_path}. Did you create the output file?"
    assert os.path.isfile(valid_log_path), f"{valid_log_path} is not a file."

    with open(valid_log_path, "r") as f:
        actual_lines = f.readlines()

    with open(expected_log_path, "r") as f:
        expected_lines = f.readlines()

    assert len(actual_lines) == len(expected_lines), (
        f"Number of lines in {valid_log_path} ({len(actual_lines)}) "
        f"does not match expected ({len(expected_lines)})."
    )

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual.strip() == expected.strip(), (
            f"Line {i+1} mismatch in {valid_log_path}. "
            f"Expected '{expected.strip()}', got '{actual.strip()}'."
        )

def test_sshd_config_custom():
    config_path = "/home/user/sshd_config.custom"

    assert os.path.exists(config_path), f"Missing {config_path}. Did you create the SSH config snippet?"
    assert os.path.isfile(config_path), f"{config_path} is not a file."

    with open(config_path, "r") as f:
        lines = [line.strip() for line in f.readlines()]

    expected_configs = [
        "PermitRootLogin no",
        "PasswordAuthentication no",
        "Protocol 2"
    ]

    for config in expected_configs:
        assert config in lines, f"Missing required configuration '{config}' in {config_path}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

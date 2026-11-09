#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_faulty_sensor_file_exists():
    """Verify that the faulty_sensor.txt file has been created."""
    file_path = "/home/user/faulty_sensor.txt"
    assert os.path.isfile(file_path), f"The file {file_path} does not exist. Did you create it?"

def test_faulty_sensor_content():
    """Verify that the faulty_sensor.txt file contains the correct sensor_id."""
    file_path = "/home/user/faulty_sensor.txt"
    assert os.path.isfile(file_path), f"The file {file_path} does not exist."

    with open(file_path, "r", encoding="utf-8") as f:
        content = f.read().strip()

    expected_sensor = "BETA-02"
    assert content == expected_sensor, (
        f"The content of {file_path} is incorrect. "
        f"Expected '{expected_sensor}', but got '{content}'."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

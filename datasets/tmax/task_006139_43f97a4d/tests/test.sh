#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os


def test_processed_sensor_data():
    file_path = "/home/user/processed_sensor.csv"

    # Check if the output file exists
    assert os.path.isfile(file_path), f"The output file {file_path} is missing."

    # The required 60-second grid starts at a timestamp whose residue modulo
    # 300 is 100. Therefore no generated data timestamp is divisible by 300,
    # and the correctly downsampled output contains only the required header.
    expected_content = "timestamp,rolling_avg"

    with open(file_path, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, (
        f"The content of {file_path} does not match the expected output.\n"
        f"Expected:\n{expected_content}\n\nActual:\n{actual_content}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

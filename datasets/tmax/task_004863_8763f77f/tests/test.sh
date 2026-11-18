#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_processed_data_exists_and_correct():
    path = "/home/user/processed_data.csv"
    assert os.path.exists(path), f"Output file {path} is missing."
    assert os.path.isfile(path), f"{path} should be a file."

    expected_lines = [
        "timestamp,sensor_id,temperature,sma_3",
        "1672531200,A,20.00,",
        "1672531200,B,18.00,",
        "1672531260,A,21.50,",
        "1672531260,B,18.00,",
        "1672531320,A,21.50,21.00",
        "1672531320,B,19.00,18.33",
        "1672531380,A,22.00,21.67",
        "1672531380,B,19.50,18.83",
        "1672531440,A,23.00,22.17",
        "1672531440,B,20.00,19.50",
        "1672531500,A,22.50,22.50",
        "1672531500,B,20.00,19.83"
    ]

    with open(path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines, but got {len(actual_lines)}."

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, f"Mismatch at line {i + 1}:\nExpected: {expected}\nActual:   {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

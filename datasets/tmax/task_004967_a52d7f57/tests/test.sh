#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_anomaly_threshold_file():
    filepath = '/home/user/anomaly_threshold.txt'
    assert os.path.isfile(filepath), f"FAIL: {filepath} does not exist. The task requires writing the final threshold to this file."

    with open(filepath, 'r') as f:
        content = f.read().strip()

    # Check if the content is a valid float
    try:
        val = float(content)
    except ValueError:
        assert False, f"FAIL: The content of {filepath} ('{content}') is not a valid float."

    # Check if it has exactly 4 decimal places
    parts = content.split('.')
    assert len(parts) == 2 and len(parts[1]) == 4, f"FAIL: The threshold must be rounded to exactly 4 decimal places, got '{content}'."

    # Check against the deterministic expected value based on the fixed random seed in the setup
    expected_val = "8.0694"
    assert content == expected_val, f"FAIL: Expected threshold to be '{expected_val}', got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

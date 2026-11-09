#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_predictions_csv_exists_and_correct():
    filepath = '/home/user/predictions.csv'
    assert os.path.isfile(filepath), f"Output file {filepath} is missing. The script did not generate the required output."

    with open(filepath, 'r') as f:
        content = f.read().strip().split('\n')

    expected_content = [
        "id,predicted_label",
        "4,B",
        "5,B",
        "7,A",
        "11,A"
    ]

    assert len(content) == len(expected_content), f"Expected {len(expected_content)} rows in {filepath}, but found {len(content)}."

    for i, (actual, expected) in enumerate(zip(content, expected_content)):
        assert actual.strip() == expected, f"Row {i+1} in {filepath} is incorrect. Expected '{expected}', got '{actual.strip()}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

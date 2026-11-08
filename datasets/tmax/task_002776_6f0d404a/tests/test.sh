#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_features_file_exists():
    features_path = "/home/user/features.txt"
    assert os.path.isfile(features_path), f"Output file missing: {features_path}"

def test_features_content_matches_expected():
    features_path = "/home/user/features.txt"
    expected_path = "/tests/expected_features.txt"

    assert os.path.isfile(features_path), f"Output file missing: {features_path}"
    assert os.path.isfile(expected_path), f"Expected features file missing: {expected_path}"

    with open(features_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    with open(expected_path, "r") as f:
        expected_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines, but found {len(actual_lines)} lines in {features_path}"
    )

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        try:
            actual_val = float(actual)
            expected_val = float(expected)
            assert abs(actual_val - expected_val) <= 1e-4, (
                f"Line {i+1}: expected {expected}, got {actual}"
            )
        except ValueError:
            assert actual == expected, f"Line {i+1}: expected {expected}, got {actual} (non-numeric)"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

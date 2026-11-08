#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_high_load_regions_output():
    output_path = "/home/user/high_load_regions.txt"

    assert os.path.isfile(output_path), f"Expected output file {output_path} is missing."

    with open(output_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_regions = [
        "eu-central",
        "us-east",
        "us-west"
    ]

    assert lines == expected_regions, (
        f"Contents of {output_path} do not match the expected output. "
        f"Expected: {expected_regions}, Got: {lines}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

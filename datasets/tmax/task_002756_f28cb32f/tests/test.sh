#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

OUTPUT_FILE = '/home/user/sod_violators.txt'

def test_output_file_exists():
    """Verify that the output file was created."""
    assert os.path.exists(OUTPUT_FILE), f"Output file not found at {OUTPUT_FILE}"
    assert os.path.isfile(OUTPUT_FILE), f"{OUTPUT_FILE} is not a file"

def test_output_file_contents():
    """Verify that the output file contains the correct SoD violators."""
    assert os.path.exists(OUTPUT_FILE), f"Cannot check contents, {OUTPUT_FILE} does not exist"

    with open(OUTPUT_FILE, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_violators = ['E001', 'E002', 'E004']

    assert lines == expected_violators, (
        f"Contents of {OUTPUT_FILE} are incorrect. "
        f"Expected: {expected_violators}, but got: {lines}. "
        "Ensure you are correctly handling the latest access events and transitive inheritance."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

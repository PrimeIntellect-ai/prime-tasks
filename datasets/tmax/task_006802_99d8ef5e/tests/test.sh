#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_bottleneck_file_exists_and_correct():
    output_path = "/home/user/bottleneck.txt"

    # Check if the output file exists
    assert os.path.isfile(output_path), f"Expected output file {output_path} does not exist."

    # Read the content of the output file
    with open(output_path, "r") as f:
        content = f.read().strip()

    # Check if the content matches the expected output
    expected_content = "JobC,0.2088"

    assert content == expected_content, (
        f"Content of {output_path} is incorrect. "
        f"Expected '{expected_content}', but got '{content}'."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

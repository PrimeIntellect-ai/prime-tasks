#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_self_cite_count_file_exists():
    """Check if the output file was created."""
    output_file = "/home/user/self_cite_count.txt"
    assert os.path.isfile(output_file), f"Output file {output_file} does not exist."

def test_self_cite_count_value():
    """Check if the output file contains the correct self-citation count."""
    output_file = "/home/user/self_cite_count.txt"

    with open(output_file, 'r') as f:
        content = f.read().strip()

    assert content == "7", f"Expected count to be '7', but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

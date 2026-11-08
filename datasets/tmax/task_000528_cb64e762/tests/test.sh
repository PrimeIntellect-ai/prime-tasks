#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def test_closest_pair_file_exists():
    output_file = "/home/user/closest_pair.txt"
    assert os.path.exists(output_file), f"Output file does not exist at {output_file}"
    assert os.path.isfile(output_file), f"Path {output_file} is not a file"

def test_closest_pair_content():
    output_file = "/home/user/closest_pair.txt"
    assert os.path.exists(output_file), f"Output file does not exist at {output_file}"

    with open(output_file, "r") as f:
        content = f.read().strip()

    expected = "apple,banana"
    assert content == expected, f"Expected '{expected}', but got '{content}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

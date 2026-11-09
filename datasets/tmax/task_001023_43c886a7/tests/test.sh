#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os

def test_total_print_time_file_exists():
    """Check if the output file exists."""
    filepath = "/home/user/total_print_time.txt"
    assert os.path.exists(filepath), f"Output file {filepath} does not exist."
    assert os.path.isfile(filepath), f"Path {filepath} is not a file."

def test_total_print_time_value():
    """Verify that the total print time is calculated correctly."""
    filepath = "/home/user/total_print_time.txt"
    assert os.path.exists(filepath), f"Output file {filepath} does not exist."

    with open(filepath, "r") as f:
        content = f.read().strip()

    assert content == "700", f"Expected total print time to be 700, but got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

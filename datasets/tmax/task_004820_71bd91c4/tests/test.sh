#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def get_expected_ticket():
    """Derive the expected ticket ID based on the crash condition."""
    for i in range(10000):
        if (i * 7) % 9999 == 4321:
            return f"TICKET_{i:04d}"
    return "TICKET_6331"  # Fallback just in case

def test_crash_input_file_content():
    """Check that the output file contains the correct crash-inducing ticket ID."""
    output_path = "/home/user/crash_input.txt"
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist. Task not completed."

    with open(output_path, "r") as f:
        content = f.read().strip()

    expected = get_expected_ticket()
    assert content == expected, f"File {output_path} contains '{content}', but expected '{expected}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

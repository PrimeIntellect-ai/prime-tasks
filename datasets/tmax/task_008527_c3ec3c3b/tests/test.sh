#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os

def test_diagnostics_file_exists():
    file_path = "/home/user/diagnostics.txt"
    assert os.path.isfile(file_path), f"The file {file_path} does not exist."

def test_diagnostics_file_content():
    file_path = "/home/user/diagnostics.txt"
    assert os.path.isfile(file_path), f"The file {file_path} does not exist."

    with open(file_path, "r") as f:
        content = f.read().strip().splitlines()

    assert len(content) == 2, f"Expected exactly 2 lines in {file_path}, but found {len(content)}."

    expected_line1 = "PASSWORD: p4ssw0rd_123_!$"
    expected_line2 = "SEGFAULT_ADDR: 0x7ffd5e3a9b20"

    assert content[0] == expected_line1, f"Expected first line to be '{expected_line1}', but got '{content[0]}'."
    assert content[1] == expected_line2, f"Expected second line to be '{expected_line2}', but got '{content[1]}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

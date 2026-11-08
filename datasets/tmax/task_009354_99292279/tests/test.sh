#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json

def test_decoder_cpp_exists():
    """Validates that the student created the C++ decoder program."""
    path = "/home/user/decoder.cpp"
    assert os.path.isfile(path), f"The required C++ decoder program was not found at {path}."

def test_flag_file_exists_and_correct():
    """Validates that the flag was successfully extracted and saved to flag.txt."""
    path = "/home/user/flag.txt"
    assert os.path.isfile(path), f"The flag file was not found at {path}. Did you successfully scan the backdoor endpoints?"

    with open(path, 'r', encoding='utf-8') as f:
        content = f.read().strip()

    # The setup script specifically returns this JSON payload: {"flag": "FLAG{cxx_vuln_sc4nn3r_991}"}
    # We check if the expected flag string is present in the file.
    expected_flag = "FLAG{cxx_vuln_sc4nn3r_991}"

    assert expected_flag in content, (
        f"The content of {path} does not contain the correct flag. "
        f"Ensure you extracted the 'flag' field from the successful JSON response."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

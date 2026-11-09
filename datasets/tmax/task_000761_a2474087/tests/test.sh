#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

def test_decrypted_file_exists_and_content():
    output_file = "/home/user/decrypted.txt"
    expected_content = "network_admin_ok"

    assert os.path.exists(output_file), f"The file {output_file} is missing. Did you save the decrypted token?"
    assert os.path.isfile(output_file), f"{output_file} should be a regular file."

    with open(output_file, "r") as f:
        content = f.read()

    assert content == expected_content, f"The content of {output_file} is incorrect. Expected '{expected_content}', but got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os

def test_decrypted_secret():
    path = "/home/user/decrypted_secret.txt"
    assert os.path.isfile(path), f"File {path} does not exist."

    with open(path, "r") as f:
        content = f.read()

    expected = "OPERATION_MIDNIGHT_ECLIPSE"
    assert content == expected, f"File {path} content is incorrect. Expected '{expected}', got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

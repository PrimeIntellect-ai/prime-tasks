#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import struct


def expected_key():
    result = 1.0
    for i in range(1, 10001):
        factor_f32 = struct.unpack("<f", struct.pack("<f", 1.0 + 1.0 / i))[0]
        result *= factor_f32
    return f"{result:.5f}"


def test_key_txt_content():
    key_path = "/home/user/key.txt"
    assert os.path.exists(key_path), f"File {key_path} does not exist. The task requires saving the key to this file."
    assert os.path.isfile(key_path), f"{key_path} is not a file."

    with open(key_path, "r") as f:
        content = f.read().strip()

    expected = expected_key()
    assert content == expected, f"Expected key to be '{expected}', but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

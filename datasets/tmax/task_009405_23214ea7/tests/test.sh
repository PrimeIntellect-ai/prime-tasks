#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_optimal_k_file():
    file_path = "/home/user/optimal_k.txt"
    assert os.path.exists(file_path), f"The file {file_path} does not exist."
    assert os.path.isfile(file_path), f"{file_path} is not a file."

def test_optimal_k_content():
    file_path = "/home/user/optimal_k.txt"
    assert os.path.exists(file_path), f"The file {file_path} does not exist."

    with open(file_path, "r") as f:
        content = f.read().strip()

    expected = "4,89.7150"
    assert content == expected, f"Expected contents '{expected}', but got '{content}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

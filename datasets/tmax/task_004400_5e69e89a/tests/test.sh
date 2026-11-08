#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_closest_pair_file_exists():
    path = "/home/user/closest_pair.txt"
    assert os.path.exists(path), f"Missing file: {path}"
    assert os.path.isfile(path), f"Not a file: {path}"

def test_closest_pair_content():
    path = "/home/user/closest_pair.txt"
    assert os.path.exists(path), f"Missing file: {path}"

    with open(path, 'r', encoding='utf-8') as f:
        content = f.read().strip()

    expected = "5011,5013"
    assert content == expected, f"Incorrect closest pair output. Expected '{expected}', but got '{content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

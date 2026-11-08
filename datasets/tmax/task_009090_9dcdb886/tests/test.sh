#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_max_error_file_exists():
    path = "/home/user/max_error.txt"
    assert os.path.isfile(path), f"The file {path} was not created."

def test_max_error_content():
    path = "/home/user/max_error.txt"
    assert os.path.isfile(path), f"The file {path} was not created."

    with open(path, "r") as f:
        content = f.read().strip()

    assert content == "0.050", f"Expected max error to be '0.050', but got '{content}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_emerging_terms_file_exists():
    path = "/home/user/emerging_terms.txt"
    assert os.path.isfile(path), f"The file {path} does not exist."

def test_emerging_terms_content():
    path = "/home/user/emerging_terms.txt"
    assert os.path.isfile(path), f"The file {path} does not exist."

    with open(path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_terms = ["floob", "widget", "zarkon"]

    assert lines == expected_terms, (
        f"Contents of {path} do not match the expected output. "
        f"Expected {expected_terms}, but got {lines}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

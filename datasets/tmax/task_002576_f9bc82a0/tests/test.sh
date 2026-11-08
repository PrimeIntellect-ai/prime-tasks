#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_config_path():
    path = "/home/user/config_path.txt"
    assert os.path.isfile(path), f"Missing file: {path}"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "/home/user/.secret_factor", f"Expected '/home/user/.secret_factor' in {path}, got '{content}'"

def test_minimal_crash():
    path = "/home/user/minimal_crash.txt"
    assert os.path.isfile(path), f"Missing file: {path}"
    with open(path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]
    expected_lines = ["42", "17", "99"]
    assert lines == expected_lines, f"Expected {expected_lines} in {path}, got {lines}"

def test_accumulator_state():
    path = "/home/user/accumulator_state.txt"
    assert os.path.isfile(path), f"Missing file: {path}"
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "159", f"Expected '159' in {path}, got '{content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_resolution_file_exists_and_correct():
    resolution_path = "/home/user/resolution.txt"
    assert os.path.exists(resolution_path), f"File {resolution_path} does not exist. You need to create it."

    with open(resolution_path, "r", encoding="utf-8") as f:
        content = f.read().strip()

    expected_content = (
        "Module: 74A9\n"
        "ErrorCode: MEM_FAULT_X99_FATAL\n"
        "MissingFunction: InitHardware_v2"
    )

    assert content == expected_content, (
        f"The content of {resolution_path} is incorrect.\n"
        f"Expected:\n{expected_content}\n\n"
        f"Actual:\n{content}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

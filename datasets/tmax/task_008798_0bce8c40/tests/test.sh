#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import pytest

def test_secret_found_file():
    path = "/home/user/secret_found.txt"
    assert os.path.exists(path), f"File {path} does not exist. You must create it."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "B1LD_S3CR3T", f"Incorrect secret string in {path}."

def test_magic_token_file():
    path = "/home/user/project/magic_token.txt"
    assert os.path.exists(path), f"File {path} does not exist. The generator needs it."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "B1LD_S3CR3T", f"Incorrect content in {path}."

def test_main_execution():
    main_path = "/home/user/project/main"
    assert os.path.exists(main_path), f"Executable {main_path} not found. Did you run build.sh successfully?"

    result = subprocess.run([main_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Running {main_path} failed with exit code {result.returncode}."
    assert "Success! Magic: 42" in result.stdout, f"Output of {main_path} was incorrect. Got: {result.stdout}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

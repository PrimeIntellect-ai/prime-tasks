#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import pytest

def test_vulnerable_function_txt():
    path = "/home/user/vulnerable_function.txt"
    assert os.path.exists(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "parse_name_field", f"Expected 'parse_name_field', but got '{content}'"

def test_crash_payload_txt_format():
    path = "/home/user/crash_payload.txt"
    assert os.path.exists(path), f"File {path} does not exist."
    with open(path, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()

    assert content.startswith("SECURE_CONF_v1\nNAME:"), "Payload does not start with 'SECURE_CONF_v1\\nNAME:'"

def test_crash_payload_causes_segfault():
    payload_path = "/home/user/crash_payload.txt"
    binary_path = "/home/user/bin/suspicious_parser"

    assert os.path.exists(payload_path), f"File {payload_path} does not exist."
    assert os.path.exists(binary_path), f"Binary {binary_path} does not exist."

    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = "/home/user/.local/lib"
    env["AUTH_MODE"] = "DEBUG"

    process = subprocess.Popen(
        [binary_path, payload_path],
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    process.communicate()

    # Check for segmentation fault (return code 139 or -11 in Python's subprocess)
    assert process.returncode in (139, -11), f"Expected segmentation fault (exit code 139 or -11), but got {process.returncode}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

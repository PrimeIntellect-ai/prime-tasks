#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import pytest

def test_poison_line_txt():
    path = "/home/user/poison_line.txt"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()
    expected = "REQ_METHOD:POST PATH:/api/v1/data ID:7781-FAIL-99"
    assert content == expected, f"Expected {path} to contain '{expected}', but found '{content}'."

def test_leak_id_txt():
    path = "/home/user/leak_id.txt"
    assert os.path.isfile(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()
    expected = "SESS88392011X"
    assert content == expected, f"Expected {path} to contain '{expected}', but found '{content}'."

def test_processor_service_compiles():
    work_dir = "/home/user/processor_service"
    assert os.path.isdir(work_dir), f"Directory {work_dir} does not exist."

    # Run cargo build to verify the build.rs fix
    result = subprocess.run(
        ["cargo", "build"],
        cwd=work_dir,
        capture_output=True,
        text=True
    )
    assert result.returncode == 0, (
        f"cargo build failed in {work_dir}.\n"
        f"STDOUT:\n{result.stdout}\n"
        f"STDERR:\n{result.stderr}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

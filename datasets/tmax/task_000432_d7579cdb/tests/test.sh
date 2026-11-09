#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

def test_libparser_exists():
    assert os.path.isfile("/home/user/libparser.so"), "Shared library /home/user/libparser.so is missing."

def test_process_artifact_exists():
    assert os.path.isfile("/home/user/process_artifact.py"), "Python script /home/user/process_artifact.py is missing."

def test_fuzz_equivalence():
    oracle_path = "/tests/oracle_parser"
    agent_cmd = ["python3", "/home/user/process_artifact.py"]

    assert os.path.isfile(oracle_path), f"Oracle missing at {oracle_path}"
    assert os.access(oracle_path, os.X_OK), f"Oracle at {oracle_path} is not executable"

    random.seed(42)
    N = 10000

    for i in range(N):
        length = random.randint(0, 128)
        input_data = bytes([random.randint(0, 255) for _ in range(length)])

        oracle_proc = subprocess.run([oracle_path], input=input_data, capture_output=True)
        agent_proc = subprocess.run(agent_cmd, input=input_data, capture_output=True)

        assert oracle_proc.returncode == agent_proc.returncode, (
            f"Return code mismatch on input length {length} (hex: {input_data.hex()}). "
            f"Oracle returned {oracle_proc.returncode}, agent returned {agent_proc.returncode}. "
            f"Agent stderr: {agent_proc.stderr.decode(errors='replace')}"
        )

        if oracle_proc.returncode == 0:
            assert oracle_proc.stdout == agent_proc.stdout, (
                f"Stdout mismatch on input length {length} (hex: {input_data.hex()}). "
                f"Oracle stdout: {oracle_proc.stdout.hex()}, Agent stdout: {agent_proc.stdout.hex()}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

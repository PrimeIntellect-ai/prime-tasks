#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import pytest

def test_checksum_script_exists_and_executable():
    path = "/home/user/checksum.sh"
    assert os.path.isfile(path), f"Agent's script {path} is missing."
    assert os.access(path, os.X_OK), f"Agent's script {path} is not executable."

def test_fuzz_equivalence():
    oracle_path = "/tests/oracle.sh"
    agent_path = "/home/user/checksum.sh"

    assert os.path.isfile(oracle_path), f"Oracle script {oracle_path} is missing."
    assert os.path.isfile(agent_path), f"Agent script {agent_path} is missing."

    random.seed(42)
    N = 500
    min_val = 0
    max_val = 100000

    inputs = [random.randint(min_val, max_val) for _ in range(N)]

    for val in inputs:
        val_str = str(val)

        try:
            oracle_res = subprocess.run([oracle_path, val_str], capture_output=True, text=True, timeout=2)
            oracle_out = oracle_res.stdout.strip()
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle script timed out on input {val_str}")

        try:
            agent_res = subprocess.run([agent_path, val_str], capture_output=True, text=True, timeout=2)
            agent_out = agent_res.stdout.strip()
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent script timed out on input {val_str}")

        assert agent_res.returncode == oracle_res.returncode, f"Return code mismatch on input {val_str}: expected {oracle_res.returncode}, got {agent_res.returncode}"
        assert agent_out == oracle_out, f"Output mismatch on input {val_str}: expected '{oracle_out}', got '{agent_out}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

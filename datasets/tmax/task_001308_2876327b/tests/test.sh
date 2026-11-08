#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import pytest

def test_fasthash_executable_exists():
    agent_bin = "/home/user/fasthash_fixed"
    assert os.path.exists(agent_bin), f"Agent binary not found at {agent_bin}"
    assert os.path.isfile(agent_bin), f"Path is not a file: {agent_bin}"
    assert os.access(agent_bin, os.X_OK), f"Agent binary is not executable: {agent_bin}"

def test_fuzz_equivalence():
    agent_bin = "/home/user/fasthash_fixed"
    oracle_bin = "/app/oracle_bin"

    assert os.path.exists(oracle_bin), f"Oracle binary not found at {oracle_bin}"
    assert os.access(oracle_bin, os.X_OK), f"Oracle binary is not executable: {oracle_bin}"
    assert os.path.exists(agent_bin), f"Agent binary not found at {agent_bin}"
    assert os.access(agent_bin, os.X_OK), f"Agent binary is not executable: {agent_bin}"

    random.seed(42)
    N = 10000

    for i in range(N):
        length = random.randint(0, 4096)
        input_data = random.randbytes(length)

        oracle_proc = subprocess.run([oracle_bin], input=input_data, capture_output=True)
        agent_proc = subprocess.run([agent_bin], input=input_data, capture_output=True)

        oracle_out = oracle_proc.stdout
        agent_out = agent_proc.stdout

        assert oracle_proc.returncode == 0, f"Oracle crashed on input {i} (length {length})"
        assert agent_proc.returncode == 0, f"Agent crashed on input {i} (length {length})"

        assert oracle_out == agent_out, (
            f"Mismatch on input {i} (length {length}).\n"
            f"Oracle output: {oracle_out!r}\n"
            f"Agent output: {agent_out!r}\n"
            f"Input data (first 32 bytes): {input_data[:32]!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

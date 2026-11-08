#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

AGENT_BIN = "/home/user/fixed_bin"
ORACLE_BIN = "/app/oracle_bin"
N_TESTS = 5000
CHARSET = "0123456789 \n\t\rabcdefghijklmnopqrstuvwxyz!@#"

def test_agent_bin_exists():
    assert os.path.isfile(AGENT_BIN), f"Agent binary not found at {AGENT_BIN}"
    assert os.access(AGENT_BIN, os.X_OK), f"Agent binary at {AGENT_BIN} is not executable"

def test_oracle_bin_exists():
    assert os.path.isfile(ORACLE_BIN), f"Oracle binary not found at {ORACLE_BIN}"
    assert os.access(ORACLE_BIN, os.X_OK), f"Oracle binary at {ORACLE_BIN} is not executable"

def test_fuzz_equivalence():
    random.seed(42)

    for i in range(N_TESTS):
        length = random.randint(0, 2048)
        input_data = "".join(random.choice(CHARSET) for _ in range(length)).encode('utf-8')

        try:
            oracle_proc = subprocess.run(
                [ORACLE_BIN],
                input=input_data,
                capture_output=True,
                timeout=2
            )
            oracle_out = oracle_proc.stdout
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle binary timed out on input length {length}")

        try:
            agent_proc = subprocess.run(
                [AGENT_BIN],
                input=input_data,
                capture_output=True,
                timeout=2
            )
            agent_out = agent_proc.stdout
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent binary timed out on input length {length}. Input data (first 100 chars): {input_data[:100]}")

        if agent_proc.returncode != oracle_proc.returncode:
            pytest.fail(f"Return code mismatch! Oracle: {oracle_proc.returncode}, Agent: {agent_proc.returncode}. Input data (first 100 chars): {input_data[:100]}")

        if agent_out != oracle_out:
            pytest.fail(
                f"Output mismatch on test {i+1}/{N_TESTS}!\n"
                f"Input data (first 100 chars): {input_data[:100]}\n"
                f"Oracle output (first 100 chars): {oracle_out[:100]}\n"
                f"Agent output (first 100 chars): {agent_out[:100]}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

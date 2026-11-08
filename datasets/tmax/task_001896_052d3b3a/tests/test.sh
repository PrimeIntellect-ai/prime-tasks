#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

def test_fuzz_equivalence():
    agent_binary = "/home/user/hash_util/target/release/hash_util"
    oracle_binary = "/tests/oracle"

    assert os.path.isfile(agent_binary), f"Agent binary not found at {agent_binary}. Did you compile with 'cargo build --release'?"
    assert os.access(agent_binary, os.X_OK), f"Agent binary at {agent_binary} is not executable."

    assert os.path.isfile(oracle_binary), f"Oracle binary not found at {oracle_binary}."
    assert os.access(oracle_binary, os.X_OK), f"Oracle binary at {oracle_binary} is not executable."

    random.seed(42)
    num_iterations = 1000

    for i in range(num_iterations):
        length = random.randint(10, 500)
        input_bytes = bytes(random.choices(range(256), k=length))

        try:
            oracle_proc = subprocess.run(
                [oracle_binary],
                input=input_bytes,
                capture_output=True,
                check=True,
                timeout=2
            )
            oracle_output = oracle_proc.stdout.decode('utf-8').strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on iteration {i} with input length {length}. Error: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on iteration {i}.")

        try:
            agent_proc = subprocess.run(
                [agent_binary],
                input=input_bytes,
                capture_output=True,
                check=True,
                timeout=2
            )
            agent_output = agent_proc.stdout.decode('utf-8').strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent binary failed on iteration {i} with input length {length}. Error: {e.stderr.decode('utf-8', errors='replace')}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent binary timed out on iteration {i}. Make sure it processes stdin until EOF efficiently.")

        assert agent_output == oracle_output, (
            f"Mismatch on iteration {i} (input length {length}).\n"
            f"Oracle output: {oracle_output}\n"
            f"Agent output:  {agent_output}\n"
            f"Input bytes (hex): {input_bytes.hex()}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

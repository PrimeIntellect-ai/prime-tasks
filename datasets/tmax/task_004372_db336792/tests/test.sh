#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import pytest

def test_fuzz_equivalence():
    oracle_path = "/app/legacy_packer"
    agent_path = "/home/user/packer.py"

    assert os.path.exists(oracle_path), f"Oracle binary missing at {oracle_path}"
    assert os.path.exists(agent_path), f"Agent script missing at {agent_path}"

    # Fixed seed for reproducibility
    random.seed(42)

    N = 500
    for i in range(N):
        # Uniformly distributed length between 0 and 1,048,576 bytes
        length = random.randint(0, 1048576)

        # Generate random binary blob
        input_data = random.randbytes(length)

        # Run oracle
        try:
            oracle_proc = subprocess.run(
                [oracle_path],
                input=input_data,
                capture_output=True,
                check=True
            )
            oracle_out = oracle_proc.stdout
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on iteration {i} with input length {length}. Stderr: {e.stderr}")

        # Run agent
        try:
            agent_proc = subprocess.run(
                ["python3", agent_path],
                input=input_data,
                capture_output=True,
                check=True
            )
            agent_out = agent_proc.stdout
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent script failed on iteration {i} with input length {length}. Stderr: {e.stderr.decode(errors='replace')}")

        # Compare outputs
        if oracle_out != agent_out:
            pytest.fail(
                f"Output mismatch on iteration {i} with input length {length}.\n"
                f"Oracle output length: {len(oracle_out)} bytes\n"
                f"Agent output length: {len(agent_out)} bytes\n"
                f"Ensure the compression settings, magic bytes, endianness, and structure are bit-exact."
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

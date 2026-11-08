#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import string
import subprocess
import pytest

def test_validator_exists_and_executable():
    agent_path = "/home/user/validator/target/release/validator"
    assert os.path.isfile(agent_path), f"Expected agent binary not found at {agent_path}"
    assert os.access(agent_path, os.X_OK), f"Agent binary at {agent_path} is not executable"

def test_fuzz_equivalence():
    oracle_path = "/app/oracle_validator"
    agent_path = "/home/user/validator/target/release/validator"

    assert os.path.isfile(oracle_path), f"Oracle binary missing at {oracle_path}"

    random.seed(42)
    chars = string.ascii_letters + string.digits

    # Generate 5000 random alphanumeric tokens of length 8 to 32
    tokens = []
    for _ in range(5000):
        length = random.randint(8, 32)
        token = ''.join(random.choice(chars) for _ in range(length))
        tokens.append([token])

    # Add some edge cases
    tokens.append([]) # No arguments
    tokens.append(["token1", "token2"]) # Too many arguments
    tokens.append([""]) # Empty token

    for args in tokens:
        oracle_cmd = [oracle_path] + args
        agent_cmd = [agent_path] + args

        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)

        oracle_out = oracle_res.stdout.strip()
        agent_out = agent_res.stdout.strip()

        assert oracle_out == agent_out, (
            f"Mismatch for arguments {args}.\n"
            f"Oracle output: {oracle_out!r}\n"
            f"Agent output: {agent_out!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

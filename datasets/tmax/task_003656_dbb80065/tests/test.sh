#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import pytest

def test_executable_exists():
    agent_path = "/app/validator/api_validator"
    assert os.path.isfile(agent_path), f"Agent executable not found at {agent_path}"
    assert os.access(agent_path, os.X_OK), f"Agent executable at {agent_path} is not executable"

def test_fuzz_equivalence():
    oracle_path = "/tests/api_validator_oracle"
    agent_path = "/app/validator/api_validator"

    assert os.path.isfile(oracle_path), f"Oracle executable not found at {oracle_path}"
    assert os.access(oracle_path, os.X_OK), f"Oracle executable at {oracle_path} is not executable"
    assert os.path.isfile(agent_path), f"Agent executable not found at {agent_path}"

    vocab = ["login", "mfa", "session", "resource", "reset", "email", "admin", "logout"]
    random.seed(42)

    N = 500
    for i in range(N):
        length = random.randint(1, 6)
        args = [random.choice(vocab) for _ in range(length)]

        oracle_cmd = [oracle_path] + args
        agent_cmd = [agent_path] + args

        try:
            oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True, timeout=2)
            oracle_output = oracle_res.stdout.strip()
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on input: {args}")

        try:
            agent_res = subprocess.run(agent_cmd, capture_output=True, text=True, timeout=2)
            agent_output = agent_res.stdout.strip()
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent timed out on input: {args}")

        assert agent_output == oracle_output, (
            f"Mismatch on input: {args}\n"
            f"Oracle output: {oracle_output}\n"
            f"Agent output: {agent_output}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

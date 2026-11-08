#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

def generate_test_case(seed):
    random.seed(seed)
    N = random.randint(10, 500)
    M = random.randint(10, 5000)
    S = random.randint(0, N - 1)
    T = random.randint(0, N - 1)

    input_lines = [f"{N} {M} {S} {T}"]
    for _ in range(M):
        u = random.randint(0, N - 1)
        v = random.randint(0, N - 1)
        w = random.randint(1, 100000)
        input_lines.append(f"{u} {v} {w}")

    return "\n".join(input_lines) + "\n"

def test_solver_equivalence():
    oracle_path = "/app/deadlock_oracle"
    agent_path = "/home/user/solver"

    assert os.path.exists(oracle_path), f"Oracle missing: {oracle_path}"
    assert os.path.exists(agent_path), f"Agent executable missing: {agent_path}. Did you compile it?"
    assert os.access(agent_path, os.X_OK), f"Agent file {agent_path} is not executable."

    num_tests = 500
    for i in range(num_tests):
        input_data = generate_test_case(seed=1337 + i)

        try:
            oracle_proc = subprocess.run(
                [oracle_path], input=input_data, text=True, capture_output=True, timeout=2
            )
            oracle_output = oracle_proc.stdout.strip()
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on test {i}")

        try:
            agent_proc = subprocess.run(
                [agent_path], input=input_data, text=True, capture_output=True, timeout=2
            )
            agent_output = agent_proc.stdout.strip()
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent program timed out on test {i}\nInput:\n{input_data[:200]}...")

        assert agent_proc.returncode == 0, (
            f"Agent program failed with return code {agent_proc.returncode} on test {i}\n"
            f"Error: {agent_proc.stderr}"
        )

        if agent_output != oracle_output:
            pytest.fail(
                f"Mismatch on test {i}.\n"
                f"Input (first 200 chars):\n{input_data[:200]}...\n"
                f"Expected (Oracle): {oracle_output}\n"
                f"Got (Agent): {agent_output}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

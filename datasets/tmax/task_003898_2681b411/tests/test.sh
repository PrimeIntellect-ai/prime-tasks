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
    oracle_path = "/app/oracle_bin"
    agent_path = "/home/user/project/solution"

    assert os.path.exists(oracle_path), f"Oracle missing at {oracle_path}"
    assert os.access(oracle_path, os.X_OK), f"Oracle {oracle_path} is not executable"

    assert os.path.exists(agent_path), f"Agent binary missing at {agent_path}. Did you run make?"
    assert os.access(agent_path, os.X_OK), f"Agent binary {agent_path} is not executable"

    random.seed(42)
    # Fuzz distribution: Random integers between 1 and 10000
    inputs = [str(random.randint(1, 10000)) for _ in range(50)]

    for inp in inputs:
        try:
            oracle_proc = subprocess.run([oracle_path, inp], capture_output=True, text=True, timeout=2)
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on input {inp}. This should not happen.")

        try:
            agent_proc = subprocess.run([agent_path, inp], capture_output=True, text=True, timeout=2)
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent program timed out on input {inp}. The infinite recursion/loop is likely not fixed.")

        assert oracle_proc.returncode == 0, f"Oracle failed on input {inp}"
        assert agent_proc.returncode == 0, f"Agent program failed on input {inp}. Return code: {agent_proc.returncode}. Stderr: {agent_proc.stderr}"

        oracle_out = oracle_proc.stdout.strip()
        agent_out = agent_proc.stdout.strip()

        assert oracle_out == agent_out, f"Output mismatch on input {inp}. Oracle expected: '{oracle_out}', Agent produced: '{agent_out}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

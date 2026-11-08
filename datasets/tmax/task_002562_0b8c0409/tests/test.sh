#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import pytest

ORACLE_PATH = "/tests/oracle_compute"
AGENT_PATH = "/home/user/compute_fixed"
N_TESTS = 1000

def test_agent_executable_exists():
    assert os.path.isfile(AGENT_PATH), f"Agent's executable not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent's file at {AGENT_PATH} is not executable"

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle executable missing at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle at {ORACLE_PATH} is not executable"

    random.seed(42)

    # Generate edge cases and random inputs
    inputs = [0, 1, 2, 1000000000, 0xFFFFFFFF, 0xFFFFFFFFFFFFFFFF]
    for _ in range(N_TESTS - len(inputs)):
        inputs.append(random.randint(0, 0xFFFFFFFFFFFFFFFF))

    for val in inputs:
        val_str = str(val)

        # Run oracle
        try:
            oracle_proc = subprocess.run(
                [ORACLE_PATH, val_str],
                capture_output=True,
                text=True,
                timeout=2
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on input {val_str}")

        assert oracle_proc.returncode == 0, f"Oracle failed on input {val_str}"
        oracle_out = oracle_proc.stdout.strip()

        # Run agent
        try:
            agent_proc = subprocess.run(
                [AGENT_PATH, val_str],
                capture_output=True,
                text=True,
                timeout=2
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent's program timed out on input {val_str}")

        assert agent_proc.returncode == 0, f"Agent program failed (crashed or returned non-zero) on input {val_str}. Stderr: {agent_proc.stderr}"
        agent_out = agent_proc.stdout.strip()

        assert agent_out == oracle_out, (
            f"Mismatch on input: {val_str}\n"
            f"Expected (Oracle): {oracle_out}\n"
            f"Got (Agent):       {agent_out}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

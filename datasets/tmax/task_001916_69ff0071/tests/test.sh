#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import subprocess
import pytest

def test_executable_exists():
    agent_bin = "/home/user/normalize"
    assert os.path.isfile(agent_bin), f"Executable {agent_bin} does not exist. Did you compile your Go program?"
    assert os.access(agent_bin, os.X_OK), f"{agent_bin} is not executable."

def test_fuzz_equivalence():
    oracle_bin = "/tests/oracle"
    agent_bin = "/home/user/normalize"

    assert os.path.isfile(oracle_bin), f"Oracle {oracle_bin} is missing."

    # Generate fuzzing input
    random.seed(42)
    N = 1000
    inputs = []
    for _ in range(N):
        vals = [random.uniform(-2000.0, 2000.0) for _ in range(4)]
        inputs.append(",".join(f"{v:.6f}" for v in vals))

    input_str = "\n".join(inputs) + "\n"

    # Run oracle
    oracle_proc = subprocess.run(
        [oracle_bin],
        input=input_str,
        text=True,
        capture_output=True,
        check=True
    )
    oracle_output = oracle_proc.stdout.strip().split("\n")

    # Run agent
    try:
        agent_proc = subprocess.run(
            [agent_bin],
            input=input_str,
            text=True,
            capture_output=True,
            timeout=10
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Agent program timed out.")

    assert agent_proc.returncode == 0, f"Agent program failed with return code {agent_proc.returncode}. Stderr: {agent_proc.stderr}"

    agent_output = agent_proc.stdout.strip().split("\n")

    assert len(oracle_output) == N, f"Oracle produced {len(oracle_output)} lines, expected {N}."
    assert len(agent_output) == N, f"Agent produced {len(agent_output)} lines, expected {N}."

    for i in range(N):
        expected = oracle_output[i]
        actual = agent_output[i]
        assert actual == expected, (
            f"Mismatch on line {i+1}.\n"
            f"Input: {inputs[i]}\n"
            f"Expected (Oracle): {expected}\n"
            f"Actual (Agent): {actual}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

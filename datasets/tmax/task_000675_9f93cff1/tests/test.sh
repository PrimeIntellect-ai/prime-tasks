#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import pytest

def test_executable_exists():
    """Test that the compiled C executable exists and is executable."""
    agent_path = "/home/user/bayes_filter"
    assert os.path.isfile(agent_path), f"Agent executable {agent_path} does not exist. Did you compile your C program?"
    assert os.access(agent_path, os.X_OK), f"Agent executable {agent_path} is not executable."

def test_fuzz_equivalence():
    """Test the agent's C program against the oracle using random fuzz inputs."""
    oracle_path = "/tests/bayes_filter"
    agent_path = "/home/user/bayes_filter"

    assert os.path.isfile(oracle_path), f"Oracle executable {oracle_path} is missing."
    assert os.access(oracle_path, os.X_OK), f"Oracle executable {oracle_path} is not executable."

    # Generate 1000 random float inputs between -1000.0 and 1000.0
    random.seed(42)
    inputs = [random.uniform(-1000.0, 1000.0) for _ in range(1000)]
    input_str = "\n".join(f"{x:.6f}" for x in inputs) + "\n"

    # Run oracle
    oracle_proc = subprocess.run(
        [oracle_path],
        input=input_str,
        text=True,
        capture_output=True
    )
    assert oracle_proc.returncode == 0, "Oracle program failed to run."

    # Run agent program
    agent_proc = subprocess.run(
        [agent_path],
        input=input_str,
        text=True,
        capture_output=True
    )
    assert agent_proc.returncode == 0, f"Agent program failed with return code {agent_proc.returncode}. Stderr: {agent_proc.stderr}"

    oracle_out = oracle_proc.stdout.strip().splitlines()
    agent_out = agent_proc.stdout.strip().splitlines()

    assert len(oracle_out) == len(inputs), "Oracle did not output the correct number of lines."
    assert len(agent_out) == len(inputs), f"Agent program output length mismatch. Expected {len(inputs)} lines, got {len(agent_out)} lines."

    for i, (expected, actual) in enumerate(zip(oracle_out, agent_out)):
        assert expected == actual, (
            f"Mismatch on input line {i+1} (input value: {inputs[i]:.6f}).\n"
            f"Expected output: {expected}\n"
            f"Agent output: {actual}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

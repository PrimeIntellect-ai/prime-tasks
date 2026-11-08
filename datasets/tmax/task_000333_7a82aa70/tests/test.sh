#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

def test_scorer_binary_exists():
    """Verify that the user compiled the scorer binary to the correct path."""
    agent_path = "/home/user/scorer"
    assert os.path.isfile(agent_path), f"Missing executable: {agent_path}"
    assert os.access(agent_path, os.X_OK), f"File is not executable: {agent_path}"

def test_scorer_fuzz_equivalence():
    """Fuzz test the user's scorer against the oracle."""
    agent_path = "/home/user/scorer"
    oracle_path = "/tests/oracle_scorer"

    assert os.path.isfile(oracle_path), f"Oracle missing: {oracle_path}"
    assert os.access(oracle_path, os.X_OK), f"Oracle not executable: {oracle_path}"

    random.seed(42)
    num_tests = 1000

    # Generate random inputs
    inputs = []
    for _ in range(num_tests):
        a = random.uniform(-100.0, 100.0)
        b = random.uniform(-100.0, 100.0)
        inputs.append(f"{a} {b}")

    input_data = "\n".join(inputs) + "\n"

    # Run Oracle
    try:
        oracle_proc = subprocess.run(
            [oracle_path],
            input=input_data,
            text=True,
            capture_output=True,
            check=True,
            timeout=5
        )
        oracle_output = oracle_proc.stdout.strip().split('\n')
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Oracle failed to execute: {e.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail("Oracle execution timed out.")

    # Run Agent
    try:
        agent_proc = subprocess.run(
            [agent_path],
            input=input_data,
            text=True,
            capture_output=True,
            check=True,
            timeout=5
        )
        agent_output = agent_proc.stdout.strip().split('\n')
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Agent's scorer failed to execute: {e.stderr}")
    except subprocess.TimeoutExpired:
        pytest.fail("Agent's scorer execution timed out.")

    # Compare outputs
    assert len(agent_output) == len(oracle_output), (
        f"Output line count mismatch. Expected {len(oracle_output)}, got {len(agent_output)}."
    )

    for i in range(num_tests):
        expected = oracle_output[i].strip()
        actual = agent_output[i].strip()
        if expected != actual:
            pytest.fail(
                f"Mismatch on input '{inputs[i]}'.\n"
                f"Expected: {expected}\n"
                f"Got:      {actual}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

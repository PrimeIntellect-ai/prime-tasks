#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import pytest

def test_query_script_exists_and_executable():
    """Test that the agent's query.sh script exists and is executable."""
    script_path = "/home/user/query.sh"
    assert os.path.isfile(script_path), f"Agent script {script_path} is missing."
    assert os.access(script_path, os.X_OK), f"Agent script {script_path} is not executable."

def test_fuzz_equivalence():
    """Fuzz the agent's script against the oracle script."""
    agent_script = "/home/user/query.sh"
    oracle_script = "/tests/oracle.sh"

    assert os.path.isfile(oracle_script), f"Oracle script {oracle_script} is missing."
    assert os.access(oracle_script, os.X_OK), f"Oracle script {oracle_script} is not executable."

    names = ["Alice", "Bob", "Charlie", "David", "Eve", "Frank", "Gina", "Harry", "Zack"]
    random.seed(42)
    test_inputs = [random.choice(names) for _ in range(10)]

    # Ensure we test all names at least once since the set is small
    test_inputs = list(set(names)) + test_inputs
    test_inputs = test_inputs[:15] # Just to be thorough

    for name in test_inputs:
        # Run oracle
        oracle_proc = subprocess.run(
            [oracle_script, name],
            capture_output=True,
            text=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on input '{name}'"
        oracle_output = oracle_proc.stdout.strip()

        # Run agent
        agent_proc = subprocess.run(
            [agent_script, name],
            capture_output=True,
            text=True
        )

        # We don't strictly assert returncode of agent unless it fails to run, but we check output
        agent_output = agent_proc.stdout.strip()

        assert agent_output == oracle_output, (
            f"Mismatch on input '{name}'.\n"
            f"Expected (Oracle): {oracle_output!r}\n"
            f"Got (Agent): {agent_output!r}\n"
            f"Agent STDERR: {agent_proc.stderr.strip()}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

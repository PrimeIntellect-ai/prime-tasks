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

def test_agent_script_exists_and_executable():
    """Test that the agent's output script exists and is executable."""
    agent_path = "/home/user/audit_hash.sh"
    assert os.path.isfile(agent_path), f"The output file {agent_path} is missing."
    assert os.access(agent_path, os.X_OK), f"The output file {agent_path} is not executable."

def test_fuzz_equivalence():
    """Fuzz the agent's script against the oracle script to ensure bit-exact equivalence."""
    oracle_path = "/tests/oracle_hash.sh"
    agent_path = "/home/user/audit_hash.sh"

    assert os.path.isfile(oracle_path), f"Oracle script {oracle_path} not found."
    assert os.path.isfile(agent_path), f"Agent script {agent_path} not found."

    random.seed(42)

    inputs = []

    # Explicitly include cases for "DROP" and "PWN"
    inputs.extend([
        "DROP",
        "PWN",
        "DROP_TABLE",
        "GET_PWN",
        "SOME_DROP_STRING",
        "PWNED_SYSTEM",
        "DROP_PWN",
        "NO_MATCH_HERE"
    ])

    # Generate 500 random printable ASCII strings of length 1 to 20
    printable_chars = string.printable
    for _ in range(500):
        length = random.randint(1, 20)
        s = "".join(random.choice(printable_chars) for _ in range(length))
        inputs.append(s)

    for inp in inputs:
        oracle_proc = subprocess.run(["bash", oracle_path, inp], capture_output=True, text=True)
        agent_proc = subprocess.run([agent_path, inp], capture_output=True, text=True)

        assert oracle_proc.returncode == agent_proc.returncode, (
            f"Exit code mismatch on input {repr(inp)}.\n"
            f"Oracle exit code: {oracle_proc.returncode}\n"
            f"Agent exit code: {agent_proc.returncode}\n"
            f"Oracle stdout: {repr(oracle_proc.stdout)}\n"
            f"Agent stdout: {repr(agent_proc.stdout)}\n"
            f"Oracle stderr: {repr(oracle_proc.stderr)}\n"
            f"Agent stderr: {repr(agent_proc.stderr)}"
        )

        assert oracle_proc.stdout == agent_proc.stdout, (
            f"Stdout mismatch on input {repr(inp)}.\n"
            f"Oracle stdout: {repr(oracle_proc.stdout)}\n"
            f"Agent stdout: {repr(agent_proc.stdout)}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

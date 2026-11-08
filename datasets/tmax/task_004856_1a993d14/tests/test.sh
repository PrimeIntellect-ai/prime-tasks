#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

AGENT_EXE = "/home/user/cypher2sql"
ORACLE_EXE = "/tests/cypher2sql_oracle"

def generate_fuzz_input():
    words = ["Person", "Knows", "Likes", "Post", "User", "Follows", "Group", "Belongs", "A", "B", "C", "D", "E"]
    num_extra_hops = random.randint(0, 3)

    parts = []
    parts.append("MATCH")
    parts.append(f"node:{random.choice(words)}")
    parts.append(f"edge:{random.choice(words)}")
    parts.append(f"node:{random.choice(words)}")

    for _ in range(num_extra_hops):
        parts.append(f"edge:{random.choice(words)}")
        parts.append(f"node:{random.choice(words)}")

    return " ".join(parts)

def test_agent_executable_exists():
    assert os.path.isfile(AGENT_EXE), f"The agent's executable {AGENT_EXE} does not exist."
    assert os.access(AGENT_EXE, os.X_OK), f"The agent's executable {AGENT_EXE} is not executable."

def test_oracle_executable_exists():
    assert os.path.isfile(ORACLE_EXE), f"The oracle executable {ORACLE_EXE} does not exist."
    assert os.access(ORACLE_EXE, os.X_OK), f"The oracle executable {ORACLE_EXE} is not executable."

def test_fuzz_equivalence():
    random.seed(42)
    inputs = [generate_fuzz_input() for _ in range(500)]

    for i, fuzz_input in enumerate(inputs):
        try:
            oracle_proc = subprocess.run(
                [ORACLE_EXE, fuzz_input],
                capture_output=True,
                text=True,
                timeout=2,
                check=True
            )
            oracle_output = oracle_proc.stdout
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on input '{fuzz_input}': {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on input '{fuzz_input}'")

        try:
            agent_proc = subprocess.run(
                [AGENT_EXE, fuzz_input],
                capture_output=True,
                text=True,
                timeout=2
            )
            agent_output = agent_proc.stdout
            agent_stderr = agent_proc.stderr
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent's executable timed out on input '{fuzz_input}'")

        assert agent_proc.returncode == 0, (
            f"Agent's executable failed with return code {agent_proc.returncode} on input '{fuzz_input}'.\n"
            f"Stderr: {agent_stderr}"
        )

        assert agent_output == oracle_output, (
            f"Output mismatch on fuzz input #{i+1}:\n"
            f"Input: {fuzz_input}\n"
            f"Expected (Oracle): {oracle_output!r}\n"
            f"Actual (Agent): {agent_output!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

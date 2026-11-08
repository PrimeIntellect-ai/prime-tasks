#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

AGENT_SCRIPT = "/home/user/normalize_graph.sh"
ORACLE_SCRIPT = "/tests/oracle_normalize.sh"
NUM_ITERATIONS = 500

def generate_random_matrix(n):
    """Generates an N x N matrix with random integers between 0 and 10."""
    lines = []
    for _ in range(n):
        row = [str(random.randint(0, 10)) for _ in range(n)]
        lines.append(" ".join(row))
    return "\n".join(lines) + "\n"

def test_agent_script_exists_and_executable():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} does not exist."
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file."
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script {AGENT_SCRIPT} is not executable."

def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_SCRIPT), f"Oracle script {ORACLE_SCRIPT} missing."

    random.seed(42)

    for i in range(NUM_ITERATIONS):
        n = random.randint(2, 20)
        matrix_input = generate_random_matrix(n)

        # Run oracle uploaded only at verification time.
        oracle_proc = subprocess.run(
            ["bash", ORACLE_SCRIPT],
            input=matrix_input,
            text=True,
            capture_output=True,
            check=False
        )
        oracle_out = oracle_proc.stdout.strip()

        # Run agent
        agent_proc = subprocess.run(
            [AGENT_SCRIPT],
            input=matrix_input,
            text=True,
            capture_output=True,
            check=False
        )
        agent_out = agent_proc.stdout.strip()

        assert agent_proc.returncode == 0, f"Agent script failed on iteration {i} with error:\n{agent_proc.stderr}"

        if oracle_out != agent_out:
            error_msg = (
                f"Mismatch on iteration {i} (N={n}).\n"
                f"Input Matrix:\n{matrix_input}\n"
                f"Expected Output (Oracle):\n{oracle_out}\n\n"
                f"Actual Output (Agent):\n{agent_out}\n"
            )
            pytest.fail(error_msg)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

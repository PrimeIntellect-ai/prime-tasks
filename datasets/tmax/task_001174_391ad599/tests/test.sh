#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

N = 2000
ORACLE_PATH = "/app/bin/key_gen"
AGENT_SCRIPT = "/home/user/keygen.py"

def generate_random_string():
    length = random.randint(1, 255)
    # Standard printable ASCII (0x20 to 0x7E)
    chars = [chr(i) for i in range(0x20, 0x7F)]
    return "".join(random.choice(chars) for _ in range(length))

def test_agent_script_exists():
    """Ensure the agent wrote the solution script to the correct path."""
    assert os.path.exists(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} does not exist."
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file."

def test_fuzz_equivalence():
    """Fuzz the agent's script against the oracle binary."""
    assert os.path.exists(ORACLE_PATH), f"Oracle binary {ORACLE_PATH} missing."
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle binary {ORACLE_PATH} is not executable."

    random.seed(42)
    inputs = [generate_random_string() for _ in range(N)]

    for s in inputs:
        # Run oracle
        oracle_res = subprocess.run(
            [ORACLE_PATH, s],
            capture_output=True,
            text=True
        )
        assert oracle_res.returncode == 0, f"Oracle failed on input {repr(s)}"
        oracle_out = oracle_res.stdout.strip()

        # Run agent
        agent_res = subprocess.run(
            ["python3", AGENT_SCRIPT, s],
            capture_output=True,
            text=True
        )
        assert agent_res.returncode == 0, f"Agent script failed on input {repr(s)}. Stderr: {agent_res.stderr}"
        agent_out = agent_res.stdout.strip()

        assert agent_out == oracle_out, (
            f"Mismatch on input {repr(s)} (length {len(s)}).\n"
            f"Oracle output: {oracle_out}\n"
            f"Agent output:  {agent_out}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

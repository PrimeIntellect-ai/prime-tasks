#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import pytest

ORACLE_PATH = "/app/signal_processor"
AGENT_SCRIPT = "/home/user/fitter.py"
NUM_TESTS = 100
NUM_FLOATS = 64

def test_fitter_script_exists():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} does not exist."

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle binary {ORACLE_PATH} missing."
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle binary {ORACLE_PATH} not executable."

    random.seed(42)

    for i in range(NUM_TESTS):
        # Generate 64 random floats between -100.0 and 100.0
        floats = [random.uniform(-100.0, 100.0) for _ in range(NUM_FLOATS)]
        input_str = " ".join(f"{x:.6f}" for x in floats) + "\n"

        # Run oracle
        oracle_proc = subprocess.run(
            [ORACLE_PATH],
            input=input_str,
            text=True,
            capture_output=True,
            check=False
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on test {i+1}:\n{oracle_proc.stderr}"
        oracle_out = oracle_proc.stdout.strip()

        # Run agent
        agent_proc = subprocess.run(
            ["python3", AGENT_SCRIPT],
            input=input_str,
            text=True,
            capture_output=True,
            check=False
        )
        assert agent_proc.returncode == 0, f"Agent script failed on test {i+1}:\n{agent_proc.stderr}"
        agent_out = agent_proc.stdout.strip()

        # Compare
        assert agent_out == oracle_out, (
            f"Mismatch on test {i+1}.\n"
            f"Input (first 5 floats): {floats[:5]}...\n"
            f"Oracle output: {oracle_out}\n"
            f"Agent output:  {agent_out}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

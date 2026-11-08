#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import pytest

ORACLE_PATH = "/tests/oracle"
AGENT_PATH = "/home/user/fitter"

def test_fitter_executable_exists():
    assert os.path.isfile(AGENT_PATH), f"The agent's executable {AGENT_PATH} is missing."
    assert os.access(AGENT_PATH, os.X_OK), f"The file {AGENT_PATH} is not executable."

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"The oracle executable {ORACLE_PATH} is missing."
    assert os.access(ORACLE_PATH, os.X_OK), f"The oracle {ORACLE_PATH} is not executable."

    random.seed(42)
    num_tests = 100

    for i in range(num_tests):
        num_floats = random.randint(10, 1000)
        floats = [random.uniform(-10.0, 10.0) for _ in range(num_floats)]
        input_data = " ".join(f"{x:.6f}" for x in floats) + "\n"

        oracle_proc = subprocess.run(
            [ORACLE_PATH],
            input=input_data,
            text=True,
            capture_output=True,
            check=False
        )
        oracle_output = oracle_proc.stdout.strip()

        agent_proc = subprocess.run(
            [AGENT_PATH],
            input=input_data,
            text=True,
            capture_output=True,
            check=False
        )
        agent_output = agent_proc.stdout.strip()

        assert agent_proc.returncode == 0, f"Agent program failed with return code {agent_proc.returncode} on test case {i+1}."
        assert agent_output == oracle_output, (
            f"Mismatch on test case {i+1}.\n"
            f"Input ({num_floats} floats, showing first 5): {' '.join(input_data.split()[:5])} ...\n"
            f"Expected (Oracle): {oracle_output}\n"
            f"Got (Agent): {agent_output}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

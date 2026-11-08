#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import pytest

def test_process_signal_exists():
    agent_path = "/home/user/process_signal.py"
    assert os.path.isfile(agent_path), f"Agent script missing: {agent_path}"

def test_fuzz_equivalence():
    agent_path = "/home/user/process_signal.py"
    oracle_path = "/tests/oracle_process_signal.py"

    assert os.path.isfile(agent_path), f"Agent script missing: {agent_path}"
    assert os.path.isfile(oracle_path), f"Oracle script missing: {oracle_path}"

    random.seed(42)

    for iteration in range(100):
        L = random.randint(2, 500)
        floats = [random.uniform(-10000.0, 10000.0) for _ in range(L)]
        input_data = "\n".join(f"{x:.10f}" for x in floats) + "\n"

        # Run oracle
        oracle_proc = subprocess.run(
            ["python3", oracle_path],
            input=input_data,
            text=True,
            capture_output=True,
            check=True
        )
        oracle_output = oracle_proc.stdout.strip()

        # Run agent
        agent_proc = subprocess.run(
            ["python3", agent_path],
            input=input_data,
            text=True,
            capture_output=True
        )

        assert agent_proc.returncode == 0, f"Agent script failed on iteration {iteration} with error: {agent_proc.stderr}"
        agent_output = agent_proc.stdout.strip()

        assert agent_output == oracle_output, (
            f"Output mismatch on iteration {iteration}.\n"
            f"Input size: {L}\n"
            f"Oracle output: {oracle_output}\n"
            f"Agent output: {agent_output}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

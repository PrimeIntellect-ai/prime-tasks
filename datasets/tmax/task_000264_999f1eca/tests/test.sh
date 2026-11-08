#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import pytest

def test_script_exists_and_executable():
    script_path = "/home/user/generate_report.sh"
    assert os.path.isfile(script_path), f"Agent script missing at {script_path}"
    assert os.access(script_path, os.X_OK), f"Agent script at {script_path} is not executable"

def test_fuzz_equivalence():
    agent_script = "/home/user/generate_report.sh"
    oracle_script = "/tests/oracle_report.sh"

    assert os.path.isfile(oracle_script), f"Oracle script missing at {oracle_script}"
    assert os.access(oracle_script, os.X_OK), f"Oracle script at {oracle_script} is not executable"

    random.seed(42)
    # Generate 50 random customer IDs between 1 and 200
    # Also test out-of-bounds IDs to ensure exit code 1
    test_ids = [random.randint(1, 200) for _ in range(50)] + [999, 1000]

    for customer_id in test_ids:
        # Run oracle
        oracle_cmd = [oracle_script, str(customer_id)]
        oracle_proc = subprocess.run(oracle_cmd, capture_output=True, text=True)

        # Run agent
        agent_cmd = ["bash", agent_script, str(customer_id)]
        agent_proc = subprocess.run(agent_cmd, capture_output=True, text=True)

        # Compare exit codes
        assert oracle_proc.returncode == agent_proc.returncode, \
            f"Exit code mismatch for Customer ID {customer_id}.\nOracle: {oracle_proc.returncode}\nAgent: {agent_proc.returncode}"

        # Compare stdout
        oracle_stdout = oracle_proc.stdout.strip()
        agent_stdout = agent_proc.stdout.strip()

        assert oracle_stdout == agent_stdout, \
            f"Output mismatch for Customer ID {customer_id}.\nOracle output:\n{oracle_stdout}\n\nAgent output:\n{agent_stdout}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

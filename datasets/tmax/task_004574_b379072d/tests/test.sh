#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sys
import subprocess
import random
import csv
import io
import pytest

AGENT_SCRIPT = "/home/user/process_features.py"
ORACLE_SCRIPT = "/tests/oracle_process_features.py"

def generate_random_csv(num_rows=20):
    output = io.StringIO()
    writer = csv.writer(output)
    writer.writerow(['A', 'B', 'C', 'D'])
    for _ in range(num_rows):
        row = [round(random.uniform(-10.0, 10.0), 4) for _ in range(4)]
        writer.writerow(row)
    return output.getvalue()

def test_agent_script_exists():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file"

def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_SCRIPT), f"Oracle script missing at {ORACLE_SCRIPT}"

    random.seed(42)
    N = 50

    for i in range(N):
        csv_input = generate_random_csv(20)

        # Run oracle
        try:
            oracle_proc = subprocess.run(
                [sys.executable, ORACLE_SCRIPT],
                input=csv_input,
                text=True,
                capture_output=True,
                check=True
            )
            oracle_output = oracle_proc.stdout
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on input {i}:\n{e.stderr}")

        # Run agent
        try:
            agent_proc = subprocess.run(
                [sys.executable, AGENT_SCRIPT],
                input=csv_input,
                text=True,
                capture_output=True,
                check=True
            )
            agent_output = agent_proc.stdout
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent script failed on input {i}. Error:\n{e.stderr}\nInput CSV:\n{csv_input}")

        if agent_output.strip() != oracle_output.strip():
            pytest.fail(
                f"Output mismatch on random input {i}.\n\n"
                f"Input CSV:\n{csv_input}\n"
                f"Expected Output (Oracle):\n{oracle_output}\n"
                f"Actual Output (Agent):\n{agent_output}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import random
import string
import subprocess
import pytest

AGENT_SCRIPT = "/home/user/format_backup.py"
ORACLE_SCRIPT = "/tests/oracle_converter.py"

def generate_random_input():
    num_records = random.randint(0, 20)
    records = []
    chars = string.ascii_letters + string.digits + " ,"
    for _ in range(num_records):
        filename_len = random.randint(5, 15)
        filename = "".join(random.choice(chars) for _ in range(filename_len))
        size_bytes = random.randint(100, 1000000)
        checksum = f"{random.randint(0, 0xffffffff):08x}"
        records.append({
            "filename": filename,
            "size_bytes": size_bytes,
            "checksum": checksum
        })
    return json.dumps(records)

def test_agent_script_exists():
    """Ensure the agent's script exists."""
    assert os.path.exists(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), f"Path {AGENT_SCRIPT} is not a file."

def test_fuzz_equivalence():
    """Fuzz the agent's script against the oracle script."""
    assert os.path.exists(ORACLE_SCRIPT), f"Oracle script missing at {ORACLE_SCRIPT}"

    random.seed(42)
    num_iterations = 100

    for i in range(num_iterations):
        input_data = generate_random_input()
        input_bytes = input_data.encode('utf-8')

        # Run Oracle
        oracle_proc = subprocess.run(
            ["python3", ORACLE_SCRIPT],
            input=input_bytes,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i} with input: {input_data}\nError: {oracle_proc.stderr.decode('utf-8', errors='replace')}"
        oracle_output = oracle_proc.stdout

        # Run Agent
        agent_proc = subprocess.run(
            ["python3", AGENT_SCRIPT],
            input=input_bytes,
            capture_output=True
        )

        if agent_proc.returncode != 0:
            agent_stderr = agent_proc.stderr.decode('utf-8', errors='replace')
            pytest.fail(f"Agent script crashed on iteration {i}.\nInput data:\n{input_data}\n\nStderr:\n{agent_stderr}")

        agent_output = agent_proc.stdout

        if agent_output != oracle_output:
            pytest.fail(
                f"Output mismatch on iteration {i}.\n"
                f"Input data:\n{input_data}\n\n"
                f"Expected Output (Oracle) [hex]:\n{oracle_output.hex()}\n\n"
                f"Actual Output (Agent) [hex]:\n{agent_output.hex()}\n"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

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

def generate_input():
    """Generate a random CSV string formatted as id,col2,col3."""
    id_val = "".join(random.choices(string.ascii_uppercase + string.digits, k=5))

    col2_type = random.choices(['empty', 'nan', 'num'], weights=[1, 1, 8])[0]
    if col2_type == 'empty':
        col2_val = ""
    elif col2_type == 'nan':
        col2_val = "NaN"
    else:
        if random.choice([True, False]):
            col2_val = str(random.randint(0, 999))
        else:
            col2_val = f"{random.randint(0, 999)}.{random.randint(0, 9)}"

    if random.choice([True, False]):
        col3_val = str(random.randint(0, 200))
    else:
        col3_val = f"{random.randint(0, 200)}.{random.randint(0, 9)}"

    return f"{id_val},{col2_val},{col3_val}"

def test_pipeline_exists_and_executable():
    agent_script = "/home/user/pipeline.sh"
    assert os.path.isfile(agent_script), f"The script {agent_script} does not exist."
    assert os.access(agent_script, os.X_OK), f"The script {agent_script} is not executable."

def test_fuzz_equivalence():
    agent_script = "/home/user/pipeline.sh"
    oracle_script = "/tests/oracle_pipeline.sh"

    assert os.path.isfile(oracle_script), f"Oracle script missing at {oracle_script}."
    assert os.access(oracle_script, os.X_OK), f"Oracle script is not executable."

    random.seed(42)
    num_tests = 1000

    for _ in range(num_tests):
        input_str = generate_input()

        oracle_proc = subprocess.run(
            [oracle_script, input_str],
            capture_output=True,
            text=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on input '{input_str}' with stderr: {oracle_proc.stderr}"
        oracle_out = oracle_proc.stdout.strip()

        agent_proc = subprocess.run(
            [agent_script, input_str],
            capture_output=True,
            text=True
        )
        assert agent_proc.returncode == 0, f"Agent script failed on input '{input_str}' with stderr: {agent_proc.stderr}"
        agent_out = agent_proc.stdout.strip()

        assert agent_out == oracle_out, (
            f"Mismatch on input: '{input_str}'\n"
            f"Expected (Oracle): '{oracle_out}'\n"
            f"Got (Agent): '{agent_out}'"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

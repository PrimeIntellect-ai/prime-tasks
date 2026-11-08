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
from datetime import datetime, timedelta

def generate_random_input(num_lines=100):
    random.seed(42)
    lines = []
    start_date = datetime(2020, 1, 1)
    for _ in range(num_lines):
        # Random datetime
        random_days = random.randint(0, 2000)
        random_seconds = random.randint(0, 86400)
        dt = start_date + timedelta(days=random_days, seconds=random_seconds)
        ts_str = dt.strftime("%Y-%m-%dT%H:%M:%SZ")

        # Random service name
        service_len = random.randint(5, 15)
        service = ''.join(random.choices(string.ascii_lowercase + string.digits + '-', k=service_len))

        # Random cpu and mem
        cpu = random.uniform(0, 10)
        mem = random.uniform(100, 10000)

        lines.append(f"{ts_str},{service},{cpu:.4f},{mem:.4f}")
    return "\n".join(lines) + "\n"

def test_script_exists_and_executable():
    script_path = "/home/user/projector.py"
    assert os.path.exists(script_path), f"Agent script {script_path} does not exist."
    assert os.path.isfile(script_path), f"Agent script {script_path} is not a file."
    assert os.access(script_path, os.X_OK), f"Agent script {script_path} is not executable."

def test_fuzz_equivalence():
    agent_script = "/home/user/projector.py"
    oracle_script = "/tests/projector_oracle"

    assert os.path.exists(agent_script), f"Agent script {agent_script} does not exist."
    assert os.path.exists(oracle_script), f"Oracle script {oracle_script} does not exist."

    input_data = generate_random_input(100)

    # Run oracle
    oracle_proc = subprocess.run(
        [oracle_script],
        input=input_data,
        text=True,
        capture_output=True,
        check=True
    )
    oracle_output = oracle_proc.stdout

    # Run agent
    agent_proc = subprocess.run(
        ["python3", agent_script],
        input=input_data,
        text=True,
        capture_output=True
    )

    if agent_proc.returncode != 0:
        pytest.fail(f"Agent script failed with return code {agent_proc.returncode}.\nStderr: {agent_proc.stderr}")

    agent_output = agent_proc.stdout

    oracle_lines = oracle_output.strip().split('\n')
    agent_lines = agent_output.strip().split('\n')
    input_lines = input_data.strip().split('\n')

    assert len(agent_lines) == len(oracle_lines), f"Output line count mismatch. Expected {len(oracle_lines)}, got {len(agent_lines)}."

    for i, (oracle_line, agent_line) in enumerate(zip(oracle_lines, agent_lines)):
        assert oracle_line == agent_line, (
            f"Mismatch at line {i+1}:\n"
            f"Input:  {input_lines[i]}\n"
            f"Oracle: {oracle_line}\n"
            f"Agent:  {agent_line}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

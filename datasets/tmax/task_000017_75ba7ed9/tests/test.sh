#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import sys
import json
import random
import string
import subprocess
import pytest

def generate_fuzz_input(n):
    lines = []
    for _ in range(n):
        mid = ''.join(random.choices(string.ascii_letters + string.digits, k=8))
        score = random.uniform(0.5, 0.99)
        loss = random.uniform(0.01, 0.5)
        lines.append(json.dumps({"id": mid, "score": score, "loss": loss}))
    return "\n".join(lines) + "\n"

def test_tracker_fuzz_equivalence():
    agent_script = "/home/user/tracker.py"
    oracle_script = "/tests/oracle_tracker"

    assert os.path.isfile(agent_script), f"Agent script not found at {agent_script}"
    assert os.path.isfile(oracle_script), f"Oracle script not found at {oracle_script}"

    # Fixed seed for reproducibility
    random.seed(42)
    input_data = generate_fuzz_input(500)

    # Run oracle
    oracle_proc = subprocess.run(
        [sys.executable, oracle_script],
        input=input_data,
        text=True,
        capture_output=True
    )
    assert oracle_proc.returncode == 0, f"Oracle failed to execute:\n{oracle_proc.stderr}"
    oracle_output = oracle_proc.stdout.strip().split('\n')

    # Run agent
    agent_proc = subprocess.run(
        [sys.executable, agent_script],
        input=input_data,
        text=True,
        capture_output=True
    )
    assert agent_proc.returncode == 0, f"Agent script failed to execute:\n{agent_proc.stderr}"
    agent_output = agent_proc.stdout.strip().split('\n')

    assert len(oracle_output) == len(agent_output), (
        f"Output line count mismatch: expected {len(oracle_output)}, got {len(agent_output)}"
    )

    input_lines = input_data.strip().split('\n')
    for i, (oracle_line, agent_line) in enumerate(zip(oracle_output, agent_output)):
        try:
            oracle_json = json.loads(oracle_line)
        except json.JSONDecodeError:
            pytest.fail(f"Oracle produced invalid JSON on line {i+1}: {oracle_line}")

        try:
            agent_json = json.loads(agent_line)
        except json.JSONDecodeError:
            pytest.fail(f"Agent produced invalid JSON on line {i+1}: {agent_line}")

        assert oracle_json == agent_json, (
            f"Mismatch on input line {i+1}.\n"
            f"Input: {input_lines[i]}\n"
            f"Expected: {oracle_json}\n"
            f"Got: {agent_json}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

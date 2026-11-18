#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import random
import subprocess
import pytest

def generate_input():
    length = random.randint(5, 50)
    data = []
    for _ in range(length):
        data.append({
            "A": random.randint(-100, 100),
            "B": random.randint(-100, 100),
            "C": random.randint(-100, 100)
        })
    return json.dumps(data)

def run_script(cmd, input_data):
    result = subprocess.run(cmd, input=input_data, text=True, capture_output=True)
    return result.stdout.strip()

def test_pipeline_exists():
    """Test that the agent's pipeline script exists."""
    agent_script = "/home/user/pipeline.py"
    assert os.path.isfile(agent_script), f"Agent script missing: {agent_script}"

def test_fuzz_equivalence():
    """Test the agent's script against the oracle on 500 random inputs."""
    agent_script = "/home/user/pipeline.py"
    oracle_script = "/tests/oracle.py"

    assert os.path.isfile(agent_script), f"Agent script missing: {agent_script}"
    assert os.path.isfile(oracle_script), f"Oracle script missing: {oracle_script}"

    random.seed(42)
    for i in range(500):
        input_data = generate_input()

        oracle_out = run_script(["python3", oracle_script], input_data)
        agent_out = run_script(["python3", agent_script], input_data)

        try:
            oracle_json = json.loads(oracle_out)
        except json.JSONDecodeError:
            oracle_json = oracle_out

        try:
            agent_json = json.loads(agent_out)
        except json.JSONDecodeError:
            agent_json = agent_out

        assert oracle_json == agent_json, (
            f"Mismatch on iteration {i+1}.\n"
            f"Input: {input_data}\n"
            f"Oracle output: {oracle_json}\n"
            f"Agent output: {agent_json}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

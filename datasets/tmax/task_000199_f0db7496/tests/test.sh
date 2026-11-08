#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import json
import random
import subprocess
import os
import pytest

def test_serializer_equivalence():
    agent_script = "/home/user/serializer.py"
    oracle_script = "/tests/reference.py"

    assert os.path.isfile(agent_script), f"Agent script {agent_script} does not exist."
    assert os.path.isfile(oracle_script), f"Oracle script {oracle_script} does not exist."

    random.seed(42)

    for i in range(1000):
        length = random.randint(0, 100)
        arr = [random.randint(-10000, 10000) for _ in range(length)]
        input_data = json.dumps(arr)

        # Run oracle
        oracle_proc = subprocess.run(
            ["python3", oracle_script],
            input=input_data,
            text=True,
            capture_output=True,
            check=True
        )
        oracle_out = oracle_proc.stdout.strip()

        # Run agent
        agent_proc = subprocess.run(
            ["python3", agent_script],
            input=input_data,
            text=True,
            capture_output=True
        )

        assert agent_proc.returncode == 0, f"Agent script failed on input: {input_data}\nError: {agent_proc.stderr}"
        agent_out = agent_proc.stdout.strip()

        # Parse JSON to allow for valid variations in spacing
        try:
            oracle_json = json.loads(oracle_out) if oracle_out else {}
        except json.JSONDecodeError:
            oracle_json = oracle_out

        try:
            agent_json = json.loads(agent_out) if agent_out else {}
        except json.JSONDecodeError:
            pytest.fail(f"Agent output is not valid JSON on input: {input_data}\nOutput: {agent_out}")

        assert agent_json == oracle_json, f"Mismatch on input: {input_data}\nExpected: {oracle_json}\nGot: {agent_json}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import json
import pytest

AGENT_SCRIPT = "/home/user/query_graph.py"
ORACLE_SCRIPT = "/tests/oracle_graph.py"

def test_agent_script_exists():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file"

def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_SCRIPT), f"Oracle script missing at {ORACLE_SCRIPT}"
    assert os.path.exists(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"

    random.seed(12345)
    num_iterations = 50

    for i in range(num_iterations):
        start_node_id = random.randint(0, 60)
        weight_limit = random.randint(0, 255)

        args = [str(start_node_id), str(weight_limit)]

        # Run Oracle
        oracle_cmd = ["python3", ORACLE_SCRIPT] + args
        try:
            oracle_result = subprocess.run(oracle_cmd, capture_output=True, text=True, check=True, timeout=10)
            oracle_output = oracle_result.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on input {args}. Error: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on input {args}.")

        # Run Agent
        agent_cmd = ["python3", AGENT_SCRIPT] + args
        try:
            agent_result = subprocess.run(agent_cmd, capture_output=True, text=True, check=True, timeout=10)
            agent_output = agent_result.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent script failed on input {args}. Error: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent script timed out on input {args}.")

        # Parse JSON to ensure structural equality, ignoring formatting differences
        try:
            oracle_json = json.loads(oracle_output)
        except json.JSONDecodeError:
            pytest.fail(f"Oracle produced invalid JSON on input {args}: {oracle_output}")

        try:
            agent_json = json.loads(agent_output)
        except json.JSONDecodeError:
            pytest.fail(f"Agent produced invalid JSON on input {args}: {agent_output}")

        assert agent_json == oracle_json, (
            f"Mismatch on input start_node_id={start_node_id}, weight_limit={weight_limit}.\n"
            f"Oracle output: {oracle_output}\n"
            f"Agent output: {agent_output}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

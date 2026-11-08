#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import json
import random
import sys
import pytest

AGENT_BIN = "/home/user/cypher_analyzer_fixed"
ORACLE_BIN = "/tests/cypher_degree_calc"

def test_agent_binary_exists():
    assert os.path.isfile(AGENT_BIN), f"Agent binary {AGENT_BIN} does not exist. Did you compile and place it correctly?"
    assert os.access(AGENT_BIN, os.X_OK), f"Agent binary {AGENT_BIN} is not executable."

def test_fuzz_equivalence():
    random.seed(42)

    for i in range(50):
        num_lines = random.randint(1, 100)
        lines = []
        for _ in range(num_lines):
            id1 = random.randint(1, 9999)
            id2 = random.randint(1, 9999)
            lines.append(f"MATCH (n1:Person {{id: {id1}}})-[:KNOWS]->(n2:Person {{id: {id2}}})")

        input_data = "\n".join(lines) + "\n"

        # Run oracle uploaded only at verification time.
        oracle_proc = subprocess.run(
            [sys.executable, ORACLE_BIN],
            input=input_data,
            text=True,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on input:\n{input_data}\nError: {oracle_proc.stderr}"
        oracle_out = oracle_proc.stdout.strip()

        # Run agent
        agent_proc = subprocess.run(
            [AGENT_BIN],
            input=input_data,
            text=True,
            capture_output=True
        )
        assert agent_proc.returncode == 0, f"Agent binary failed on input:\n{input_data}\nError: {agent_proc.stderr}"
        agent_out = agent_proc.stdout.strip()

        try:
            oracle_json = json.loads(oracle_out)
        except json.JSONDecodeError:
            pytest.fail(f"Oracle produced invalid JSON: {oracle_out}")

        try:
            agent_json = json.loads(agent_out)
        except json.JSONDecodeError:
            pytest.fail(f"Agent produced invalid JSON: {agent_out}\nInput was:\n{input_data}")

        assert oracle_json == agent_json, (
            f"Output mismatch on test case {i+1}.\n"
            f"Input:\n{input_data}\n"
            f"Oracle output:\n{oracle_out}\n"
            f"Agent output:\n{agent_out}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

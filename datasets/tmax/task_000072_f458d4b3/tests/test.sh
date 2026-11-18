#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import sqlite3
import subprocess
import random
import pytest

def test_fuzz_equivalence():
    agent_script = "/home/user/route_calculator.py"
    oracle_script = "/tests/oracle_route_calculator.py"
    db_path = "/app/routing_backup.db"

    assert os.path.isfile(agent_script), f"Agent script missing: {agent_script}"
    assert os.path.isfile(oracle_script), f"Oracle script missing: {oracle_script}"
    assert os.path.isfile(db_path), f"Database missing: {db_path}"

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM nodes WHERE name NOT IN ('NodeDelta', 'NodeSigma', 'NodeTau');")
    valid_nodes = [row[0] for row in cursor.fetchall()]
    conn.close()

    assert len(valid_nodes) >= 2, "Not enough valid nodes to test."

    random.seed(42)
    test_cases = []
    for _ in range(500):
        start, end = random.sample(valid_nodes, 2)
        test_cases.append((start, end))

    for start, end in test_cases:
        # Run oracle
        oracle_cmd = ["python3", oracle_script, start, end]
        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_res.returncode == 0, f"Oracle failed on {start} -> {end}\nError: {oracle_res.stderr}"
        oracle_out = oracle_res.stdout.strip()

        # Run agent
        agent_cmd = ["python3", agent_script, start, end]
        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)
        assert agent_res.returncode == 0, f"Agent script failed on {start} -> {end}\nError: {agent_res.stderr}"
        agent_out = agent_res.stdout.strip()

        assert agent_out == oracle_out, (
            f"Mismatch on {start} -> {end}.\n"
            f"Oracle output: {oracle_out}\n"
            f"Agent output: {agent_out}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

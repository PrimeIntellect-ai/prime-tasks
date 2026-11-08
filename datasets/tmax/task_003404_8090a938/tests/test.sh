#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import subprocess
import pytest

def test_pathfinder_executable_exists():
    path = "/home/user/pathfinder"
    assert os.path.isfile(path), f"Missing executable: {path}"
    assert os.access(path, os.X_OK), f"File is not executable: {path}"

def test_fuzz_equivalence():
    oracle_path = "/tests/oracle_pathfinder"
    agent_path = "/home/user/pathfinder"

    assert os.path.isfile(oracle_path), f"Oracle executable missing: {oracle_path}"
    assert os.path.isfile(agent_path), f"Agent executable missing: {agent_path}"

    # Generate fuzz input
    random.seed(1337)
    queries = []
    for _ in range(100):
        u = random.randint(0, 99)
        v = random.randint(0, 99)
        queries.append(f"{u} {v}")

    input_data = "\n".join(queries) + "\n"

    # Run oracle
    oracle_proc = subprocess.run(
        [oracle_path],
        input=input_data,
        text=True,
        capture_output=True,
        check=True
    )
    oracle_output = oracle_proc.stdout

    # Run agent
    agent_proc = subprocess.run(
        [agent_path],
        input=input_data,
        text=True,
        capture_output=True
    )

    assert agent_proc.returncode == 0, f"Agent program failed with return code {agent_proc.returncode}. stderr: {agent_proc.stderr}"

    agent_output = agent_proc.stdout

    # Compare
    oracle_lines = oracle_output.strip().split("\n")
    agent_lines = agent_output.strip().split("\n")

    assert len(agent_lines) == len(oracle_lines), f"Output line count mismatch. Expected {len(oracle_lines)}, got {len(agent_lines)}."

    for i, (query, expected, actual) in enumerate(zip(queries, oracle_lines, agent_lines)):
        assert expected.strip() == actual.strip(), f"Mismatch on query {i+1} ('{query}'): expected {expected.strip()}, got {actual.strip()}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import pytest

def test_fuzz_equivalence():
    agent_bin = "/home/user/route_engine/target/release/route_engine"
    oracle_bin = "/tests/oracle_route_engine"

    assert os.path.isfile(agent_bin), f"Agent binary not found at {agent_bin}"
    assert os.access(agent_bin, os.X_OK), f"Agent binary at {agent_bin} is not executable"

    assert os.path.isfile(oracle_bin), f"Oracle binary not found at {oracle_bin}"
    assert os.access(oracle_bin, os.X_OK), f"Oracle binary at {oracle_bin} is not executable"

    # Read hubs.csv to get hub_ids
    hubs_file = "/home/user/data/hubs.csv"
    assert os.path.isfile(hubs_file), f"{hubs_file} does not exist"

    hub_ids = []
    with open(hubs_file, "r") as f:
        lines = f.read().strip().split("\n")
        for line in lines:
            parts = line.split(",")
            if parts and parts[0].isdigit():
                hub_ids.append(parts[0])

    assert hub_ids, "No valid hub_ids found in hubs.csv"

    # Generate 1000 random queries
    random.seed(42)
    queries = []
    for _ in range(1000):
        x = random.choice(hub_ids)
        y = random.choice(hub_ids)
        queries.append(f"{x},{y}")

    input_data = "\n".join(queries) + "\n"

    # Run oracle
    oracle_proc = subprocess.run(
        [oracle_bin],
        input=input_data,
        text=True,
        capture_output=True,
        check=False
    )
    assert oracle_proc.returncode == 0, f"Oracle failed with error: {oracle_proc.stderr}"
    oracle_output = oracle_proc.stdout

    # Run agent
    agent_proc = subprocess.run(
        [agent_bin],
        input=input_data,
        text=True,
        capture_output=True,
        check=False
    )
    assert agent_proc.returncode == 0, f"Agent program failed with error: {agent_proc.stderr}"
    agent_output = agent_proc.stdout

    # Compare outputs
    oracle_lines = oracle_output.strip().split("\n")
    agent_lines = agent_output.strip().split("\n")

    assert len(oracle_lines) == len(agent_lines), f"Output line count mismatch: expected {len(oracle_lines)}, got {len(agent_lines)}"

    for i, (o_line, a_line) in enumerate(zip(oracle_lines, agent_lines)):
        assert o_line == a_line, f"Mismatch on query {i+1} ('{queries[i]}'):\nExpected: {o_line}\nGot:      {a_line}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

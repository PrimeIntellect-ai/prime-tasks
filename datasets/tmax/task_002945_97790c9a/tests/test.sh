#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import random
import string
import subprocess
import sys
import pytest

ORACLE_PATH = "/tests/oracle_graph_etl"
AGENT_PATH = "/app/etl_pipeline/target/release/graph_etl"
NUM_TESTS = 500

def generate_random_input():
    num_nodes = random.randint(0, 30)
    nodes = []
    node_ids = []
    for _ in range(num_nodes):
        node_id = "".join(random.choices(string.ascii_letters, k=random.randint(2, 5)))
        node_ids.append(node_id)
        status = random.choice(["ACTIVE", "INACTIVE", "PENDING"])
        nodes.append({"id": node_id, "status": status})

    num_edges = random.randint(0, 100)
    edges = []
    for _ in range(num_edges):
        # Allow some edges to have non-existent nodes to test robustness
        if node_ids and random.random() < 0.9:
            src = random.choice(node_ids)
            dst = random.choice(node_ids)
        else:
            src = "".join(random.choices(string.ascii_letters, k=random.randint(2, 5)))
            dst = "".join(random.choices(string.ascii_letters, k=random.randint(2, 5)))

        action = random.choice(["CONNECT", "DISCONNECT", "VIEW"])
        val = random.randint(-100, 100)
        edges.append({"src": src, "dst": dst, "action": action, "val": val})

    return json.dumps({"nodes": nodes, "edges": edges})

def test_agent_executable_exists():
    assert os.path.exists(AGENT_PATH), f"Agent executable missing at {AGENT_PATH}. Did you compile in release mode?"
    assert os.path.isfile(AGENT_PATH), f"{AGENT_PATH} is not a file."
    assert os.access(AGENT_PATH, os.X_OK), f"Agent executable at {AGENT_PATH} is not executable."

def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle script missing at {ORACLE_PATH}"

    random.seed(42)
    inputs = [generate_random_input() for _ in range(NUM_TESTS)]

    for i, inp in enumerate(inputs):
        # Run Oracle uploaded only at verification time
        oracle_proc = subprocess.run(
            [sys.executable, ORACLE_PATH],
            input=inp,
            text=True,
            capture_output=True,
            check=False
        )
        oracle_out = oracle_proc.stdout.strip()

        # Run Agent
        agent_proc = subprocess.run(
            [AGENT_PATH],
            input=inp,
            text=True,
            capture_output=True,
            check=False
        )
        agent_out = agent_proc.stdout.strip()

        assert agent_proc.returncode == 0, f"Agent program failed with return code {agent_proc.returncode} on input:\n{inp}\nStderr:\n{agent_proc.stderr}"

        assert agent_out == oracle_out, (
            f"Output mismatch on fuzz test {i+1}/{NUM_TESTS}.\n"
            f"Input:\n{inp}\n\n"
            f"Expected (Oracle):\n{oracle_out}\n\n"
            f"Got (Agent):\n{agent_out}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

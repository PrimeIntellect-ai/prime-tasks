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
import pytest

ORACLE_PATH = "/tests/oracle_relevance_calc"
AGENT_PATH = "/home/user/relevance_calc"
NUM_ITERATIONS = 200

def generate_random_graph(seed):
    random.seed(seed)
    num_nodes = random.randint(1, 100)
    nodes = []
    node_ids = set()

    # Generate unique node IDs
    while len(node_ids) < num_nodes:
        id_len = random.randint(1, 8)
        node_id = "".join(random.choices(string.ascii_letters + string.digits, k=id_len))
        node_ids.add(node_id)

    node_ids = list(node_ids)
    for node_id in node_ids:
        weight = round(random.uniform(0.0, 100.0), 2)
        nodes.append({"id": node_id, "weight": weight})

    num_edges = random.randint(0, 200)
    edges = []
    for _ in range(num_edges):
        src = random.choice(node_ids)
        dst = random.choice(node_ids)
        edges.append({"src": src, "dst": dst})

    return {"nodes": nodes, "edges": edges}

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle not found at {ORACLE_PATH}"
    assert os.path.isfile(AGENT_PATH), f"Agent binary not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary {AGENT_PATH} is not executable"

    for i in range(NUM_ITERATIONS):
        graph_data = generate_random_graph(seed=1000 + i)
        input_json = json.dumps(graph_data)

        oracle_proc = subprocess.run(
            [ORACLE_PATH],
            input=input_json,
            text=True,
            capture_output=True
        )

        agent_proc = subprocess.run(
            [AGENT_PATH],
            input=input_json,
            text=True,
            capture_output=True
        )

        assert agent_proc.returncode == oracle_proc.returncode, (
            f"Return code mismatch on iteration {i}.\n"
            f"Oracle: {oracle_proc.returncode}, Agent: {agent_proc.returncode}\n"
            f"Input: {input_json}"
        )

        if oracle_proc.returncode == 0:
            try:
                oracle_out = json.loads(oracle_proc.stdout)
                agent_out = json.loads(agent_proc.stdout)
                assert oracle_out == agent_out, (
                    f"Parsed JSON output mismatch on iteration {i}.\n"
                    f"Input: {input_json}\n"
                    f"Oracle: {oracle_out}\n"
                    f"Agent: {agent_out}"
                )
            except json.JSONDecodeError:
                # Fallback to string comparison if output is not valid JSON
                assert oracle_proc.stdout == agent_proc.stdout, (
                    f"Raw output mismatch on iteration {i}.\n"
                    f"Input: {input_json}\n"
                    f"Oracle: {oracle_proc.stdout}\n"
                    f"Agent: {agent_proc.stdout}"
                )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

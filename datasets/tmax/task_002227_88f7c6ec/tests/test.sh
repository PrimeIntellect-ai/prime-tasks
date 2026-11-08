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

AGENT_SCRIPT = "/home/user/graph_query.py"
ORACLE_SCRIPT = "/tests/oracle.py"
NUM_ITERATIONS = 200

def generate_random_graph(seed):
    random.seed(seed)
    num_nodes = random.randint(100, 500)
    num_edges = random.randint(200, 1000)

    nodes = []
    node_ids = []
    for _ in range(num_nodes):
        node_id = ''.join(random.choices(string.ascii_letters + string.digits, k=8))
        node_ids.append(node_id)
        node_type = random.choice(["User", "Product", "Category"])
        node = {"id": node_id, "type": node_type}
        if node_type == "Product":
            node["price"] = random.randint(1, 20)
        nodes.append(node)

    edges = []
    if num_nodes > 1:
        for _ in range(num_edges):
            source = random.choice(node_ids)
            target = random.choice(node_ids)
            edges.append({"source": source, "target": target})

    return json.dumps({"nodes": nodes, "edges": edges})

def test_agent_script_exists():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), f"Path {AGENT_SCRIPT} is not a file"

def test_oracle_script_exists():
    assert os.path.exists(ORACLE_SCRIPT), f"Oracle script not found at {ORACLE_SCRIPT}"

def test_fuzz_equivalence():
    assert os.path.exists(AGENT_SCRIPT), "Agent script missing."
    assert os.path.exists(ORACLE_SCRIPT), "Oracle script missing."

    for i in range(NUM_ITERATIONS):
        graph_json = generate_random_graph(seed=i)
        input_data = graph_json.encode('utf-8')

        oracle_proc = subprocess.run(
            ["python3", ORACLE_SCRIPT],
            input=input_data,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i} with error: {oracle_proc.stderr.decode()}"
        oracle_output = oracle_proc.stdout.decode('utf-8').strip()

        agent_proc = subprocess.run(
            ["python3", AGENT_SCRIPT],
            input=input_data,
            capture_output=True
        )
        assert agent_proc.returncode == 0, f"Agent script failed on iteration {i} with error: {agent_proc.stderr.decode()}"
        agent_output = agent_proc.stdout.decode('utf-8').strip()

        if oracle_output != agent_output:
            error_msg = (
                f"Mismatch on iteration {i}.\n"
                f"Input JSON (truncated): {graph_json[:200]}...\n"
                f"Expected (Oracle) Output: {oracle_output}\n"
                f"Actual (Agent) Output: {agent_output}"
            )
            pytest.fail(error_msg)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

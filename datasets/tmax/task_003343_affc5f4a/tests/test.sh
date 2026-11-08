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

def generate_random_graph(num_nodes, avg_out_degree):
    nodes = [str(i) for i in range(1, num_nodes + 1)]
    graph = {node: [] for node in nodes}

    num_edges = int(num_nodes * avg_out_degree)
    for _ in range(num_edges):
        u = random.choice(nodes)
        v = random.choice(nodes)
        if v not in graph[u]:
            graph[u].append(v)

    return graph

def test_path_finder_fuzz_equivalence():
    agent_script = "/home/user/path_finder.py"
    oracle_script = "/tests/oracle.py"

    assert os.path.isfile(agent_script), f"Agent script missing at {agent_script}"
    assert os.path.isfile(oracle_script), f"Oracle script missing at {oracle_script}"

    random.seed(42)
    N = 200

    for i in range(N):
        num_nodes = random.randint(10, 50)
        avg_out_degree = random.uniform(1, 4)

        graph = generate_random_graph(num_nodes, avg_out_degree)
        start_node = random.choice(list(graph.keys()))

        graph_json = json.dumps(graph)

        # Run oracle
        oracle_cmd = ["python3", oracle_script, "--graph", graph_json, "--start", start_node]
        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_res.returncode == 0, f"Oracle failed on input {i}:\n{oracle_res.stderr}"
        oracle_out = oracle_res.stdout.strip()

        # Run agent
        agent_cmd = ["python3", agent_script, "--graph", graph_json, "--start", start_node]
        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)
        assert agent_res.returncode == 0, f"Agent script failed on input {i}:\n{agent_res.stderr}"
        agent_out = agent_res.stdout.strip()

        assert agent_out == oracle_out, (
            f"Mismatch on input {i}:\n"
            f"Graph: {graph_json}\n"
            f"Start: {start_node}\n"
            f"Oracle output: {oracle_out}\n"
            f"Agent output: {agent_out}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

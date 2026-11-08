#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import json
import random
import string
import tempfile
import pytest

def test_jq_compiled_and_functional():
    """Verify that jq has been compiled and works."""
    jq_path = "/app/jq-1.6/jq"
    assert os.path.isfile(jq_path), f"Compiled jq not found at {jq_path}"
    assert os.access(jq_path, os.X_OK), f"Compiled jq at {jq_path} is not executable"

    result = subprocess.run([jq_path, "--version"], capture_output=True, text=True)
    assert "jq-1.6" in result.stdout or "jq-1.6" in result.stderr, "jq --version did not output 'jq-1.6'"

def test_query_script_exists():
    """Verify that the user script exists."""
    script_path = "/home/user/query_2hop.sh"
    assert os.path.isfile(script_path), f"Script {script_path} not found"

def generate_random_graph(num_edges):
    """Generate a random JSONL graph and return the lines and a list of nodes."""
    nodes = ["".join(random.choices(string.ascii_letters + string.digits, k=random.randint(4, 8))) for _ in range(num_edges // 2)]
    edges = []
    for _ in range(num_edges):
        source = random.choice(nodes)
        target = random.choice(nodes)
        edges.append(json.dumps({"source": source, "target": target, "transaction_type": "transfer"}))
    return edges, nodes

def test_fuzz_equivalence():
    """Fuzz the agent's script against the oracle."""
    script_path = "/home/user/query_2hop.sh"
    oracle_path = "/tests/query_2hop_reference.py"

    assert os.path.isfile(script_path), f"Agent script missing: {script_path}"
    assert os.path.isfile(oracle_path), f"Oracle script missing: {oracle_path}"

    random.seed(42)
    N = 100

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(N):
            num_edges = random.randint(500, 2000)
            edges, nodes = generate_random_graph(num_edges)
            target_node = random.choice(nodes)

            graph_file = os.path.join(tmpdir, f"graph_{i}.jsonl")
            with open(graph_file, "w") as f:
                f.write("\n".join(edges) + "\n")

            # Run oracle
            oracle_cmd = ["python3", oracle_path, target_node, graph_file]
            oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
            assert oracle_res.returncode == 0, f"Oracle failed on input {i}:\n{oracle_res.stderr}"

            # Run agent
            agent_cmd = ["bash", script_path, target_node, graph_file]
            agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)

            oracle_out = oracle_res.stdout.strip()
            agent_out = agent_res.stdout.strip()

            assert agent_res.returncode == 0, f"Agent script failed on input {i}:\n{agent_res.stderr}"
            assert agent_out == oracle_out, (
                f"Mismatch on fuzz iteration {i}.\n"
                f"Target node: {target_node}\n"
                f"Oracle output:\n{oracle_out}\n\n"
                f"Agent output:\n{agent_out}\n"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

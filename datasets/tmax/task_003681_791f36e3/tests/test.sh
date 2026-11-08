#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import tempfile
import csv
import pytest

def test_sqlite_binary_built():
    bin_path = "/app/sqlite-amalgamation-3430000/sqlite3"
    assert os.path.isfile(bin_path), f"Expected sqlite3 binary not found at {bin_path}. Did you compile it?"
    assert os.access(bin_path, os.X_OK), f"sqlite3 binary at {bin_path} is not executable."

def generate_random_graph(num_nodes, density):
    edges = []
    for i in range(num_nodes):
        for j in range(num_nodes):
            if i != j and random.random() < density:
                edges.append((f"node_{i}", f"node_{j}"))
    return edges

def test_fuzz_equivalence():
    oracle_path = "/tests/oracle.py"
    agent_path = "/home/user/etl.sh"

    assert os.path.isfile(oracle_path), f"Oracle not found at {oracle_path}."
    assert os.path.isfile(agent_path), f"Agent script not found at {agent_path}."
    assert os.access(agent_path, os.X_OK), f"Agent script at {agent_path} is not executable."

    random.seed(42)

    for i in range(20):
        num_nodes = random.randint(10, 100)
        density = random.uniform(0.05, 0.2)
        edges = generate_random_graph(num_nodes, density)

        with tempfile.NamedTemporaryFile(mode='w', suffix='.csv', delete=False) as f:
            writer = csv.writer(f)
            writer.writerow(["source", "target"])
            writer.writerows(edges)
            tmp_filename = f.name

        try:
            oracle_proc = subprocess.run(["python3", oracle_path, tmp_filename], capture_output=True, text=True)
            assert oracle_proc.returncode == 0, f"Oracle failed on test case {i}. Stderr: {oracle_proc.stderr}"

            agent_proc = subprocess.run([agent_path, tmp_filename], capture_output=True, text=True)

            if agent_proc.returncode != 0:
                pytest.fail(f"Agent script failed with return code {agent_proc.returncode} on test case {i}.\nStderr: {agent_proc.stderr}")

            oracle_out = oracle_proc.stdout.strip()
            agent_out = agent_proc.stdout.strip()

            if oracle_out != agent_out:
                pytest.fail(
                    f"Output mismatch on test case {i} (nodes: {num_nodes}, edges: {len(edges)}).\n"
                    f"Oracle output:\n{oracle_out}\n\n"
                    f"Agent output:\n{agent_out}\n"
                )
        finally:
            os.remove(tmp_filename)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

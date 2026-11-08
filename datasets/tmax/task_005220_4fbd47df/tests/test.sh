#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import string
import tempfile
import pytest

def test_sqlite3_compiled():
    sqlite3_path = '/app/sqlite-autoconf/sqlite3'
    assert os.path.isfile(sqlite3_path), f"Compiled sqlite3 binary not found at {sqlite3_path}"
    assert os.access(sqlite3_path, os.X_OK), f"sqlite3 binary at {sqlite3_path} is not executable"

    # Check if it runs
    result = subprocess.run([sqlite3_path, '--version'], capture_output=True, text=True)
    assert result.returncode == 0, f"sqlite3 --version failed with error: {result.stderr}"
    assert result.stdout.strip() != "", "sqlite3 --version returned empty output"

def test_fuzz_equivalence():
    agent_script = '/home/user/graph_join.sh'
    oracle_script = '/tests/oracle_graph_join.sh'

    assert os.path.isfile(agent_script), f"Agent script not found at {agent_script}"
    assert os.path.isfile(oracle_script), f"Oracle script not found at {oracle_script}"

    random.seed(42)

    def random_string(length=8):
        return ''.join(random.choices(string.ascii_letters, k=length))

    N = 25
    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(N):
            nodes_file = os.path.join(tmpdir, f'nodes_{i}.csv')
            edges_file = os.path.join(tmpdir, f'edges_{i}.csv')

            num_nodes = random.randint(10, 100)
            node_ids = random.sample(range(1, 1000), num_nodes)

            with open(nodes_file, 'w') as f:
                f.write("id,name,weight\n")
                for nid in node_ids:
                    f.write(f"{nid},{random_string()},{random.uniform(0.1, 10.0):.2f}\n")

            num_edges = random.randint(5, 200)
            with open(edges_file, 'w') as f:
                f.write("source_id,target_id,relation\n")
                for _ in range(num_edges):
                    src = random.choice(node_ids)
                    tgt = random.choice(node_ids)
                    f.write(f"{src},{tgt},{random_string(5)}\n")

            agent_cmd = ['bash', agent_script, nodes_file, edges_file]
            oracle_cmd = ['bash', oracle_script, nodes_file, edges_file]

            agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)
            oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)

            assert agent_res.returncode == 0, f"Agent script failed on iteration {i}:\n{agent_res.stderr}"
            assert oracle_res.returncode == 0, f"Oracle script failed on iteration {i}:\n{oracle_res.stderr}"

            assert agent_res.stdout == oracle_res.stdout, (
                f"Mismatch on iteration {i}.\n"
                f"Nodes file: {nodes_file}\n"
                f"Edges file: {edges_file}\n"
                f"Oracle output:\n{oracle_res.stdout}\n"
                f"Agent output:\n{agent_res.stdout}\n"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import subprocess
import tempfile
import pytest

ORACLE = "/app/impact_calculator"
AGENT = "/home/user/impact.sh"
N_TESTS = 50

def generate_dag(num_nodes, num_edges):
    nodes = [f"N{i}" for i in range(1, num_nodes + 1)]

    # To ensure acyclic, only add edges from N_i to N_j where i < j
    possible_edges = [(i, j) for i in range(1, num_nodes) for j in range(i + 1, num_nodes + 1)]

    if num_edges > len(possible_edges):
        num_edges = len(possible_edges)

    chosen_edges = random.sample(possible_edges, num_edges)

    target = random.choice(nodes)

    lines = [f"TARGET: {target}"]
    for i, j in chosen_edges:
        lines.append(f"N{i} -> N{j}")

    return "\n".join(lines) + "\n"

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE), f"Oracle program {ORACLE} not found."
    assert os.access(ORACLE, os.X_OK), f"Oracle program {ORACLE} is not executable."

    assert os.path.isfile(AGENT), f"Agent program {AGENT} not found."
    assert os.access(AGENT, os.X_OK), f"Agent program {AGENT} is not executable."

    random.seed(42)

    for i in range(N_TESTS):
        num_nodes = random.randint(10, 100)
        num_edges = random.randint(10, 500)
        dag_content = generate_dag(num_nodes, num_edges)

        with tempfile.NamedTemporaryFile(mode='w', delete=False) as f:
            f.write(dag_content)
            temp_path = f.name

        try:
            oracle_proc = subprocess.run([ORACLE, temp_path], capture_output=True, text=True)
            agent_proc = subprocess.run([AGENT, temp_path], capture_output=True, text=True)

            oracle_out = oracle_proc.stdout.strip()
            agent_out = agent_proc.stdout.strip()

            assert oracle_out == agent_out, (
                f"Mismatch on fuzz test {i+1}/{N_TESTS}.\n"
                f"Input graph:\n{dag_content}\n"
                f"Oracle output: '{oracle_out}'\n"
                f"Agent output: '{agent_out}'\n"
                f"Oracle stderr: '{oracle_proc.stderr}'\n"
                f"Agent stderr: '{agent_proc.stderr}'"
            )
        finally:
            os.remove(temp_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

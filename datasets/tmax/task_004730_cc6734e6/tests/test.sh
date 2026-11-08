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

ORACLE_PATH = "/tests/query_edges_oracle.py"
AGENT_SCRIPT = "/app/sh-graph-query-1.0/bin/query_edges.sh"

def generate_edges_csv(filepath, num_edges=1000):
    """Generate a random edges.csv file."""
    random.seed(42)
    with open(filepath, "w") as f:
        for _ in range(num_edges):
            source = random.randint(1, 500)
            target = random.randint(1, 500)
            weight = random.randint(1, 100)
            f.write(f"{source},{target},{weight}\n")

def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"
    assert os.path.exists(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"

    with tempfile.TemporaryDirectory() as tmpdir:
        csv_path = os.path.join(tmpdir, "edges.csv")
        generate_edges_csv(csv_path)

        random.seed(1337)
        test_inputs = [str(random.randint(1, 500)) for _ in range(100)]

        for node_id in test_inputs:
            oracle_proc = subprocess.run(
                [ORACLE_PATH, node_id],
                cwd=tmpdir,
                capture_output=True,
                text=True,
                check=False
            )
            oracle_out = oracle_proc.stdout

            agent_proc = subprocess.run(
                ["bash", AGENT_SCRIPT, node_id],
                cwd=tmpdir,
                capture_output=True,
                text=True,
                check=False
            )
            agent_out = agent_proc.stdout

            assert agent_out == oracle_out, (
                f"Mismatch for node_id {node_id}.\n"
                f"Oracle output:\n{oracle_out}\n"
                f"Agent output:\n{agent_out}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

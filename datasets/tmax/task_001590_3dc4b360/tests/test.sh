#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import subprocess
import pytest

AGENT_SCRIPT = "/home/user/project_graph.py"
ORACLE_BIN = "/tests/oracle_project_graph"
LABELS = ["ALPHA", "BETA", "GAMMA", "DELTA", "EPSILON", "ZETA", "ETA", "THETA", "IOTA", "KAPPA"]
N_ITERATIONS = 50

def test_agent_script_exists():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_BIN), f"Oracle not found at {ORACLE_BIN}"
    assert os.access(ORACLE_BIN, os.X_OK), f"Oracle at {ORACLE_BIN} is not executable"

    random.seed(42)

    for i in range(N_ITERATIONS):
        node_label = random.choice(LABELS)
        max_depth = random.randint(1, 5)

        # Run oracle
        oracle_cmd = [ORACLE_BIN, str(node_label), str(max_depth)]
        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_res.returncode == 0, f"Oracle failed on input {node_label} {max_depth}:\n{oracle_res.stderr}"
        oracle_out = oracle_res.stdout.strip()

        # Run agent
        agent_cmd = ["python3", AGENT_SCRIPT, str(node_label), str(max_depth)]
        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)
        assert agent_res.returncode == 0, f"Agent script failed on input {node_label} {max_depth}:\n{agent_res.stderr}"
        agent_out = agent_res.stdout.strip()

        assert agent_out == oracle_out, (
            f"Mismatch on iteration {i+1} with inputs node_label={node_label}, max_depth={max_depth}.\n"
            f"Expected (Oracle): {oracle_out}\n"
            f"Got (Agent): {agent_out}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

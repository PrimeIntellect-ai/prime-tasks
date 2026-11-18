#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import pytest

AGENT_SCRIPT = "/home/user/query.sh"
ORACLE_SCRIPT = "/tests/query_oracle.sh"
NETWORK_FILE = "/home/user/network.tsv"

def test_agent_script_exists_and_executable():
    """Check if the agent's query.sh exists and is executable."""
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script missing: {AGENT_SCRIPT}"
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script is not executable: {AGENT_SCRIPT}"

def test_fuzz_equivalence():
    """Fuzz the agent's script against the oracle on 100 random protein pairs."""
    assert os.path.isfile(NETWORK_FILE), f"Network file missing: {NETWORK_FILE}"
    assert os.path.isfile(ORACLE_SCRIPT), f"Oracle script missing: {ORACLE_SCRIPT}"

    # Extract all unique proteins from the network file
    proteins = set()
    with open(NETWORK_FILE, 'r') as f:
        for line in f:
            parts = line.strip().split('\t')
            if len(parts) >= 2:
                proteins.add(parts[0])
                proteins.add(parts[1])

    proteins = sorted(list(proteins))
    assert len(proteins) > 0, "No proteins found in network file"

    random.seed(42)

    # Generate 100 random pairs for fuzzing
    pairs = [(random.choice(proteins), random.choice(proteins)) for _ in range(100)]

    # Ensure at least one self-loop is tested
    if proteins:
        pairs.append((proteins[0], proteins[0]))

    for start_node, end_node in pairs:
        # Run oracle, which is uploaded only at verification time
        oracle_res = subprocess.run(
            ["bash", ORACLE_SCRIPT, start_node, end_node],
            capture_output=True, text=True
        )
        oracle_output = oracle_res.stdout.strip()

        # Run agent
        agent_res = subprocess.run(
            [AGENT_SCRIPT, start_node, end_node],
            capture_output=True, text=True
        )
        agent_output = agent_res.stdout.strip()

        assert agent_output == oracle_output, (
            f"Mismatch for input: Start='{start_node}', End='{end_node}'.\n"
            f"Oracle output: '{oracle_output}'\n"
            f"Agent output: '{agent_output}'\n"
            f"Agent stderr: '{agent_res.stderr.strip()}'"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

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
import tempfile
import pytest

def generate_tree(num_nodes):
    nodes = []
    node_ids = []

    def rand_str():
        return ''.join(random.choices(string.ascii_letters + string.digits, k=random.randint(5, 10)))

    for i in range(num_nodes):
        nid = rand_str()
        while nid in node_ids:
            nid = rand_str()
        node_ids.append(nid)

        parent_id = None
        if i > 0 and random.random() > 0.2:
            # Pick a parent from already created nodes to ensure it's a valid tree (no cycles)
            parent_id = random.choice(node_ids[:i])

        nodes.append({
            'X_Z9': nid,
            'P_K2': parent_id,
            'S_M1': random.randint(1, 1000000),
            'T_D5': random.randint(1600000000, 1700000000)
        })

    # Shuffle so parent isn't necessarily before child in the JSONL file
    random.shuffle(nodes)
    return nodes

def test_fuzz_equivalence():
    """Fuzz test the agent's script against the oracle to ensure bit-exact equivalence."""
    agent_path = "/home/user/restore_planner.py"
    oracle_path = "/tests/oracle.py"

    assert os.path.exists(agent_path), f"Agent script is missing at {agent_path}"
    assert os.path.exists(oracle_path), f"Oracle script is missing at {oracle_path}"

    random.seed(42)
    N = 50

    for i in range(N):
        num_nodes = random.randint(50, 500)
        tree = generate_tree(num_nodes)

        with tempfile.NamedTemporaryFile('w', delete=False, suffix='.jsonl') as f:
            for node in tree:
                f.write(json.dumps(node) + '\n')
            temp_path = f.name

        try:
            oracle_proc = subprocess.run(
                ['python3', oracle_path, temp_path],
                capture_output=True, text=True, check=True
            )
            agent_proc = subprocess.run(
                ['python3', agent_path, temp_path],
                capture_output=True, text=True
            )

            assert agent_proc.returncode == 0, (
                f"Agent script failed on fuzz run {i + 1}/{N} with return code {agent_proc.returncode}.\n"
                f"Stderr:\n{agent_proc.stderr}\n"
                f"Input file had {num_nodes} nodes."
            )

            oracle_out = oracle_proc.stdout.strip()
            agent_out = agent_proc.stdout.strip()

            if oracle_out != agent_out:
                # Truncate output if it's too long for the error message
                oracle_disp = oracle_out if len(oracle_out) < 1000 else oracle_out[:1000] + "\n...[truncated]"
                agent_disp = agent_out if len(agent_out) < 1000 else agent_out[:1000] + "\n...[truncated]"
                pytest.fail(
                    f"Output mismatch on fuzz run {i + 1}/{N}!\n"
                    f"Input contained {num_nodes} nodes.\n\n"
                    f"--- ORACLE OUTPUT ---\n{oracle_disp}\n\n"
                    f"--- AGENT OUTPUT ---\n{agent_disp}\n"
                )
        finally:
            os.remove(temp_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

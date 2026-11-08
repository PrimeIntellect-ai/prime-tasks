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

def test_vendored_package_fixed():
    core_py_path = "/app/sqlite-graph-builder-0.4.5/sqlite_graph_builder/core.py"
    assert os.path.exists(core_py_path), f"The file {core_py_path} is missing."

    with open(core_py_path, "r") as f:
        content = f.read()

    assert "INDEXED BY idx_parent_stale" not in content, (
        f"The file {core_py_path} still contains the corrupted index directive 'INDEXED BY idx_parent_stale'. "
        "You must remove it to fix the package."
    )

def test_fuzz_equivalence():
    agent_script = "/home/user/fetch_subtree.py"
    oracle_script = "/tests/fetch_subtree_oracle.py"

    assert os.path.exists(agent_script), f"Agent script {agent_script} does not exist."
    assert os.path.exists(oracle_script), f"Oracle script {oracle_script} does not exist."

    random.seed(42)
    fuzz_inputs = [random.randint(1, 500) for _ in range(50)]

    for node_id in fuzz_inputs:
        # Run oracle
        oracle_cmd = ["python3", oracle_script, str(node_id)]
        oracle_proc = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_proc.returncode == 0, f"Oracle failed on input {node_id}:\n{oracle_proc.stderr}"

        # Run agent
        agent_cmd = ["python3", agent_script, str(node_id)]
        agent_proc = subprocess.run(agent_cmd, capture_output=True, text=True)
        assert agent_proc.returncode == 0, f"Agent script failed on input {node_id}:\n{agent_proc.stderr}"

        # Parse JSON to compare structurally, ignoring formatting differences
        try:
            oracle_json = json.loads(oracle_proc.stdout)
        except json.JSONDecodeError:
            pytest.fail(f"Oracle returned invalid JSON on input {node_id}: {oracle_proc.stdout}")

        try:
            agent_json = json.loads(agent_proc.stdout)
        except json.JSONDecodeError:
            pytest.fail(f"Agent returned invalid JSON on input {node_id}: {agent_proc.stdout}")

        assert agent_json == oracle_json, (
            f"Output mismatch for node_id={node_id}.\n"
            f"Expected JSON:\n{json.dumps(oracle_json, indent=2)}\n"
            f"Got JSON:\n{json.dumps(agent_json, indent=2)}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

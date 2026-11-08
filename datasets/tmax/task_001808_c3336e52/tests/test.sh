#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import random
import subprocess
import pytest


def test_graph_query_fuzz_equivalence():
    agent_script = "/home/user/graph_query.py"
    oracle_script = "/tests/oracle_graph_query.py"

    assert os.path.exists(agent_script), f"Agent script not found at {agent_script}"
    assert os.path.exists(oracle_script), f"Oracle script not found at {oracle_script}"

    nodes = [
        "internet", "firewall", "router", "switch_A", "switch_B",
        "app_server_1", "app_server_2", "db_master", "db_replica",
        "backup_storage", "cache_server"
    ]
    invalid_nodes = ["invalid_node", "fake_router", "unknown_server"]

    random.seed(42)
    inputs = []

    for _ in range(500):
        r = random.random()
        if r < 0.4:
            if random.random() < 0.1:
                node = random.choice(invalid_nodes)
            else:
                node = random.choice(nodes)
            inputs.append({"action": "pagerank", "node": node})
        elif r < 0.8:
            source = random.choice(nodes)
            target = random.choice(nodes)
            inputs.append({"action": "shortest_path", "source": source, "target": target})
        else:
            limit = random.randint(1, 15)
            inputs.append({"action": "top_in_degree", "limit": limit})

    input_str = "\n".join(json.dumps(req) for req in inputs) + "\n"

    oracle_proc = subprocess.run(
        ["python3", oracle_script],
        input=input_str,
        text=True,
        capture_output=True
    )
    assert oracle_proc.returncode == 0, f"Oracle failed with error:\n{oracle_proc.stderr}"

    agent_proc = subprocess.run(
        ["python3", agent_script],
        input=input_str,
        text=True,
        capture_output=True
    )
    assert agent_proc.returncode == 0, f"Agent script failed with error:\n{agent_proc.stderr}"

    oracle_lines = oracle_proc.stdout.strip().split("\n")
    agent_lines = agent_proc.stdout.strip().split("\n")

    assert len(agent_lines) == len(oracle_lines), (
        f"Output line count mismatch. Expected {len(oracle_lines)}, got {len(agent_lines)}"
    )

    for i, (req, oracle_line, agent_line) in enumerate(zip(inputs, oracle_lines, agent_lines)):
        try:
            oracle_json = json.loads(oracle_line)
        except json.JSONDecodeError:
            pytest.fail(f"Oracle returned invalid JSON on line {i+1}: {oracle_line}")

        try:
            agent_json = json.loads(agent_line)
        except json.JSONDecodeError:
            pytest.fail(
                f"Agent returned invalid JSON on line {i+1}: {agent_line}\n"
                f"Input was: {json.dumps(req)}"
            )

        assert agent_json == oracle_json, (
            f"Mismatch on input {i+1}: {json.dumps(req)}\n"
            f"Expected: {oracle_line}\n"
            f"Got:      {agent_line}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

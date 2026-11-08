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

def generate_random_id():
    return "snap-" + "".join(random.choices(string.ascii_lowercase + string.digits, k=8))

def generate_backup_graph(num_nodes):
    nodes = {}
    full_nodes = []

    # Create at least one full backup
    for _ in range(max(1, num_nodes // 10)):
        node_id = generate_random_id()
        nodes[node_id] = {
            "id": node_id,
            "type": "full",
            "timestamp": random.randint(1600000000, 1700000000)
        }
        full_nodes.append(node_id)

    # Create incremental backups
    existing_nodes = list(nodes.keys())
    for _ in range(num_nodes - len(full_nodes)):
        node_id = generate_random_id()
        parent_id = random.choice(existing_nodes)
        nodes[node_id] = {
            "id": node_id,
            "type": "incremental",
            "parent": parent_id,
            "timestamp": nodes[parent_id]["timestamp"] + random.randint(100, 10000)
        }
        existing_nodes.append(node_id)

    return list(nodes.values())

def compute_expected_chain(nodes, target_id):
    node_map = {n["id"]: n for n in nodes}
    chain = []
    curr = target_id
    while curr:
        chain.append(curr)
        node = node_map.get(curr)
        if not node:
            break
        if node.get("type") == "full":
            break
        curr = node.get("parent")
    chain.reverse()
    return ",".join(chain)

def test_executable_exists():
    assert os.path.exists("/home/user/bin/get_chain.sh"), "The executable /home/user/bin/get_chain.sh was not found."
    assert os.access("/home/user/bin/get_chain.sh", os.X_OK), "/home/user/bin/get_chain.sh is not executable."

def test_fuzz_equivalence():
    random.seed(42)
    agent_executable = "/home/user/bin/get_chain.sh"

    assert os.path.exists(agent_executable), f"Agent program missing at {agent_executable}"

    for i in range(50):
        num_nodes = random.randint(5, 500)
        nodes = generate_backup_graph(num_nodes)
        random.shuffle(nodes)  # Shuffle to ensure order doesn't matter

        target_node = random.choice(nodes)
        target_id = target_node["id"]

        expected_output = compute_expected_chain(nodes, target_id)

        with tempfile.NamedTemporaryFile(mode='w', delete=False, suffix='.jsonl') as tmp:
            for node in nodes:
                tmp.write(json.dumps(node) + '\n')
            tmp_path = tmp.name

        try:
            result = subprocess.run(
                [agent_executable, tmp_path, target_id],
                capture_output=True,
                text=True,
                timeout=5
            )

            agent_output = result.stdout.strip()

            assert result.returncode == 0, f"Agent program failed with return code {result.returncode}. Stderr: {result.stderr}"
            assert agent_output == expected_output, (
                f"Mismatch on iteration {i}.\n"
                f"Target ID: {target_id}\n"
                f"Expected: {expected_output}\n"
                f"Got: {agent_output}\n"
            )
        finally:
            if os.path.exists(tmp_path):
                os.remove(tmp_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

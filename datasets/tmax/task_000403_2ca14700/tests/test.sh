#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import random
import string
import stat
import subprocess
import tempfile

ORACLE_PATH = "/app/route_calc"
AGENT_SCRIPT = "/home/user/route_calc.py"


def generate_random_topology(seed):
    random.seed(seed)
    num_nodes = random.randint(10, 50)

    nodes = []
    for _ in range(num_nodes):
        node_id = ''.join(random.choices(string.ascii_uppercase + string.digits, k=8))
        nodes.append(node_id)

    num_storage = random.randint(1, 5)
    storage_nodes = random.sample(nodes, num_storage)
    available_targets = [n for n in nodes if n not in storage_nodes]
    target_node = random.choice(available_targets)

    edges = []
    num_edges = random.randint(num_nodes, num_nodes * 3)
    for _ in range(num_edges):
        src = random.choice(nodes)
        dst = random.choice(nodes)
        if src != dst:
            edges.append({
                "src": src,
                "dst": dst,
                "latency_ms": random.randint(1, 100),
                "throughput_penalty": random.randint(1, 50)
            })

    path_length = random.randint(1, 3)
    current = random.choice(storage_nodes)
    for _ in range(path_length - 1):
        next_node = random.choice([n for n in nodes if n != current and n != target_node])
        edges.append({
            "src": current,
            "dst": next_node,
            "latency_ms": random.randint(1, 100),
            "throughput_penalty": random.randint(1, 50)
        })
        current = next_node
    edges.append({
        "src": current,
        "dst": target_node,
        "latency_ms": random.randint(1, 100),
        "throughput_penalty": random.randint(1, 50)
    })

    topology = {
        "nodes": [{"id": n, "is_backup_storage": n in storage_nodes} for n in nodes],
        "edges": edges
    }
    return topology, target_node


def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle not executable at {ORACLE_PATH}"
    assert os.path.exists(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script is not a regular file: {AGENT_SCRIPT}"

    app_mode = stat.S_IMODE(os.stat("/app").st_mode)
    with tempfile.TemporaryDirectory() as tmpdir:
        os.chmod(tmpdir, 0o755)
        cases = []

        # Obtain oracle answers before making the proprietary executable
        # inaccessible to the account used to run the submission.
        for i in range(100):
            topology, target_node = generate_random_topology(seed=42 + i)
            json_path = os.path.join(tmpdir, f"topology_{i}.json")
            with open(json_path, "w") as f:
                json.dump(topology, f)
            os.chmod(json_path, 0o644)

            oracle_proc = subprocess.run(
                [ORACLE_PATH, json_path, target_node],
                capture_output=True,
                text=True
            )
            assert oracle_proc.returncode == 0, (
                f"Oracle failed on iteration {i}:\n{oracle_proc.stderr}"
            )
            cases.append((i, json_path, target_node, oracle_proc.stdout.strip()))

        try:
            # The verifier is root, but the submitted program runs as the normal
            # agent user. Prevent it from invoking /app/route_calc as a proxy.
            os.chmod("/app", 0o700)

            for i, json_path, target_node, oracle_out in cases:
                agent_proc = subprocess.run(
                    ["runuser", "-u", "user", "--", "python3", AGENT_SCRIPT,
                     json_path, target_node],
                    capture_output=True,
                    text=True
                )
                assert agent_proc.returncode == 0, (
                    f"Agent script failed on iteration {i}:\n{agent_proc.stderr}"
                )
                agent_out = agent_proc.stdout.strip()
                assert agent_out == oracle_out, (
                    f"Mismatch on iteration {i}.\n"
                    f"Target Node: {target_node}\n"
                    f"Topology saved at (in test): {json_path}\n"
                    f"Oracle output: {oracle_out}\n"
                    f"Agent output:  {agent_out}\n"
                )
        finally:
            os.chmod("/app", app_mode)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

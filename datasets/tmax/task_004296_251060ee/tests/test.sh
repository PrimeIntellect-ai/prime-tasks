#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import string
import subprocess
import tempfile
import pytest

ORACLE_PATH = "/app/backup_router"
AGENT_PATH = "/home/user/route.sh"

def generate_random_string(length=8):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))

def generate_log_file(path, num_nodes, num_edges):
    nodes = [f"db_{generate_random_string(6)}" for _ in range(num_nodes)]
    edges = []
    for _ in range(num_edges):
        u = random.choice(nodes)
        v = random.choice(nodes)
        edges.append((u, v))

    # group by u
    adj = {}
    for u, v in edges:
        adj.setdefault(u, []).append(v)

    with open(path, 'w') as f:
        for u, deps in adj.items():
            f.write(f"BACKUP_START {u}\n")
            for v in deps:
                f.write(f"DEPENDS_ON {v}\n")
            f.write("BACKUP_END\n")

    return nodes

def test_fuzz_equivalence():
    assert os.path.exists(AGENT_PATH), f"Agent script {AGENT_PATH} not found."
    assert os.access(AGENT_PATH, os.X_OK), f"Agent script {AGENT_PATH} is not executable."
    assert os.path.exists(ORACLE_PATH), f"Oracle {ORACLE_PATH} not found."

    random.seed(42)
    cases = []

    # Derive every expected answer before making the proprietary executable
    # unavailable to the submitted script.
    for i in range(50):
        num_nodes = random.randint(10, 100)
        num_edges = random.randint(10, 300)

        with tempfile.NamedTemporaryFile(mode='w', delete=False) as tmp:
            log_path = tmp.name

        nodes = generate_log_file(log_path, num_nodes, num_edges)
        src = random.choice(nodes)
        tgt = random.choice(nodes)

        oracle_cmd = [ORACLE_PATH, log_path, src, tgt]
        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        cases.append((i, log_path, src, tgt, oracle_res.stdout.strip(), oracle_res.stderr))

    os.unlink(ORACLE_PATH)

    try:
        for i, log_path, src, tgt, oracle_out, oracle_stderr in cases:
            agent_cmd = [AGENT_PATH, log_path, src, tgt]
            agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)
            agent_out = agent_res.stdout.strip()

            assert oracle_out == agent_out, (
                f"Mismatch on test case {i}!\n"
                f"Source: {src}, Target: {tgt}\n"
                f"Oracle output: {oracle_out}\n"
                f"Agent output: {agent_out}\n"
                f"Oracle stderr: {oracle_stderr}\n"
                f"Agent stderr: {agent_res.stderr}\n"
            )
    finally:
        for _, log_path, _, _, _, _ in cases:
            try:
                os.remove(log_path)
            except FileNotFoundError:
                pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

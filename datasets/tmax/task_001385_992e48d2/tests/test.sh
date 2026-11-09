#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import math

def test_video_result():
    result_file = "/home/user/video_result.txt"
    assert os.path.isfile(result_file), f"Missing {result_file}"
    with open(result_file, "r") as f:
        content = f.read().strip()
    assert content == "0 1 2 3 4 5 6 7 8 9", f"Incorrect content in {result_file}: {content}"

def generate_dag(N):
    # Generate upper triangular matrix to ensure DAG
    adj = [[0]*N for _ in range(N)]
    for i in range(N):
        for j in range(i+1, N):
            if random.random() < 0.3:
                adj[i][j] = 1

    # Randomly permute the nodes
    p = list(range(N))
    random.shuffle(p)

    adj_perm = [[0]*N for _ in range(N)]
    for i in range(N):
        for j in range(N):
            if adj[i][j] == 1:
                adj_perm[p[i]][p[j]] = 1

    s = ""
    for i in range(N):
        for j in range(N):
            s += str(adj_perm[i][j])
    return s

def generate_cyclic(N):
    # Generate a random graph with at least one cycle
    adj = [[0]*N for _ in range(N)]
    for i in range(N):
        for j in range(N):
            if i != j and random.random() < 0.2:
                adj[i][j] = 1

    # Force a cycle
    cycle_len = random.randint(2, N)
    nodes = random.sample(range(N), cycle_len)
    for i in range(cycle_len):
        u = nodes[i]
        v = nodes[(i+1)%cycle_len]
        adj[u][v] = 1

    s = ""
    for i in range(N):
        for j in range(N):
            s += str(adj[i][j])
    return s

def test_resolver_cli_fuzzing():
    agent_cli = "/home/user/resolver_cli"
    oracle_cli = "/tests/topo_sort.py"

    assert os.path.isfile(agent_cli), f"Missing agent CLI: {agent_cli}"
    assert os.access(agent_cli, os.X_OK), f"Agent CLI {agent_cli} is not executable"
    assert os.path.isfile(oracle_cli), f"Missing test oracle: {oracle_cli}"

    random.seed(42)
    inputs = []
    for _ in range(70):
        N = random.randint(5, 30)
        inputs.append(generate_dag(N))
    for _ in range(30):
        N = random.randint(5, 30)
        inputs.append(generate_cyclic(N))

    random.shuffle(inputs)

    for i, inp in enumerate(inputs):
        oracle_proc = subprocess.run(["python3", oracle_cli, inp], capture_output=True, text=True)
        agent_proc = subprocess.run([agent_cli, inp], capture_output=True, text=True)

        oracle_out = oracle_proc.stdout.strip()
        agent_out = agent_proc.stdout.strip()

        assert oracle_out == agent_out, (
            f"Fuzz test failed on input {i} (length {len(inp)}, N={math.isqrt(len(inp))}).\n"
            f"Input: {inp}\n"
            f"Expected (Oracle): {oracle_out}\n"
            f"Got (Agent): {agent_out}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

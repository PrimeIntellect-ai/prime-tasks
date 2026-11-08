#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
from collections import defaultdict, deque

def test_api_token_log():
    deps_path = "/home/user/api_deps.txt"
    assert os.path.exists(deps_path), f"{deps_path} is missing."

    graph = defaultdict(list)
    in_degree = defaultdict(int)
    nodes = set()

    with open(deps_path, "r") as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) == 2:
                u, v = parts
                graph[u].append(v)
                in_degree[v] += 1
                nodes.add(u)
                nodes.add(v)

    # Topological sort
    queue = deque([n for n in nodes if in_degree[n] == 0])
    order = []

    while queue:
        u = queue.popleft()
        order.append(u)
        for v in graph[u]:
            in_degree[v] -= 1
            if in_degree[v] == 0:
                queue.append(v)

    expected_token = ""
    for service in order:
        emu_path = f"/home/user/scripts/{service}.emu"
        dump_path = f"/home/user/mem/{service}.dump"

        mem_map = {}
        if os.path.exists(dump_path):
            with open(dump_path, "r") as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) == 2:
                        mem_map[parts[0]] = parts[1]

        if os.path.exists(emu_path):
            with open(emu_path, "r") as f:
                for line in f:
                    parts = line.strip().split()
                    if len(parts) == 2 and parts[0] == "READ":
                        addr = parts[1]
                        expected_token += mem_map.get(addr, "")

    log_path = "/home/user/api_token.log"
    assert os.path.exists(log_path), f"File {log_path} is missing."

    with open(log_path, "r") as f:
        actual_token = f.read().strip()

    assert actual_token == expected_token, f"Expected token '{expected_token}', but got '{actual_token}' in {log_path}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

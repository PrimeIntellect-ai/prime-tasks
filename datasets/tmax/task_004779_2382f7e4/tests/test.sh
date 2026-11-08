#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import os
import random
import subprocess


def test_agent_executable_exists():
    agent_path = "/home/user/graph_query"
    assert os.path.isfile(agent_path), f"Agent executable {agent_path} is missing."
    assert os.access(agent_path, os.X_OK), f"Agent executable {agent_path} is not executable."


def test_fuzz_equivalence():
    reference_path = "/tests/ground_truth_edges.txt"
    agent_path = "/home/user/graph_query"

    assert os.path.isfile(reference_path), f"Reference data {reference_path} is missing."
    assert os.path.isfile(agent_path), f"Agent executable {agent_path} is missing."

    # Match the original oracle's last-edge-wins behavior for duplicate edges.
    graph = [dict() for _ in range(100)]
    with open(reference_path, "r", encoding="utf-8") as f:
        for line in f:
            u, v, w = map(int, line.strip().split(","))
            if 0 <= u < 100 and 0 <= v < 100:
                graph[u][v] = w

    # Do not expose the reference dataset to the submitted executable.
    os.unlink(reference_path)

    def shortest_path(src, dest):
        if src < 0 or src >= 100 or dest < 0 or dest >= 100:
            return -1
        dist = [None] * 100
        dist[src] = 0
        heap = [(0, src)]
        while heap:
            d, u = heapq.heappop(heap)
            if dist[u] != d:
                continue
            if u == dest:
                return d
            for v, w in graph[u].items():
                nd = d + w
                if dist[v] is None or nd < dist[v]:
                    dist[v] = nd
                    heapq.heappush(heap, (nd, v))
        return -1

    random.seed(12345)
    queries = []
    expected = []
    for _ in range(1000):
        u = random.randint(0, 60)
        v = random.randint(0, 60)
        queries.append(f"{u} {v}")
        expected.append(str(shortest_path(u, v)))

    input_data = "\n".join(queries) + "\n"
    agent_proc = subprocess.run(
        [agent_path],
        input=input_data,
        text=True,
        capture_output=True,
        check=False
    )

    assert agent_proc.returncode == 0, f"Agent program crashed or failed: {agent_proc.stderr}"

    agent_out = agent_proc.stdout.strip().splitlines()
    assert len(expected) == len(agent_out), "Agent output line count differs from oracle."

    for q, expected_out, actual_out in zip(queries, expected, agent_out):
        assert expected_out == actual_out, \
            f"Mismatch on query '{q}': expected '{expected_out}', got '{actual_out}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

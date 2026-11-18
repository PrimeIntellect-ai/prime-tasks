#!/bin/bash
set +e
mkdir -p /logs/verifier

run_verification() {
    cd /home/user/backup_tool || return 1

    # The requested source and an agent-built executable must both exist.
    test -f router.cpp && test -s router.cpp || return 1
    test -f router && test -x router || return 1

    # Compile router.cpp itself so the behavioral tests exercise the submitted source.
    timeout 30s g++ -O3 -std=c++17 router.cpp -o /tmp/router_submission || return 1
    test -f /tmp/router_submission && test -x /tmp/router_submission || return 1

    python3 <<'PY'
import csv
import heapq
import os
import secrets
import subprocess

ROOT = "/home/user/backup_tool"
EDGES = os.path.join(ROOT, "edges.csv")
JOBS = os.path.join(ROOT, "jobs.csv")
TOP_JOBS = "/home/user/top_jobs.csv"
TOP_HUBS = "/home/user/top_hubs.csv"
BINARY = "/tmp/router_submission"

EXPECTED_ORIGINAL_JOBS = [
    "job_id,latency",
    "J1,35",
    "J2,35",
    "J3,25",
]
EXPECTED_ORIGINAL_HUBS = [
    "node_id,degree",
    "B,3",
    "C,3",
    "A,2",
]

def read_lines(path):
    assert os.path.isfile(path), f"File {path} does not exist. Did you run the compiled tool?"
    with open(path, "r", newline="") as f:
        return f.read().strip().splitlines()

def assert_reports(expected_jobs, expected_hubs):
    actual_jobs = read_lines(TOP_JOBS)
    actual_hubs = read_lines(TOP_HUBS)
    assert actual_jobs == expected_jobs, (
        f"Content of {TOP_JOBS} is incorrect. Expected {expected_jobs}, got {actual_jobs}."
    )
    assert actual_hubs == expected_hubs, (
        f"Content of {TOP_HUBS} is incorrect. Expected {expected_hubs}, got {actual_hubs}."
    )

def run_tool():
    for path in (TOP_JOBS, TOP_HUBS):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    subprocess.run([BINARY], cwd=ROOT, check=True, timeout=10)

def derive_expected(nodes, edges, jobs):
    graph = {node: [] for node in nodes}
    neighbors = {node: set() for node in nodes}
    for source, target, weight in edges:
        graph[source].append((target, weight))
        graph[target].append((source, weight))
        neighbors[source].add(target)
        neighbors[target].add(source)

    results = []
    for job_id, source, target in jobs:
        dist = {node: float("inf") for node in nodes}
        dist[source] = 0
        queue = [(0, source)]
        while queue:
            current, node = heapq.heappop(queue)
            if current != dist[node]:
                continue
            if node == target:
                break
            for nxt, weight in graph[node]:
                candidate = current + weight
                if candidate < dist[nxt]:
                    dist[nxt] = candidate
                    heapq.heappush(queue, (candidate, nxt))
        results.append((job_id, int(dist[target])))

    results.sort(key=lambda item: (-item[1], item[0]))
    hubs = [(node, len(neighbors[node])) for node in nodes]
    hubs.sort(key=lambda item: (-item[1], item[0]))

    expected_jobs = ["job_id,latency"] + [f"{job},{latency}" for job, latency in results[:3]]
    expected_hubs = ["node_id,degree"] + [f"{node},{degree}" for node, degree in hubs[:3]]
    return expected_jobs, expected_hubs

def write_probe(nodes, edges, jobs):
    with open(EDGES, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["source_node", "target_node", "latency"])
        writer.writerows(edges)
    with open(JOBS, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["job_id", "source_node", "target_node"])
        writer.writerows(jobs)

with open(EDGES, "rb") as f:
    original_edges = f.read()
with open(JOBS, "rb") as f:
    original_jobs = f.read()

try:
    # Preserve the original verifier's report assertions, with the corrected J3 result.
    assert_reports(EXPECTED_ORIGINAL_JOBS, EXPECTED_ORIGINAL_HUBS)

    # Exercise the submitted implementation on an unpredictable connected graph.
    token = secrets.token_hex(4)
    nodes = [f"N{token}_{i}" for i in range(7)]
    edges = []
    used = set()
    for i in range(len(nodes) - 1):
        weight = 2 + secrets.randbelow(40)
        edges.append((nodes[i], nodes[i + 1], weight))
        used.add((i, i + 1))

    candidates = [(i, j) for i in range(len(nodes)) for j in range(i + 1, len(nodes)) if (i, j) not in used]
    for _ in range(6):
        index = secrets.randbelow(len(candidates))
        i, j = candidates.pop(index)
        edges.append((nodes[i], nodes[j], 2 + secrets.randbelow(40)))

    pairs = [(i, j) for i in range(len(nodes)) for j in range(len(nodes)) if i != j]
    jobs = []
    for i in range(12):
        index = secrets.randbelow(len(pairs))
        source, target = pairs.pop(index)
        jobs.append((f"Q{token}_{i:02d}", nodes[source], nodes[target]))

    expected_jobs, expected_hubs = derive_expected(nodes, edges, jobs)
    write_probe(nodes, edges, jobs)
    run_tool()
    assert_reports(expected_jobs, expected_hubs)

    # Restore the task inputs, execute the submitted source on them, and retain the
    # originally required reports as the final state.
    with open(EDGES, "wb") as f:
        f.write(original_edges)
    with open(JOBS, "wb") as f:
        f.write(original_jobs)
    run_tool()
    assert_reports(EXPECTED_ORIGINAL_JOBS, EXPECTED_ORIGINAL_HUBS)
finally:
    with open(EDGES, "wb") as f:
        f.write(original_edges)
    with open(JOBS, "wb") as f:
        f.write(original_jobs)
PY
}

if run_verification; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

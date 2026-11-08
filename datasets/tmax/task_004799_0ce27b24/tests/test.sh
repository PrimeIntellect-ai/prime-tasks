#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
import time
import tempfile
from collections import defaultdict, deque

AGENT_BINARY = "/home/user/fast_resolver"
LEGACY_BINARY = "/app/legacy_resolver"
RNG = random.SystemRandom()


def generate_dense_dag(filepath, num_nodes=22):
    """Generate a densely connected DAG to force exponential time on naive algorithms."""
    with open(filepath, 'w') as f:
        for i in range(num_nodes):
            for j in range(i + 1, num_nodes):
                f.write(f"node{i} node{j}\n")


def fresh_names(count):
    prefix = secrets.token_hex(5)
    names = [f"N{prefix}{i}X{secrets.token_hex(2)}" for i in range(count)]
    RNG.shuffle(names)
    return names


def write_edges(path, edges):
    edges = list(edges)
    RNG.shuffle(edges)
    with open(path, "w") as f:
        for u, v in edges:
            f.write(f"{u} {v}\n")


def graph_answer(edges):
    """Independently compute longest-path length, or None if the graph is cyclic."""
    nodes = set()
    adj = defaultdict(list)
    indegree = defaultdict(int)
    for u, v in edges:
        nodes.add(u)
        nodes.add(v)
        adj[u].append(v)
        indegree[v] += 1
        indegree[u] += 0

    queue = deque(u for u in nodes if indegree[u] == 0)
    distance = {u: 0 for u in nodes}
    visited = 0
    best = 0
    while queue:
        u = queue.popleft()
        visited += 1
        best = max(best, distance[u])
        for v in adj[u]:
            distance[v] = max(distance[v], distance[u] + 1)
            indegree[v] -= 1
            if indegree[v] == 0:
                queue.append(v)

    return best if visited == len(nodes) else None


def run_agent(path, timeout=8):
    return subprocess.run(
        [AGENT_BINARY, path], capture_output=True, text=True, timeout=timeout
    )


def test_binary_exists_and_executable():
    assert os.path.isfile(AGENT_BINARY), f"Expected binary not found at {AGENT_BINARY}"
    assert os.access(AGENT_BINARY, os.X_OK), f"Binary at {AGENT_BINARY} is not executable"
    with open(AGENT_BINARY, "rb") as agent, open(LEGACY_BINARY, "rb") as legacy:
        assert agent.read() != legacy.read(), "Replacement must not be a copy of the legacy binary"


def test_binary_is_statically_linked():
    result = subprocess.run(["file", AGENT_BINARY], capture_output=True, text=True)
    assert "statically linked" in result.stdout.lower(), f"Binary is not statically linked: {result.stdout}"


def test_performance_and_correctness():
    with tempfile.TemporaryDirectory() as tmpdir:
        eval_file = os.path.join(tmpdir, "eval_deps.txt")
        generate_dense_dag(eval_file, num_nodes=22)

        start_legacy = time.time()
        legacy_proc = subprocess.run([LEGACY_BINARY, eval_file], capture_output=True, text=True)
        time_legacy = time.time() - start_legacy

        assert legacy_proc.returncode == 0, "Legacy binary failed on evaluation graph"
        legacy_output = legacy_proc.stdout.strip()

        start_agent = time.time()
        agent_proc = subprocess.run([AGENT_BINARY, eval_file], capture_output=True, text=True)
        time_agent = time.time() - start_agent

        assert agent_proc.returncode == 0, "Agent binary failed (non-zero exit code) on evaluation graph"
        agent_output = agent_proc.stdout.strip()

        assert agent_output == legacy_output, f"Output mismatch. Legacy: {legacy_output}, Agent: {agent_output}"

        speedup = time_legacy / max(time_agent, 1e-6)
        assert speedup >= 10.0, f"Speedup threshold not met. Speedup: {speedup:.2f}x (Legacy: {time_legacy:.4f}s, Agent: {time_agent:.4f}s)"


def test_cycle_detection():
    with tempfile.TemporaryDirectory() as tmpdir:
        cycle_file = os.path.join(tmpdir, "cycle_deps.txt")
        with open(cycle_file, 'w') as f:
            f.write("A B\n")
            f.write("B C\n")
            f.write("C A\n")

        agent_proc = subprocess.run([AGENT_BINARY, cycle_file], capture_output=True, text=True)

        assert agent_proc.returncode == 1, "Agent binary must exit with status code 1 on cycle"
        assert agent_proc.stdout.strip() == "CYCLE", "Agent binary must print exactly 'CYCLE' to stdout on cycle"


def test_varied_random_dags():
    with tempfile.TemporaryDirectory() as tmpdir:
        # Random names, shuffled edge order, sparse/dense graphs, disconnected
        # components, and different longest-path lengths prevent fixed answers.
        for case in range(16):
            n = RNG.randint(7, 48)
            names = fresh_names(n)
            edges = set()

            probability = RNG.uniform(0.025, 0.28)
            for i in range(n):
                for j in range(i + 1, n):
                    if RNG.random() < probability:
                        edges.add((names[i], names[j]))

            chain_nodes = RNG.sample(range(n), RNG.randint(2, min(n, 12)))
            chain_nodes.sort()
            for i in range(len(chain_nodes) - 1):
                edges.add((names[chain_nodes[i]], names[chain_nodes[i + 1]]))

            expected = graph_answer(edges)
            assert expected is not None
            path = os.path.join(tmpdir, f"dag_{case}.txt")
            write_edges(path, edges)
            proc = run_agent(path)
            assert proc.returncode == 0, f"DAG case {case} returned {proc.returncode}: {proc.stderr}"
            assert proc.stdout.strip() == str(expected), (
                f"Wrong longest path for DAG case {case}: expected {expected}, got {proc.stdout!r}"
            )


def test_varied_embedded_cycles():
    with tempfile.TemporaryDirectory() as tmpdir:
        cycle_lengths = [1, 2, 4, 6, 9, RNG.randint(3, 10)]
        for case, cycle_len in enumerate(cycle_lengths):
            n = cycle_len + RNG.randint(5, 25)
            names = fresh_names(n)
            edges = set()

            # Add an ordinary acyclic region around the cycle.
            for i in range(n):
                for j in range(i + 1, n):
                    if RNG.random() < 0.08:
                        edges.add((names[i], names[j]))

            members = RNG.sample(names, cycle_len)
            if cycle_len == 1:
                edges.add((members[0], members[0]))
            else:
                for i in range(cycle_len):
                    edges.add((members[i], members[(i + 1) % cycle_len]))

            assert graph_answer(edges) is None
            path = os.path.join(tmpdir, f"cycle_{case}.txt")
            write_edges(path, edges)
            proc = run_agent(path)
            assert proc.returncode == 1, f"Cycle case {case} must exit 1, got {proc.returncode}"
            assert proc.stdout.strip() == "CYCLE", (
                f"Cycle case {case} must print exactly CYCLE, got {proc.stdout!r}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

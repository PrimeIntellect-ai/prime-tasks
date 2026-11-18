#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import heapq
import json
import os
import random
import secrets
import subprocess
import tempfile
import time


def run_cmd(cmd):
    start = time.time()
    res = subprocess.run(cmd, capture_output=True, text=True)
    end = time.time()
    return res, end - start


def load_graph(csv_path):
    graph = {}
    max_node = -1
    with open(csv_path, "r") as f:
        for line in f:
            parts = line.rstrip("\n").split(",", 3)
            if len(parts) != 4:
                continue
            u = int(parts[0])
            v = int(parts[1])
            base = float(parts[2])
            penalty = float(json.loads(parts[3]).get("penalty", 1.0))
            graph.setdefault(u, []).append((v, base * penalty))
            max_node = max(max_node, u, v)
    return graph, max_node


def expected_outputs(graph, max_node, queries):
    outputs = []
    for src, dst in queries:
        if src < 0 or dst < 0 or src > max_node or dst > max_node:
            outputs.append("-1.00")
            continue

        dist = {src: 0.0}
        heap = [(0.0, src)]
        answer = None
        while heap:
            current, u = heapq.heappop(heap)
            if current != dist.get(u):
                continue
            if u == dst:
                answer = current
                break
            for v, weight in graph.get(u, ()):
                candidate = current + weight
                if candidate < dist.get(v, float("inf")):
                    dist[v] = candidate
                    heapq.heappush(heap, (candidate, v))

        outputs.append("-1.00" if answer is None else f"{answer:.2f}")
    return outputs


def write_queries(path, queries):
    with open(path, "w") as f:
        for u, v in queries:
            f.write(f"{u} {v}\n")


def test_fast_path_speedup():
    c_file = "/home/user/fast_path.c"
    binary_file = "/home/user/fast_path"

    assert os.path.isfile(c_file), f"Source file missing: {c_file}"

    # Compile the C file to ensure we are testing the latest version with optimizations
    compile_cmd = ["gcc", "-O3", c_file, "-o", binary_file, "-lm"]
    compile_res = subprocess.run(compile_cmd, capture_output=True, text=True)
    assert compile_res.returncode == 0, f"Compilation failed:\n{compile_res.stderr}"

    assert os.path.isfile(binary_file), f"Binary missing: {binary_file}"
    assert os.access(binary_file, os.X_OK), f"Binary is not executable: {binary_file}"

    edges_test = "/test/edges_test.csv"
    queries_test = "/test/queries_test.txt"
    oracle_bin = "/app/graph_oracle"

    assert os.path.isfile(edges_test), f"Test edges missing: {edges_test}"
    assert os.path.isfile(queries_test), f"Test queries missing: {queries_test}"
    assert os.path.isfile(oracle_bin), f"Oracle binary missing: {oracle_bin}"
    assert not filecmp.cmp(binary_file, oracle_bin, shallow=False), "Submission must not be the oracle binary."

    # Run oracle
    oracle_res, oracle_time = run_cmd([oracle_bin, edges_test, queries_test])
    assert oracle_res.returncode == 0, f"Oracle failed:\n{oracle_res.stderr}"
    oracle_out = oracle_res.stdout.strip()

    # Run agent
    agent_res, agent_time = run_cmd([binary_file, edges_test, queries_test])
    assert agent_res.returncode == 0, f"Agent binary failed:\n{agent_res.stderr}"
    agent_out = agent_res.stdout.strip()

    # Check correctness
    assert agent_out == oracle_out, "Agent output does not match the oracle output exactly."

    # Check speedup
    speedup = oracle_time / agent_time
    assert speedup >= 50.0, f"Speedup is {speedup:.2f}x, which is less than the required 50.0x threshold."

    # Exercise a graph generated only after the agent has finished. Expected
    # answers are independently derived with Dijkstra rather than copied from
    # an agent-accessible output file.
    rng = random.Random(int.from_bytes(os.urandom(16), "big"))
    graph_fd, graph_path = tempfile.mkstemp(prefix="heldout_edges_", suffix=".csv")
    query_fd, query_path = tempfile.mkstemp(prefix="heldout_queries_", suffix=".txt")
    os.close(graph_fd)
    os.close(query_fd)
    try:
        node_count = 96
        with open(graph_path, "w") as f:
            # Ensure every node occurs while retaining directed-path behavior.
            for u in range(node_count - 1):
                base = rng.randint(100, 1000) / 100.0
                penalty = rng.randint(50, 200) / 100.0
                props = json.dumps({"type": "friend", "penalty": penalty})
                f.write(f"{u},{u + 1},{base:.2f},{props}\n")
            for _ in range(650):
                u = rng.randrange(node_count)
                v = rng.randrange(node_count)
                base = rng.randint(100, 1000) / 100.0
                penalty = rng.randint(50, 200) / 100.0
                props = json.dumps({"type": "friend", "penalty": penalty})
                f.write(f"{u},{v},{base:.2f},{props}\n")

        heldout_queries = [(rng.randrange(node_count), rng.randrange(node_count)) for _ in range(80)]
        write_queries(query_path, heldout_queries)
        heldout_graph, heldout_max = load_graph(graph_path)
        heldout_expected = expected_outputs(heldout_graph, heldout_max, heldout_queries)

        heldout_res, _ = run_cmd([binary_file, graph_path, query_path])
        assert heldout_res.returncode == 0, f"Agent failed on generated graph:\n{heldout_res.stderr}"
        assert heldout_res.stdout.strip().splitlines() == heldout_expected, \
            "Agent output is incorrect on a verifier-generated graph."
    finally:
        os.unlink(graph_path)
        os.unlink(query_path)

    # Use unpredictable queries on the large graph for both correctness and
    # performance, preventing a fixed table of the shipped 500 answers from
    # satisfying the speed requirement.
    graph, max_node = load_graph(edges_test)
    dynamic_count = 300
    dynamic_queries = [
        (secrets.randbelow(max_node + 1), secrets.randbelow(max_node + 1))
        for _ in range(dynamic_count)
    ]
    dynamic_expected = expected_outputs(graph, max_node, dynamic_queries)

    fd, dynamic_query_path = tempfile.mkstemp(prefix="heldout_large_queries_", suffix=".txt")
    os.close(fd)
    try:
        write_queries(dynamic_query_path, dynamic_queries)
        dynamic_res, dynamic_time = run_cmd([binary_file, edges_test, dynamic_query_path])
        assert dynamic_res.returncode == 0, f"Agent failed on held-out queries:\n{dynamic_res.stderr}"
        assert dynamic_res.stdout.strip().splitlines() == dynamic_expected, \
            "Agent output is incorrect on verifier-generated large-graph queries."

        fixed_query_count = len(oracle_out.splitlines())
        comparable_oracle_time = oracle_time * dynamic_count / fixed_query_count
        dynamic_speedup = comparable_oracle_time / dynamic_time
        assert dynamic_speedup >= 50.0, \
            f"Held-out-query speedup is {dynamic_speedup:.2f}x, less than the required 50.0x."
    finally:
        os.unlink(dynamic_query_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

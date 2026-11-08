#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import runpy
import subprocess
import sys
import threading
from collections import deque
import pytest

LIB_PATH = "/app/graphetl-lib"
SCRIPT_PATH = "/home/user/analyze_graph.py"
OUTPUT_PATH = "/home/user/shortest_path.txt"
CSV_PATH = "/app/data/transactions.csv"


def run_analysis_with_instrumentation(timeout=15):
    """Execute the submitted script while counting calls to Graph.add_edge."""
    wrapper = r'''
import runpy
import sys
sys.path.insert(0, "/app/graphetl-lib")
from graphetl import Graph
calls = {"count": 0}
original_add_edge = Graph.add_edge

def counted_add_edge(self, u, v):
    calls["count"] += 1
    return original_add_edge(self, u, v)

Graph.add_edge = counted_add_edge
try:
    runpy.run_path("/home/user/analyze_graph.py", run_name="__main__")
finally:
    print("__GRAPH_ADD_EDGE_CALLS__=" + str(calls["count"]))
'''
    try:
        result = subprocess.run(
            ["python3", "-c", wrapper],
            cwd="/home/user",
            capture_output=True,
            text=True,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("analyze_graph.py timed out")

    assert result.returncode == 0, (
        f"analyze_graph.py failed.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    match = re.search(r"__GRAPH_ADD_EDGE_CALLS__=(\d+)", result.stdout)
    assert match is not None, "Could not determine whether analyze_graph.py used Graph.add_edge"
    return int(match.group(1))


def parse_output_path():
    assert os.path.isfile(OUTPUT_PATH), f"Student output file missing at {OUTPUT_PATH}"
    with open(OUTPUT_PATH, "r") as f:
        content = f.read().strip()
    assert content, "Shortest path file is empty."
    return [node.strip() for node in content.split(",")]


def test_throughput_metric():
    """
    Run the verifier benchmark and ensure the throughput is >= 15000 edges/sec.
    """
    benchmark_script = "/app/verifier_benchmark.py"
    assert os.path.isfile(benchmark_script), f"Benchmark script missing at {benchmark_script}"

    try:
        result = subprocess.run(
            ["python3", benchmark_script],
            capture_output=True,
            text=True,
            timeout=30
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Benchmark script timed out. Deadlock might still be present.")

    assert result.returncode == 0, f"Benchmark script failed with error:\n{result.stderr}"

    # Extract throughput from stdout. The benchmark prints it.
    # We look for a number in the output.
    match = re.search(r"([\d\.]+)", result.stdout)
    assert match is not None, f"Could not parse throughput from benchmark output:\n{result.stdout}"

    throughput = float(match.group(1))
    threshold = 15000.0

    assert throughput >= threshold, (
        f"Throughput {throughput:.2f} edges/sec is below the required threshold of {threshold} edges/sec. "
        "Ensure you are using fine-grained locks and not a single global lock."
    )


def test_concurrent_insertions_actually_mutate_graph():
    """Ensure concurrent add_edge calls insert every requested undirected edge."""
    sys.path.insert(0, LIB_PATH)
    from graphetl import Graph

    graph = Graph()
    thread_edges = []
    expected = set()
    for thread_id in range(8):
        edges = []
        for i in range(1200):
            u = f"N_{i % 40}"
            v = f"N_{(i * 7 + thread_id * 3 + 1) % 40}"
            if u != v:
                # Alternate orientation to exercise overlapping lock acquisition.
                edge = (u, v) if (i + thread_id) % 2 == 0 else (v, u)
                edges.append(edge)
                expected.add(frozenset(edge))
        thread_edges.append(edges)

    errors = []

    def worker(edges):
        try:
            for u, v in edges:
                graph.add_edge(u, v)
        except BaseException as exc:
            errors.append(exc)

    threads = [threading.Thread(target=worker, args=(edges,), daemon=True)
               for edges in thread_edges]
    for thread in threads:
        thread.start()
    for thread in threads:
        thread.join(timeout=10)

    assert not any(thread.is_alive() for thread in threads), "Concurrent add_edge calls deadlocked"
    assert not errors, f"Concurrent add_edge raised an exception: {errors[0]!r}"

    for edge in expected:
        u, v = tuple(edge)
        assert v in graph.adj.get(u, set()), f"Missing inserted edge {u} -> {v}"
        assert u in graph.adj.get(v, set()), f"Missing reverse edge {v} -> {u}"


def test_analysis_script_exists_executes_and_uses_fixed_graph():
    assert os.path.isfile(SCRIPT_PATH), f"Analysis script missing at {SCRIPT_PATH}"
    with open(SCRIPT_PATH, "rb") as f:
        source = f.read()
    assert source, "Analysis script is empty"
    try:
        compile(source, SCRIPT_PATH, "exec")
    except SyntaxError as exc:
        pytest.fail(f"Analysis script is not valid Python: {exc}")

    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    calls = run_analysis_with_instrumentation()

    with open(CSV_PATH, "r") as f:
        edge_count = sum(
            1 for line in f
            if line.strip() and not line.strip().startswith("source")
        )
    assert calls >= edge_count, (
        "analyze_graph.py did not load the transaction edges through the fixed Graph.add_edge API"
    )
    assert os.path.isfile(OUTPUT_PATH), "analyze_graph.py did not create shortest_path.txt"


def test_shortest_path_result():
    """
    Verify the shortest path written by the student in /home/user/shortest_path.txt.
    """
    csv_path = "/app/data/transactions.csv"
    assert os.path.isfile(csv_path), f"Data file missing at {csv_path}"

    # Recompute the shortest path to avoid hardcoding
    adj = {}
    with open(csv_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line or line.startswith('source'):
                continue
            parts = line.split(',')
            if len(parts) >= 2:
                u, v = parts[0].strip(), parts[1].strip()
                adj.setdefault(u, set()).add(v)
                adj.setdefault(v, set()).add(u)

    start_node = 'CUST_739'
    end_node = 'CUST_882'

    # BFS to find the shortest path length
    queue = deque([[start_node]])
    visited = {start_node}
    expected_length = None

    while queue:
        path = queue.popleft()
        node = path[-1]
        if node == end_node:
            expected_length = len(path)
            break
        for neighbor in sorted(adj.get(node, [])):
            if neighbor not in visited:
                visited.add(neighbor)
                queue.append(path + [neighbor])

    assert expected_length is not None, f"No path found between {start_node} and {end_node} in the dataset."

    student_file = "/home/user/shortest_path.txt"
    assert os.path.isfile(student_file), f"Student output file missing at {student_file}"

    with open(student_file, 'r') as f:
        student_content = f.read().strip()

    assert student_content, "Shortest path file is empty."

    student_path = [node.strip() for node in student_content.split(',')]

    assert student_path[0] == start_node, f"Path must start with {start_node}, got {student_path[0]}"
    assert student_path[-1] == end_node, f"Path must end with {end_node}, got {student_path[-1]}"
    assert len(student_path) == expected_length, (
        f"Expected shortest path length of {expected_length} nodes, "
        f"but got {len(student_path)} nodes."
    )

    # Verify that the path is valid in the graph
    for i in range(len(student_path) - 1):
        u = student_path[i]
        v = student_path[i+1]
        assert v in adj.get(u, set()), f"Invalid edge in path: {u} -> {v} does not exist in the graph."


def test_analysis_recomputes_for_changed_transactions():
    """Reject a script that merely writes the known path for the original CSV."""
    import secrets

    with open(CSV_PATH, "rb") as f:
        original_csv = f.read()
    original_output = None
    if os.path.exists(OUTPUT_PATH):
        with open(OUTPUT_PATH, "rb") as f:
            original_output = f.read()

    token = secrets.token_hex(6)
    a = f"ALT_A_{token}"
    b = f"ALT_B_{token}"
    d = f"ALT_D_{token}"
    e = f"ALT_E_{token}"
    fnode = f"ALT_F_{token}"
    alternate_csv = (
        "source,target\n"
        f"CUST_739,{a}\n"
        f"{a},{b}\n"
        f"{b},CUST_882\n"
        f"CUST_739,{d}\n"
        f"{d},{e}\n"
        f"{e},{fnode}\n"
        f"{fnode},CUST_882\n"
    )

    try:
        with open(CSV_PATH, "w") as f:
            f.write(alternate_csv)
        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)

        calls = run_analysis_with_instrumentation()
        assert calls >= 7, "Analysis did not load all alternate transaction edges through Graph.add_edge"
        student_path = parse_output_path()
        expected_path = ["CUST_739", a, b, "CUST_882"]
        assert student_path == expected_path, (
            "analyze_graph.py did not recompute the shortest path from the transaction CSV"
        )
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
        if original_output is None:
            if os.path.exists(OUTPUT_PATH):
                os.remove(OUTPUT_PATH)
        else:
            with open(OUTPUT_PATH, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

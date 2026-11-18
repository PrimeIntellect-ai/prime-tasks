#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import os
import re
import secrets
import subprocess
from pathlib import Path

BASE = Path("/home/user/graph_db")
EDGES = BASE / "edges.csv"
SOURCE = BASE / "fast_query.cpp"
BINARY = BASE / "fast_query"
RESULT = BASE / "result.log"


def parse_graph(data):
    graph = {}
    for raw_line in data.splitlines():
        line = raw_line.strip()
        if not line:
            continue
        parts = line.split(",")
        if len(parts) == 3:
            u, v, w = map(int, parts)
            graph.setdefault(u, {})
            if v not in graph[u] or w < graph[u][v]:
                graph[u][v] = w
    return graph


def shortest_cost(graph):
    dist = {10: 0}
    pq = [(0, 10)]
    while pq:
        d, u = heapq.heappop(pq)
        if d > dist[u]:
            continue
        if u == 500:
            return d
        for v, w in graph.get(u, {}).items():
            nd = d + w
            if nd < dist.get(v, float("inf")):
                dist[v] = nd
                heapq.heappush(pq, (nd, v))
    return float("inf")


def validate_output(output, edge_data):
    match = re.fullmatch(
        r"Cost:\s*(\d+)\s*\nPath:\s*(\d+(?:\s*->\s*\d+)*)\s*",
        output,
    )
    assert match, "Program output must contain exactly a Cost line and a Path line."

    reported_cost = int(match.group(1))
    path_nodes = [int(x.strip()) for x in match.group(2).split("->")]
    graph = parse_graph(edge_data)
    expected_cost = shortest_cost(graph)

    assert expected_cost != float("inf"), "Generated test graph has no path from 10 to 500."
    assert reported_cost == expected_cost, f"Reported cost {reported_cost}, expected {expected_cost}."
    assert len(path_nodes) >= 2, "Path must contain at least two nodes."
    assert path_nodes[0] == 10, "Path must start at node 10."
    assert path_nodes[-1] == 500, "Path must end at node 500."

    actual_cost = 0
    for u, v in zip(path_nodes, path_nodes[1:]):
        assert u in graph and v in graph[u], f"Invalid transition in path: {u} -> {v}."
        actual_cost += graph[u][v]
    assert actual_cost == expected_cost, "Reported path is not a shortest path."


def run_program(executable):
    completed = subprocess.run(
        [str(executable)],
        cwd=str(BASE),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=5,
        check=False,
    )
    assert completed.returncode == 0, (
        f"{executable} exited with status {completed.returncode}: {completed.stderr}"
    )
    return completed.stdout


def test_files_exist():
    """Verify that the required files have been created."""
    assert os.path.isfile("/home/user/graph_db/fast_query.cpp"), "/home/user/graph_db/fast_query.cpp is missing. Did you write the C++ program?"
    assert os.path.isfile("/home/user/graph_db/fast_query"), "/home/user/graph_db/fast_query is missing. Did you compile the C++ program?"
    assert os.path.isfile("/home/user/graph_db/result.log"), "/home/user/graph_db/result.log is missing. Did you run the program and redirect output?"
    assert os.access(BINARY, os.X_OK), "fast_query is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "fast_query must be a compiled native executable."


def test_result_log_correctness():
    """Verify that the result.log contains the correct minimum cost and a valid path."""
    edges_file = "/home/user/graph_db/edges.csv"
    assert os.path.isfile(edges_file), "edges.csv is missing. The data file must not be deleted."

    graph = {}
    with open(edges_file, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(",")
            if len(parts) == 3:
                u, v, w = int(parts[0]), int(parts[1]), int(parts[2])
                if u not in graph:
                    graph[u] = {}
                if v not in graph[u] or w < graph[u][v]:
                    graph[u][v] = w

    dist = {10: 0}
    pq = [(0, 10)]
    while pq:
        d, u = heapq.heappop(pq)
        if d > dist[u]:
            continue
        if u == 500:
            break
        for v, w in graph.get(u, {}).items():
            if dist.get(v, float('inf')) > d + w:
                dist[v] = d + w
                heapq.heappush(pq, (dist[v], v))

    expected_cost = dist.get(500, float('inf'))
    assert expected_cost != float('inf'), "No path found in edges.csv from 10 to 500."

    with open("/home/user/graph_db/result.log", "r") as f:
        content = f.read()

    cost_match = re.search(r"Cost:\s*(\d+)", content)
    assert cost_match, "Could not find a valid 'Cost: [TOTAL_COST]' line in result.log."
    reported_cost = int(cost_match.group(1))

    path_match = re.search(r"Path:\s*([\d\s->]+)", content)
    assert path_match, "Could not find a valid 'Path: 10 -> ... -> 500' line in result.log."

    path_str = path_match.group(1).strip()
    path_nodes = [int(x.strip()) for x in path_str.split("->") if x.strip().isdigit()]

    assert reported_cost == expected_cost, f"Reported cost {reported_cost} does not match the actual minimum cost {expected_cost}."
    assert len(path_nodes) >= 2, "Path must contain at least two nodes."
    assert path_nodes[0] == 10, f"Path starts at {path_nodes[0]}, expected 10."
    assert path_nodes[-1] == 500, f"Path ends at {path_nodes[-1]}, expected 500."

    actual_path_cost = 0
    for i in range(len(path_nodes) - 1):
        u, v = path_nodes[i], path_nodes[i+1]
        assert u in graph and v in graph[u], f"Invalid transition in path: Edge {u} -> {v} does not exist in edges.csv."
        actual_path_cost += graph[u][v]

    assert actual_path_cost == expected_cost, f"The sum of edge costs in the reported path ({actual_path_cost}) does not match the expected minimum cost ({expected_cost}). The path is not optimal."


def test_program_executes_and_reads_csv_dynamically(tmp_path):
    original_edges = EDGES.read_bytes()
    original_result = RESULT.read_text()
    rebuilt = tmp_path / "fast_query_rebuilt"

    compile_result = subprocess.run(
        ["g++", "-O2", str(SOURCE), "-o", str(rebuilt)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
        check=False,
    )
    assert compile_result.returncode == 0, f"fast_query.cpp does not compile with g++: {compile_result.stderr}"

    try:
        original_text = original_edges.decode()
        submitted_output = run_program(BINARY)
        assert submitted_output == original_result, "Running fast_query on the original edges.csv does not reproduce result.log exactly."
        validate_output(submitted_output, original_text)

        test_graphs = [
            "10,20,7\n20,500,9\n10,500,40\n10,30,3\n30,40,4\n40,500,25\n",
            "10,111,12\n111,222,13\n222,500,14\n10,333,2\n333,444,3\n444,500,80\n10,500,100\n",
        ]

        rng = secrets.SystemRandom()
        random_edges = [(10, 250, 17), (250, 500, 19), (10, 500, 90)]
        for _ in range(1200):
            u = rng.randint(1, 499)
            v = rng.randint(1, 500)
            if u != v:
                random_edges.append((u, v, rng.randint(1, 60)))
        test_graphs.append("".join(f"{u},{v},{w}\n" for u, v, w in random_edges))

        for edge_data in test_graphs:
            for executable in (BINARY, rebuilt):
                EDGES.write_text(edge_data)
                output = run_program(executable)
                validate_output(output, edge_data)
    finally:
        EDGES.write_bytes(original_edges)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

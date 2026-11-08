#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import heapq
import json
import os
import secrets
import subprocess

import pytest

SOURCE = "/home/user/analyze.go"
BINARY = "/tmp/analyze_submission"
NODES = "/home/user/nodes.csv"
EDGES = "/home/user/edges.csv"
QUERIES = "/home/user/queries.csv"
VALIDATION = "/home/user/validation_errors.log"
SUMMARY = "/home/user/summary.json"


def run_program():
    for path in (VALIDATION, SUMMARY):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    result = subprocess.run(
        [BINARY],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Compiled analyze.go exited with status {result.returncode}. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )


def test_analyze_go_exists():
    file_path = "/home/user/analyze.go"
    assert os.path.isfile(file_path), f"Expected Go program {file_path} does not exist."


def test_analyze_go_compiles_and_runs():
    result = subprocess.run(
        ["go", "build", "-o", BINARY, SOURCE],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=40,
    )
    assert result.returncode == 0, (
        f"analyze.go did not compile. stdout: {result.stdout!r}; "
        f"stderr: {result.stderr!r}"
    )
    run_program()


def test_validation_errors_log():
    file_path = "/home/user/validation_errors.log"
    assert os.path.isfile(file_path), f"Expected file {file_path} was not generated."

    with open(file_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_errors = ["W", "X", "Y", "Z"]
    assert lines == expected_errors, f"Content of {file_path} does not match the expected missing nodes. Got: {lines}"


def test_summary_json():
    file_path = "/home/user/summary.json"
    assert os.path.isfile(file_path), f"Expected file {file_path} was not generated."

    with open(file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{file_path} is not valid JSON.")

    expected_data = {
        "total_queries": 5,
        "successful_paths": 4,
        "total_cost": 110,
        "average_cost": 27.5
    }

    assert "total_queries" in data, "Missing 'total_queries' in summary.json"
    assert data["total_queries"] == expected_data["total_queries"], f"Expected total_queries to be {expected_data['total_queries']}, got {data['total_queries']}"

    assert "successful_paths" in data, "Missing 'successful_paths' in summary.json"
    assert data["successful_paths"] == expected_data["successful_paths"], f"Expected successful_paths to be {expected_data['successful_paths']}, got {data['successful_paths']}"

    assert "total_cost" in data, "Missing 'total_cost' in summary.json"
    assert data["total_cost"] == expected_data["total_cost"], f"Expected total_cost to be {expected_data['total_cost']}, got {data['total_cost']}"

    assert "average_cost" in data, "Missing 'average_cost' in summary.json"
    assert data["average_cost"] == expected_data["average_cost"], f"Expected average_cost to be {expected_data['average_cost']}, got {data['average_cost']}"


def expected_results(nodes, edges, queries):
    node_ids = {node_id for node_id, _ in nodes}
    missing = sorted({
        endpoint
        for src, dst, _, _ in edges
        for endpoint in (src, dst)
        if endpoint not in node_ids
    })

    graph = {node_id: [] for node_id in node_ids}
    for src, dst, cost, rel in edges:
        if rel in {"CONNECTED_TO", "DEPENDS_ON"} and src in node_ids and dst in node_ids:
            graph[src].append((dst, float(cost)))

    costs = []
    for start, end in queries:
        if start not in node_ids or end not in node_ids:
            continue
        distances = {start: 0.0}
        queue = [(0.0, start)]
        found = None
        while queue:
            distance, current = heapq.heappop(queue)
            if distance != distances.get(current):
                continue
            if current == end:
                found = distance
                break
            for neighbor, edge_cost in graph[current]:
                candidate = distance + edge_cost
                if candidate < distances.get(neighbor, float("inf")):
                    distances[neighbor] = candidate
                    heapq.heappush(queue, (candidate, neighbor))
        if found is not None:
            costs.append(found)

    total_cost = sum(costs)
    successful = len(costs)
    return missing, {
        "total_queries": len(queries),
        "successful_paths": successful,
        "total_cost": total_cost,
        "average_cost": total_cost / successful if successful else 0.0,
    }


def write_case(nodes, edges, queries):
    with open(NODES, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["node_id", "node_type"])
        writer.writerows(nodes)
    with open(EDGES, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["src", "dst", "cost", "rel"])
        writer.writerows(edges)
    with open(QUERIES, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["start", "end"])
        writer.writerows(queries)


def test_program_on_runtime_generated_inputs():
    original_inputs = {path: open(path, "rb").read() for path in (NODES, EDGES, QUERIES)}
    rng = secrets.SystemRandom()

    try:
        for _ in range(3):
            tag = secrets.token_hex(6)
            ids = [f"N{tag}_{i}" for i in range(6)]
            missing_ids = [f"M{tag}_{i}" for i in range(3)]
            nodes = [(node_id, "Location") for node_id in ids]

            a = rng.randint(3, 12)
            b = rng.randint(2, 9)
            c = rng.randint(1, 8)
            d = rng.randint(2, 10)
            e = rng.randint(4, 13)
            expensive = a + b + rng.randint(10, 30)
            ignored_shortcut = rng.randint(1, 2) / 10

            edges = [
                (ids[0], ids[1], a, "CONNECTED_TO"),
                (ids[0], ids[2], expensive, "CONNECTED_TO"),
                (ids[1], ids[2], b, "DEPENDS_ON"),
                (ids[1], ids[3], c, "DEPENDS_ON"),
                (ids[3], ids[4], d, "CONNECTED_TO"),
                (ids[0], ids[4], ignored_shortcut, "INCOMPATIBLE_WITH"),
                (ids[5], ids[0], e, "CONNECTED_TO"),
                (missing_ids[0], missing_ids[1], 7, "CONNECTED_TO"),
                (ids[2], missing_ids[2], 1, "INCOMPATIBLE_WITH"),
            ]
            queries = [
                (ids[0], ids[2]),
                (ids[0], ids[4]),
                (ids[1], ids[4]),
                (ids[5], ids[2]),
                (ids[0], ids[5]),
            ]

            expected_missing, expected_summary = expected_results(nodes, edges, queries)
            write_case(nodes, edges, queries)
            run_program()

            assert os.path.isfile(VALIDATION), f"Expected file {VALIDATION} was not generated."
            with open(VALIDATION, "r") as f:
                actual_missing = [line.strip() for line in f if line.strip()]
            assert actual_missing == expected_missing

            assert os.path.isfile(SUMMARY), f"Expected file {SUMMARY} was not generated."
            with open(SUMMARY, "r") as f:
                actual = json.load(f)
            assert actual["total_queries"] == expected_summary["total_queries"]
            assert actual["successful_paths"] == expected_summary["successful_paths"]
            assert actual["total_cost"] == pytest.approx(expected_summary["total_cost"])
            assert actual["average_cost"] == pytest.approx(expected_summary["average_cost"])
    finally:
        for path, contents in original_inputs.items():
            with open(path, "wb") as f:
                f.write(contents)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

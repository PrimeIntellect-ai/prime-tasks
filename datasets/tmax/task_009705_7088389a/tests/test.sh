#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import heapq
import os
import re
import sqlite3
import subprocess

import pytest

PROCESS = "/home/user/process_graph.sh"
VALIDATE = "/home/user/validate.sh"
NODES = "/home/user/nodes.csv"
EDGES = "/home/user/edges.csv"
DB = "/home/user/graph.db"
SUMMARY = "/home/user/summary.csv"


def run_script(path):
    return subprocess.run(["bash", path], capture_output=True, text=True, timeout=20)


def test_process_graph_script_exists():
    assert os.path.isfile(PROCESS), f"{PROCESS} does not exist."


def test_validate_script_exists():
    assert os.path.isfile(VALIDATE), f"{VALIDATE} does not exist."


def assert_database_matches(nodes, edges):
    assert os.path.isfile(DB), f"{DB} was not created."
    con = sqlite3.connect(DB)
    try:
        objects = dict(con.execute(
            "SELECT name, type FROM sqlite_master WHERE name IN ('nodes','edges','active_edges')"
        ).fetchall())
        assert objects.get("nodes") == "table", "nodes was not imported as a table"
        assert objects.get("edges") == "table", "edges was not imported as a table"
        assert objects.get("active_edges") in ("table", "view"), "active_edges is not a table or view"

        node_cols = [r[1] for r in con.execute("PRAGMA table_info(nodes)")]
        edge_cols = [r[1] for r in con.execute("PRAGMA table_info(edges)")]
        active_cols = [r[1] for r in con.execute("PRAGMA table_info(active_edges)")]
        assert all(c in node_cols for c in ("id", "name", "status"))
        assert all(c in edge_cols for c in ("source", "target", "cost", "capacity"))
        assert all(c in active_cols for c in ("source", "target", "cost", "capacity"))

        actual_nodes = [tuple(map(str, r)) for r in con.execute(
            "SELECT id,name,status FROM nodes ORDER BY rowid"
        )]
        actual_edges = [tuple(map(str, r)) for r in con.execute(
            "SELECT source,target,cost,capacity FROM edges ORDER BY rowid"
        )]
        expected_nodes = [(r["id"], r["name"], r["status"]) for r in nodes]
        expected_edges = [(r["source"], r["target"], r["cost"], r["capacity"]) for r in edges]
        assert actual_nodes == expected_nodes, "nodes.csv was not correctly imported"
        assert actual_edges == expected_edges, "edges.csv was not correctly imported"

        statuses = {r["id"]: r["status"] for r in nodes}
        expected_active = sorted(
            (r["source"], r["target"], r["cost"], r["capacity"])
            for r in edges
            if statuses.get(r["source"]) == "ACTIVE" and statuses.get(r["target"]) == "ACTIVE"
        )
        actual_active = sorted(tuple(map(str, r)) for r in con.execute(
            "SELECT source,target,cost,capacity FROM active_edges"
        ))
        assert actual_active == expected_active, "active_edges does not contain exactly the active-node projection"
    finally:
        con.close()


def derive_results(nodes, edges):
    statuses = {r["id"]: r["status"] for r in nodes}
    names = {r["name"]: r["id"] for r in nodes}
    active = [
        r for r in edges
        if statuses.get(r["source"]) == "ACTIVE" and statuses.get(r["target"]) == "ACTIVE"
    ]
    capacity = sum(int(r["capacity"]) for r in active)
    graph = {}
    for r in active:
        graph.setdefault(r["source"], []).append((r["target"], int(r["cost"])))

    start, goal = names["Alpha"], names["Foxtrot"]
    queue = [(0, start)]
    best = {start: 0}
    shortest = None
    while queue:
        cost, node = heapq.heappop(queue)
        if cost != best[node]:
            continue
        if node == goal:
            shortest = cost
            break
        for nxt, weight in graph.get(node, []):
            candidate = cost + weight
            if candidate < best.get(nxt, float("inf")):
                best[nxt] = candidate
                heapq.heappush(queue, (candidate, nxt))
    assert shortest is not None
    return capacity, shortest


def read_fixture():
    with open(NODES, newline="") as f:
        nodes = list(csv.DictReader(f))
    with open(EDGES, newline="") as f:
        edges = list(csv.DictReader(f))
    return nodes, edges


def assert_summary(capacity, shortest):
    assert os.path.isfile(SUMMARY), f"{SUMMARY} was not created."
    with open(SUMMARY) as f:
        content = f.read().strip()
    expected = f"metric_name,value\ntotal_active_capacity,{capacity}\nshortest_path_cost,{shortest}"
    assert content == expected, f"Content of {SUMMARY} is incorrect. Got:\n{content}\nExpected:\n{expected}"


def assert_validator_accepts_valid_summary():
    result = run_script(VALIDATE)
    assert result.returncode == 0, (
        f"validate.sh returned non-zero exit code: {result.returncode}. stderr: {result.stderr}"
    )
    assert result.stdout.strip() == "VALID", (
        f"validate.sh did not print 'VALID'. Got: {result.stdout.strip()}"
    )


def test_process_graph_execution_and_outputs():
    with open(PROCESS) as f:
        source = f.read()
    non_comment_source = "\n".join(
        line for line in source.splitlines() if not line.lstrip().startswith("#")
    )
    assert re.search(r"\bWITH\s+RECURSIVE\b", non_comment_source, re.IGNORECASE), (
        "process_graph.sh does not contain the required recursive CTE"
    )

    if os.path.exists(DB):
        os.remove(DB)
    if os.path.exists(SUMMARY):
        os.remove(SUMMARY)

    result = run_script(PROCESS)
    assert result.returncode == 0, f"process_graph.sh failed to execute. stderr: {result.stderr}"
    assert os.path.isfile(DB), f"{DB} was not created."
    assert os.path.isfile(SUMMARY), f"{SUMMARY} was not created."

    with open(SUMMARY) as f:
        content = f.read().strip()
    expected_content = "metric_name,value\ntotal_active_capacity,610\nshortest_path_cost,50"
    content_lines = [line.strip() for line in content.splitlines() if line.strip()]
    expected_lines = [line.strip() for line in expected_content.splitlines() if line.strip()]
    assert content_lines == expected_lines, (
        f"Content of {SUMMARY} is incorrect. Got:\n{content}\nExpected:\n{expected_content}"
    )

    nodes, edges = read_fixture()
    assert_database_matches(nodes, edges)
    assert_validator_accepts_valid_summary()


def test_validate_script_rejects_invalid_summaries():
    valid = "metric_name,value\ntotal_active_capacity,610\nshortest_path_cost,50\n"
    invalid_cases = [
        "wrong_header,value\ntotal_active_capacity,610\nshortest_path_cost,50\n",
        "metric_name,value\ntotal_active_capacity,610\n",
        "metric_name,value\ntotal_active_capacity,610\nshortest_path_cost,50\nextra,1\n",
        "metric_name,value\ntotal_active_capacity,0\nshortest_path_cost,50\n",
        "metric_name,value\ntotal_active_capacity,-1\nshortest_path_cost,50\n",
        "metric_name,value\ntotal_active_capacity,610\nshortest_path_cost,2.5\n",
        "metric_name,value\nwrong_metric,610\nshortest_path_cost,50\n",
    ]
    try:
        for bad in invalid_cases:
            with open(SUMMARY, "w") as f:
                f.write(bad)
            result = run_script(VALIDATE)
            assert result.returncode == 1, f"validate.sh accepted invalid summary:\n{bad}"
            assert result.stdout.strip() == "INVALID", (
                f"validate.sh must print INVALID for invalid summary. Got: {result.stdout.strip()}"
            )
    finally:
        with open(SUMMARY, "w") as f:
            f.write(valid)


def test_process_graph_uses_current_csv_data():
    with open(NODES, "rb") as f:
        original_nodes = f.read()
    with open(EDGES, "rb") as f:
        original_edges = f.read()

    changed_nodes = """id,name,status
10,Alpha,ACTIVE
11,Beta,ACTIVE
12,Gamma,ACTIVE
13,Storm,INACTIVE
14,Foxtrot,ACTIVE
"""
    changed_edges = """source,target,cost,capacity
10,11,7,31
11,14,9,37
10,12,2,41
12,14,20,43
10,13,1,100
13,14,1,100
10,14,50,47
11,12,1,53
"""
    try:
        with open(NODES, "w") as f:
            f.write(changed_nodes)
        with open(EDGES, "w") as f:
            f.write(changed_edges)
        for path in (DB, SUMMARY):
            if os.path.exists(path):
                os.remove(path)

        nodes, edges = read_fixture()
        expected_capacity, expected_shortest = derive_results(nodes, edges)
        result = run_script(PROCESS)
        assert result.returncode == 0, (
            f"process_graph.sh failed on changed CSV input. stderr: {result.stderr}"
        )
        assert_database_matches(nodes, edges)
        assert_summary(expected_capacity, expected_shortest)
        assert_validator_accepts_valid_summary()
    finally:
        with open(NODES, "wb") as f:
            f.write(original_nodes)
        with open(EDGES, "wb") as f:
            f.write(original_edges)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

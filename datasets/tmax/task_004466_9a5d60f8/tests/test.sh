#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import sqlite3
import stat
import subprocess
from decimal import Decimal

import pytest

SCRIPT_PATH = "/home/user/analyze_graph.sh"
DB_PATH = "/home/user/routing.db"
NODES_PATH = "/home/user/nodes.csv"
EDGES_PATH = "/home/user/edges.csv"


def run_script(start, hops):
    return subprocess.run(
        [SCRIPT_PATH, start, str(hops)],
        capture_output=True,
        text=True,
        cwd="/home/user",
        timeout=20,
    )


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."


def test_script_execution_and_output():
    result = run_script("Alpha", 3)
    assert result.returncode == 0, f"Script failed with error:\n{result.stderr}"

    output = result.stdout.strip().replace("\r\n", "\n")
    expected_output = (
        "destination_name,min_total_weight,rank\n"
        "Bravo,10,1\n"
        "Charlie,15,2\n"
        "Delta,20,3\n"
        "Echo,30,4"
    )
    assert output == expected_output, (
        f"Script output did not match expected.\nExpected:\n{expected_output}\nGot:\n{output}"
    )


def test_database_created():
    assert os.path.isfile(DB_PATH), f"Database {DB_PATH} was not created."
    result = subprocess.run(
        ["sqlite3", DB_PATH, "SELECT name FROM sqlite_master WHERE type='table';"],
        capture_output=True,
        text=True,
        timeout=10,
    )
    tables = result.stdout.strip().split("\n")
    assert "nodes" in tables, "Table 'nodes' not found in the database."
    assert "edges" in tables, "Table 'edges' not found in the database."


def write_fixture(nodes, edges):
    with open(NODES_PATH, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["node_id", "node_name"])
        writer.writerows(nodes)
    with open(EDGES_PATH, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["source_id", "target_id", "weight", "is_stale"])
        writer.writerows(edges)


def expected_routes(nodes, edges, start_name, max_hops):
    names = {int(node_id): name for node_id, name in nodes}
    starts = [node_id for node_id, name in names.items() if name == start_name]
    if not starts:
        return {}

    outgoing = {}
    for source, target, weight, stale in edges:
        if int(stale) == 0:
            outgoing.setdefault(int(source), []).append((int(target), Decimal(str(weight))))

    frontier = [(node_id, Decimal(0)) for node_id in starts]
    best = {}
    for _depth in range(1, int(max_hops) + 1):
        next_frontier = []
        for current, total in frontier:
            for target, weight in outgoing.get(current, []):
                new_total = total + weight
                next_frontier.append((target, new_total))
                if target not in best or new_total < best[target]:
                    best[target] = new_total
        frontier = next_frontier

    distinct_weights = sorted(set(best.values()))
    ranks = {weight: index + 1 for index, weight in enumerate(distinct_weights)}
    return {names[node_id]: (weight, ranks[weight]) for node_id, weight in best.items()}


def parse_output(output):
    rows = list(csv.reader(output.splitlines()))
    assert rows, "No CSV output was produced."
    assert rows[0] == ["destination_name", "min_total_weight", "rank"], (
        f"Incorrect CSV header: {rows[0]}"
    )
    parsed = {}
    for row in rows[1:]:
        assert len(row) == 3, f"Malformed CSV row: {row}"
        name, weight, rank = row
        assert name not in parsed, f"Duplicate destination row for {name}"
        parsed[name] = (Decimal(weight), int(rank))
    return parsed


def assert_database_import(nodes, edges):
    assert os.path.isfile(DB_PATH), "The routing database was not created."
    con = sqlite3.connect(DB_PATH)
    try:
        tables = {row[0] for row in con.execute(
            "SELECT name FROM sqlite_master WHERE type='table'"
        )}
        assert "nodes" in tables
        assert "edges" in tables

        node_columns = [row[1] for row in con.execute("PRAGMA table_info(nodes)")]
        edge_columns = [row[1] for row in con.execute("PRAGMA table_info(edges)")]
        assert node_columns == ["node_id", "node_name"]
        assert edge_columns == ["source_id", "target_id", "weight", "is_stale"]

        actual_nodes = {(int(row[0]), str(row[1])) for row in con.execute(
            "SELECT node_id, node_name FROM nodes"
        )}
        expected_nodes = {(int(row[0]), str(row[1])) for row in nodes}
        assert actual_nodes == expected_nodes, "nodes.csv was not imported exactly."

        actual_edges = {
            (int(row[0]), int(row[1]), Decimal(str(row[2])), int(row[3]))
            for row in con.execute(
                "SELECT source_id, target_id, weight, is_stale FROM edges"
            )
        }
        expected_edges = {
            (int(row[0]), int(row[1]), Decimal(str(row[2])), int(row[3]))
            for row in edges
        }
        assert actual_edges == expected_edges, "edges.csv was not imported exactly."
    finally:
        con.close()


def test_dynamic_graphs_stale_edges_cycles_parameters_and_idempotency():
    nodes = [
        (10, "O'Brien, Hub"),
        (11, "Able"),
        (12, "Baker"),
        (13, "Cedar"),
        (14, "Dover"),
        (15, "Isolated"),
    ]
    edges = [
        (10, 11, 7, 0),
        (10, 12, 2, 0),
        (12, 11, 1, 0),
        (11, 13, 4, 0),
        (12, 13, 5, 0),
        (10, 14, 1, 1),
        (12, 14, 2, 1),
        (11, 14, 9, 0),
        (13, 10, 3, 0),
    ]
    write_fixture(nodes, edges)

    result = run_script("O'Brien, Hub", 3)
    assert result.returncode == 0, result.stderr
    assert parse_output(result.stdout) == expected_routes(nodes, edges, "O'Brien, Hub", 3)
    assert_database_import(nodes, edges)

    # Pollute both imported tables, then require a second run to recreate/clean them.
    con = sqlite3.connect(DB_PATH)
    try:
        con.execute("INSERT INTO nodes VALUES (999, 'Bogus')")
        con.execute("INSERT INTO edges VALUES (999, 999, -1000, 0)")
        con.commit()
    finally:
        con.close()

    result = run_script("O'Brien, Hub", 3)
    assert result.returncode == 0, result.stderr
    assert parse_output(result.stdout) == expected_routes(nodes, edges, "O'Brien, Hub", 3)
    assert_database_import(nodes, edges)

    # A different start and hop limit must change the traversal result.
    result = run_script("Able", 1)
    assert result.returncode == 0, result.stderr
    assert parse_output(result.stdout) == expected_routes(nodes, edges, "Able", 1)

    # This fixture checks tied ranks, multiple paths, stale filtering, and a cycle
    # back to the start node.
    nodes2 = [(1, "Start"), (2, "X"), (3, "Y"), (4, "Z"), (5, "Trap")]
    edges2 = [
        (1, 2, 5, 0),
        (1, 3, 2, 0),
        (3, 2, 3, 0),
        (3, 4, 3, 0),
        (1, 5, 1, 1),
        (2, 1, 1, 0),
    ]
    write_fixture(nodes2, edges2)
    result = run_script("Start", 2)
    assert result.returncode == 0, result.stderr
    assert parse_output(result.stdout) == expected_routes(nodes2, edges2, "Start", 2)
    assert_database_import(nodes2, edges2)


def test_requires_exactly_two_arguments():
    for args in ([], ["Start"], ["Start", "2", "extra"]):
        result = subprocess.run(
            [SCRIPT_PATH] + args,
            capture_output=True,
            text=True,
            cwd="/home/user",
            timeout=10,
        )
        assert result.returncode != 0, f"Invocation with {len(args)} arguments should fail."


def test_uses_required_advanced_sql_constructs():
    with open(SCRIPT_PATH, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()
    assert re.search(r"\bWITH\s+RECURSIVE\b", source, re.IGNORECASE), (
        "The script does not contain the required recursive CTE."
    )
    assert re.search(r"\bOVER\s*\(", source, re.IGNORECASE), (
        "The script does not contain the required SQL window function."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

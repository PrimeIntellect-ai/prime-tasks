#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import os
import random
import re
import secrets
import sqlite3
import subprocess

import pytest

PROJECT = "/home/user/graph_analyzer"
NODES_CSV = "/home/user/data/nodes.csv"
EDGES_CSV = "/home/user/data/edges.csv"
DB_PATH = "/home/user/data/graph.db"
RESULT_PATH = "/home/user/data/top_department.txt"

with open(NODES_CSV, "rb") as f:
    ORIGINAL_NODES = f.read()
with open(EDGES_CSV, "rb") as f:
    ORIGINAL_EDGES = f.read()


def inspect_rust_project():
    manifest = os.path.join(PROJECT, "Cargo.toml")
    assert os.path.isfile(manifest), "Missing Rust project Cargo.toml."

    rust_files = glob.glob(os.path.join(PROJECT, "**", "*.rs"), recursive=True)
    assert rust_files, "The project contains no Rust source files."
    source = "\n".join(open(path, encoding="utf-8").read() for path in rust_files)
    assert re.search(r"\bfn\s+main\s*\(", source), "No Rust main function was found."
    assert re.search(r"(?i)INSERT\s+INTO", source), "Rust source does not insert CSV records."

    binding_api = re.search(
        r"params!\s*\[|named_params!\s*\[|params_from_iter\s*\(|\.execute\s*\(\s*[&]?[\[(]",
        source,
        re.DOTALL,
    )
    placeholder_values = re.search(
        r"(?is)VALUES\s*\([^)]*(?:\?|:\w+|@\w+|\$\w+)", source
    )
    dynamic_placeholders = "params_from_iter" in source
    assert binding_api and (placeholder_values or dynamic_placeholders), (
        "Rust source does not appear to use parameterized INSERT queries."
    )


def run_application(timeout=240):
    for path in (DB_PATH, RESULT_PATH):
        if os.path.exists(path):
            os.remove(path)
    completed = subprocess.run(
        ["cargo", "run", "--quiet", "--manifest-path", os.path.join(PROJECT, "Cargo.toml")],
        cwd=PROJECT,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=timeout,
    )
    assert completed.returncode == 0, "Rust application failed:\n" + completed.stdout


def write_fixture(nodes, edges):
    with open(NODES_CSV, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["id", "name", "department"])
        writer.writeheader()
        writer.writerows(nodes)
    with open(EDGES_CSV, "w", newline="", encoding="utf-8") as f:
        writer = csv.DictWriter(f, fieldnames=["source", "target", "relation_type"])
        writer.writeheader()
        writer.writerows(edges)


def expected_result(nodes, edges):
    counts = {str(node["id"]): 0 for node in nodes}
    for edge in edges:
        if edge["relation_type"] == "reports_to" and str(edge["target"]) in counts:
            counts[str(edge["target"])] += 1

    departments = {}
    for node in nodes:
        department = node["department"]
        total, number = departments.get(department, (0, 0))
        departments[department] = (total + counts[str(node["id"])], number + 1)

    averages = {name: total / number for name, (total, number) in departments.items()}
    best = max(averages, key=averages.get)
    return f"{best},{averages[best]:.2f}"


def assert_database_matches(nodes, edges):
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} is missing."
    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='nodes';")
        assert cursor.fetchone() is not None, "Table 'nodes' is missing in graph.db."
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='edges';")
        assert cursor.fetchone() is not None, "Table 'edges' is missing in graph.db."

        cursor.execute("PRAGMA table_info(nodes)")
        node_columns = {row[1] for row in cursor.fetchall()}
        assert {"id", "name", "department"}.issubset(node_columns)
        cursor.execute("PRAGMA table_info(edges)")
        edge_columns = {row[1] for row in cursor.fetchall()}
        assert {"source", "target", "relation_type"}.issubset(edge_columns)

        actual_nodes = {
            tuple("" if value is None else str(value) for value in row)
            for row in cursor.execute("SELECT id, name, department FROM nodes")
        }
        expected_nodes = {
            (str(row["id"]), str(row["name"]), str(row["department"])) for row in nodes
        }
        assert actual_nodes == expected_nodes, "The nodes table does not match nodes.csv."

        actual_edges = {
            tuple("" if value is None else str(value) for value in row)
            for row in cursor.execute("SELECT source, target, relation_type FROM edges")
        }
        expected_edges = {
            (str(row["source"]), str(row["target"]), str(row["relation_type"])) for row in edges
        }
        assert actual_edges == expected_edges, "The edges table does not match edges.csv."
    finally:
        conn.close()


def read_csvs():
    with open(NODES_CSV, newline="", encoding="utf-8") as f:
        nodes = list(csv.DictReader(f))
    with open(EDGES_CSV, newline="", encoding="utf-8") as f:
        edges = list(csv.DictReader(f))
    return nodes, edges


def build_fixture(winner_index):
    token = secrets.token_hex(5)
    departments = [f"Dept_{token}_{i}" for i in range(3)]
    base = random.SystemRandom().randint(10000, 900000)
    group_sizes = [3, 3, 2]
    nodes = []
    groups = []
    next_id = base
    for department, size in zip(departments, group_sizes):
        group = []
        for j in range(size):
            node_id = str(next_id)
            next_id += random.SystemRandom().randint(2, 9)
            group.append(node_id)
            name = f"Employee {token} {j}"
            if len(nodes) == 1:
                name = f"O'Reilly, \"{token}\""
            nodes.append({"id": node_id, "name": name, "department": department})
        groups.append(group)

    all_ids = [row["id"] for row in nodes]
    edges = []
    used = set()
    totals = [1, 1, 1]
    totals[winner_index] = 5
    cursor = 0
    for department_index, total in enumerate(totals):
        targets = groups[department_index]
        for n in range(total):
            target = targets[n % len(targets)]
            while True:
                source = all_ids[cursor % len(all_ids)]
                cursor += 1
                if source != target and (source, target) not in used:
                    break
            used.add((source, target))
            edges.append({"source": source, "target": target, "relation_type": "reports_to"})

    edges.append({
        "source": all_ids[-1],
        "target": all_ids[0],
        "relation_type": f"collaborates_with_{token}",
    })
    return nodes, edges


@pytest.fixture(scope="session", autouse=True)
def execute_original_artifact():
    inspect_rust_project()
    run_application()


def test_graph_db_exists_and_valid():
    """Check if graph.db exists and contains the required tables and data."""
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} is missing."
    try:
        conn = sqlite3.connect(DB_PATH)
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='nodes';")
        assert cursor.fetchone() is not None, "Table 'nodes' is missing in graph.db."
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='edges';")
        assert cursor.fetchone() is not None, "Table 'edges' is missing in graph.db."
        cursor.execute("SELECT COUNT(*) FROM nodes;")
        assert cursor.fetchone()[0] > 0, "Table 'nodes' is empty."
        cursor.execute("SELECT COUNT(*) FROM edges;")
        assert cursor.fetchone()[0] > 0, "Table 'edges' is empty."
    except sqlite3.Error as e:
        pytest.fail(f"Failed to read SQLite database {DB_PATH}: {e}")
    finally:
        if 'conn' in locals():
            conn.close()

    nodes, edges = read_csvs()
    assert_database_matches(nodes, edges)


def test_top_department_result():
    """Check if top_department.txt exists and contains the correct result."""
    assert os.path.isfile(RESULT_PATH), f"Result file {RESULT_PATH} is missing."
    with open(RESULT_PATH, "r", encoding="utf-8") as f:
        content = f.read().strip()
    expected_content = "Engineering,0.75"
    assert content == expected_content, (
        f"Expected '{expected_content}', but found '{content}' in {RESULT_PATH}."
    )


def test_application_processes_unseen_csv_data():
    try:
        for winner_index in (0, 2):
            nodes, edges = build_fixture(winner_index)
            write_fixture(nodes, edges)
            run_application()
            assert_database_matches(nodes, edges)
            assert os.path.isfile(RESULT_PATH), "Rust application did not create top_department.txt."
            with open(RESULT_PATH, encoding="utf-8") as f:
                actual = f.read().strip()
            expected = expected_result(nodes, edges)
            assert actual == expected, f"Expected dynamic result {expected!r}, got {actual!r}."
    finally:
        with open(NODES_CSV, "wb") as f:
            f.write(ORIGINAL_NODES)
        with open(EDGES_CSV, "wb") as f:
            f.write(ORIGINAL_EDGES)
        run_application()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

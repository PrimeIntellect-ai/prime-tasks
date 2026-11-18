#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sqlite3
import csv
from collections import Counter

import networkx as nx

DB_PATH = "/home/user/dataset/graph.db"
CSV_PATH = "/home/user/dataset/citations.csv"
PATH_FILE = "/home/user/dataset/shortest_path.txt"


def read_csv_edges():
    assert os.path.isfile(CSV_PATH), f"File {CSV_PATH} does not exist."
    with open(CSV_PATH, "r", newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header is not None, "CSV file is empty."
        assert len(header) >= 2 and header[0] == "source" and header[1] == "target", \
            "CSV must have source,target columns."
        edges = []
        for line_number, row in enumerate(reader, start=2):
            assert len(row) == 2, f"Malformed CSV row at line {line_number}: {row!r}"
            try:
                edges.append((int(row[0]), int(row[1])))
            except ValueError:
                raise AssertionError(f"Non-integer CSV row at line {line_number}: {row!r}")
    return edges


def test_shortest_path_result():
    assert os.path.isfile(PATH_FILE), f"File {PATH_FILE} does not exist."
    with open(PATH_FILE, "r") as f:
        content = f.read().strip()

    assert content, "Shortest-path file is empty."
    parts = content.split(",")
    try:
        submitted_path = [int(part) for part in parts]
    except ValueError:
        raise AssertionError(f"Shortest path is not a comma-separated sequence of integers: {content!r}")

    assert content == ",".join(str(node) for node in submitted_path), \
        "Shortest path must be exported as a plain comma-separated integer sequence."
    assert submitted_path[0] == 10, "Shortest path must start at node 10."
    assert submitted_path[-1] == 99, "Shortest path must end at node 99."

    csv_edges = read_csv_edges()
    graph = nx.DiGraph()
    graph.add_edges_from(csv_edges)
    assert nx.has_path(graph, 10, 99), "The CSV graph has no path from node 10 to node 99."

    edge_set = set(csv_edges)
    for source, target in zip(submitted_path, submitted_path[1:]):
        assert (source, target) in edge_set, \
            f"Submitted path uses edge ({source}, {target}), which is absent from the CSV."

    expected_distance = nx.shortest_path_length(graph, source=10, target=99)
    submitted_distance = len(submitted_path) - 1
    assert submitted_distance == expected_distance, \
        f"Submitted path has length {submitted_distance}, but the CSV graph's shortest distance is {expected_distance}."


def test_database_exists_and_schema():
    assert os.path.isfile(DB_PATH), f"Database {DB_PATH} does not exist."

    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()

        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='citations'")
        assert cursor.fetchone() is not None, "Table 'citations' does not exist in the database."

        cursor.execute("PRAGMA table_info(citations)")
        columns = {row[1]: row[2].upper() for row in cursor.fetchall()}
        assert "source" in columns, "Column 'source' missing from 'citations' table."
        assert "target" in columns, "Column 'target' missing from 'citations' table."
        assert "INT" in columns["source"], "Column 'source' should be of type INTEGER."
        assert "INT" in columns["target"], "Column 'target' should be of type INTEGER."

        cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='citations'")
        indices = cursor.fetchall()
        user_indices = [idx[0] for idx in indices if not idx[0].startswith("sqlite_autoindex")]
        assert len(user_indices) > 0, "No explicit index found on 'citations' table. An index was required."

        suitable_indices = []
        for index_name in user_indices:
            cursor.execute("PRAGMA index_list(citations)")
            index_metadata = {row[1]: row for row in cursor.fetchall()}
            metadata = index_metadata.get(index_name)
            if metadata is not None and len(metadata) > 4 and metadata[4]:
                continue
            escaped_name = index_name.replace("'", "''")
            cursor.execute(f"PRAGMA index_info('{escaped_name}')")
            indexed_columns = [row[2] for row in sorted(cursor.fetchall(), key=lambda row: row[0])]
            if indexed_columns[:2] == ["source", "target"]:
                suitable_indices.append(index_name)

        assert suitable_indices, \
            "An explicit non-partial index beginning with (source, target) is required for source lookups and pair checks."
    finally:
        conn.close()


def test_database_content():
    if not os.path.isfile(DB_PATH) or not os.path.isfile(CSV_PATH):
        return

    csv_rows = read_csv_edges()
    csv_count = len(csv_rows)

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT count(*) FROM citations")
        db_count = cursor.fetchone()[0]
        cursor.execute("SELECT source, target FROM citations")
        db_rows = cursor.fetchall()
    except sqlite3.OperationalError:
        db_count = -1
        db_rows = []
    finally:
        conn.close()

    assert db_count == csv_count, f"Expected {csv_count} rows in database matching the CSV, got {db_count}."
    assert Counter(db_rows) == Counter(csv_rows), \
        "The citations table does not contain exactly the source,target rows from citations.csv."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

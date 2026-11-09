#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import sqlite3
from collections import Counter
import pytest

DB_PATH = "/home/user/research.db"
JSONL_PATH = "/home/user/dataset/papers.jsonl"
CSV_PATH = "/home/user/influential_ml_papers.csv"


def compute_pagerank(nodes, edges, alpha=0.85, max_iter=100, tol=1.0e-6):
    """Compute PageRank in pure Python to match networkx default behavior."""
    N = len(nodes)
    if N == 0:
        return {}

    pr = {n: 1.0 / N for n in nodes}
    out_degree = {n: 0 for n in nodes}
    for u, v in edges:
        out_degree[u] += 1

    for _ in range(max_iter):
        new_pr = {n: (1.0 - alpha) / N for n in nodes}
        dangling_sum = sum(pr[n] for n in nodes if out_degree[n] == 0)

        for n in nodes:
            new_pr[n] += alpha * dangling_sum / N

        for u, v in edges:
            new_pr[v] += alpha * pr[u] / out_degree[u]

        err = sum(abs(new_pr[n] - pr[n]) for n in nodes)
        pr = new_pr
        if err < tol:
            break

    return pr


def read_source():
    assert os.path.exists(JSONL_PATH), f"Input file {JSONL_PATH} is missing."
    records = []
    with open(JSONL_PATH, "r") as f:
        for line in f:
            if line.strip():
                records.append(json.loads(line))
    return records


def quote_identifier(value):
    return '"' + value.replace('"', '""') + '"'


def find_exact_relation(conn, tables, expected_rows, used_tables, label):
    """Find a distinct table containing exactly the expected two-column relation."""
    expected = Counter(tuple(row) for row in expected_rows)

    for table in tables:
        if table in used_tables:
            continue
        qtable = quote_identifier(table)
        columns = [row[1] for row in conn.execute(f"PRAGMA table_info({qtable})")]
        if len(columns) < 2:
            continue

        row_count = conn.execute(f"SELECT COUNT(*) FROM {qtable}").fetchone()[0]
        if row_count != len(expected_rows):
            continue

        for first in columns:
            for second in columns:
                if first == second:
                    continue
                query = (
                    f"SELECT {quote_identifier(first)}, {quote_identifier(second)} "
                    f"FROM {qtable}"
                )
                actual = Counter(tuple(row) for row in conn.execute(query).fetchall())
                if actual == expected:
                    return {"table": table, "first": first, "second": second}

    pytest.fail(
        f"Database does not contain a distinct normalized {label} relation "
        f"with exactly the rows from {JSONL_PATH}."
    )


@pytest.fixture
def expected_data():
    nodes = []
    edges = []
    ml_papers = {}

    for data in read_source():
        pid = data['id']
        nodes.append(pid)
        if "machine_learning" in data.get("keywords", []):
            ml_papers[pid] = data['title']
        for cited in data.get("citations", []):
            edges.append((pid, cited))

    pr = compute_pagerank(nodes, edges)
    ml_pr = [(pid, ml_papers[pid], pr[pid]) for pid in ml_papers]
    ml_pr.sort(key=lambda x: (-x[2], x[0]))
    return ml_pr[:3]


@pytest.fixture
def normalized_database():
    records = read_source()
    expected_relations = {
        "papers": [(r["id"], r["title"]) for r in records],
        "authors": [(r["id"], author) for r in records for author in r.get("authors", [])],
        "citations": [(r["id"], cited) for r in records for cited in r.get("citations", [])],
        "keywords": [(r["id"], keyword) for r in records for keyword in r.get("keywords", [])],
    }

    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} was not created."
    try:
        conn = sqlite3.connect(DB_PATH)
        tables = [
            row[0]
            for row in conn.execute(
                "SELECT name FROM sqlite_master "
                "WHERE type='table' AND name NOT LIKE 'sqlite_%'"
            ).fetchall()
        ]

        used = set()
        mappings = {}
        for label in ("papers", "authors", "citations", "keywords"):
            mapping = find_exact_relation(
                conn, tables, expected_relations[label], used, label
            )
            mappings[label] = mapping
            used.add(mapping["table"])
        conn.close()
        return mappings
    except sqlite3.Error as e:
        pytest.fail(f"Failed to validate normalized data in {DB_PATH}: {e}")


def test_database_exists():
    db_path = "/home/user/research.db"
    assert os.path.exists(db_path), f"Database file {db_path} was not created."

    # Try to connect to ensure it's a valid SQLite DB
    try:
        conn = sqlite3.connect(db_path)
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
        tables = cursor.fetchall()
        conn.close()
        assert len(tables) > 0, "Database exists but contains no tables."
    except sqlite3.Error as e:
        pytest.fail(f"Failed to read SQLite database at {db_path}: {e}")


def test_database_contains_normalized_input(normalized_database):
    assert len({m["table"] for m in normalized_database.values()}) == 4


def test_csv_output(expected_data):
    csv_path = "/home/user/influential_ml_papers.csv"
    assert os.path.exists(csv_path), f"Output file {csv_path} was not created."

    with open(csv_path, 'r', newline='') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "CSV file is empty."

    header = rows[0]
    assert header == ['id', 'title', 'pagerank'], f"Incorrect CSV header. Expected ['id', 'title', 'pagerank'], got {header}"

    data_rows = rows[1:]
    assert len(data_rows) == 3, f"Expected exactly 3 data rows in CSV, got {len(data_rows)}."

    for i, (expected_id, expected_title, expected_pr) in enumerate(expected_data):
        actual_id, actual_title, actual_pr_str = data_rows[i]

        assert actual_id == expected_id, f"Row {i+1}: Expected id '{expected_id}', got '{actual_id}'"
        assert actual_title == expected_title, f"Row {i+1}: Expected title '{expected_title}', got '{actual_title}'"

        expected_pr_rounded = f"{expected_pr:.4f}"
        assert actual_pr_str == expected_pr_rounded, f"Row {i+1}: Expected pagerank '{expected_pr_rounded}', got '{actual_pr_str}'"


def test_csv_matches_network_queried_from_database(normalized_database):
    conn = sqlite3.connect(DB_PATH)

    def read_relation(mapping):
        query = (
            f"SELECT {quote_identifier(mapping['first'])}, "
            f"{quote_identifier(mapping['second'])} "
            f"FROM {quote_identifier(mapping['table'])}"
        )
        return [tuple(row) for row in conn.execute(query).fetchall()]

    papers = read_relation(normalized_database["papers"])
    citations = read_relation(normalized_database["citations"])
    keywords = read_relation(normalized_database["keywords"])
    conn.close()

    titles = dict(papers)
    nodes = [pid for pid, _ in papers]
    ml_ids = {pid for pid, keyword in keywords if keyword == "machine_learning"}
    pr = compute_pagerank(nodes, citations)
    expected = [(pid, titles[pid], pr[pid]) for pid in ml_ids]
    expected.sort(key=lambda x: (-x[2], x[0]))
    expected = expected[:3]

    with open(CSV_PATH, "r", newline="") as f:
        rows = list(csv.reader(f))

    assert rows[0] == ["id", "title", "pagerank"]
    assert rows[1:] == [
        [pid, title, f"{rank:.4f}"] for pid, title, rank in expected
    ], "CSV does not match the citation network and keyword data stored in SQLite."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

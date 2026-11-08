#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import json
import csv
import sqlite3
import subprocess
import uuid
import pytest

DATA_FILE = "/home/user/data/transactions.jsonl"
EDGES_CSV = "/home/user/data/edges.csv"
DB_FILE = "/home/user/db/graph.sqlite"
RESULTS_CSV = "/home/user/results/top_paths.csv"
EXTRACT_SCRIPT = "/home/user/scripts/extract.py"
SCHEMA_SCRIPT = "/home/user/scripts/schema.sql"
ANALYZE_SCRIPT = "/home/user/scripts/analyze.sql"


def get_expected_edges():
    edges = []
    if not os.path.exists(DATA_FILE):
        return edges
    with open(DATA_FILE, 'r') as f:
        for line in f:
            if not line.strip():
                continue
            record = json.loads(line)
            if record.get("event_type") == "transfer" and record.get("status") == "success":
                edges.append({
                    "source": record["sender"],
                    "target": record["receiver"],
                    "timestamp": record["timestamp"],
                    "amount": record["amount"]
                })
    return edges


def get_expected_top_paths():
    edges = get_expected_edges()

    # Build 3-hop paths
    paths = []
    for e1 in edges:
        for e2 in edges:
            if e1["target"] == e2["source"] and e1["timestamp"] < e2["timestamp"]:
                for e3 in edges:
                    if e2["target"] == e3["source"] and e2["timestamp"] < e3["timestamp"]:
                        paths.append({
                            "start_node": e1["source"],
                            "end_node": e3["target"],
                            "total_amount": e1["amount"] + e2["amount"] + e3["amount"]
                        })

    # Rank by total_amount descending partitioned by start_node
    best_paths = {}
    for p in paths:
        sn = p["start_node"]
        if sn not in best_paths or p["total_amount"] > best_paths[sn]["total_amount"]:
            best_paths[sn] = p

    # Sort globally by total_amount desc, take top 5
    sorted_paths = sorted(best_paths.values(), key=lambda x: x["total_amount"], reverse=True)
    return sorted_paths[:5]


def test_edges_csv_exists_and_correct():
    assert os.path.isfile(EDGES_CSV), f"Edges CSV file is missing: {EDGES_CSV}"

    expected_edges = get_expected_edges()

    with open(EDGES_CSV, 'r') as f:
        reader = csv.DictReader(f)
        headers = reader.fieldnames
        assert headers == ["source", "target", "timestamp", "amount"], f"Incorrect headers in {EDGES_CSV}"

        rows = list(reader)
        assert len(rows) == len(expected_edges), f"Expected {len(expected_edges)} edges, found {len(rows)}"

        # Check a few records if possible
        for row, exp in zip(rows, expected_edges):
            assert row["source"] == exp["source"]
            assert row["target"] == exp["target"]
            assert int(row["timestamp"]) == exp["timestamp"]
            assert float(row["amount"]) == exp["amount"]


def check_schema_and_indexes(conn):
    cursor = conn.cursor()

    # Check table exists
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='Edges'")
    assert cursor.fetchone() is not None, "Table 'Edges' does not exist in the database."

    # Check columns
    cursor.execute("PRAGMA table_info(Edges)")
    table_info = cursor.fetchall()
    columns = {row[1]: row[2].upper() for row in table_info}
    assert "source" in columns, "Column 'source' missing"
    assert "target" in columns, "Column 'target' missing"
    assert "timestamp" in columns, "Column 'timestamp' missing"
    assert "amount" in columns, "Column 'amount' missing"
    assert [(row[1], row[2].upper()) for row in table_info] == [
        ("source", "TEXT"), ("target", "TEXT"),
        ("timestamp", "INTEGER"), ("amount", "REAL")
    ], "Edges must have the required columns, order, and declared types"

    # Check indexes
    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='Edges'")
    indexes = cursor.fetchall()
    assert len(indexes) > 0, "No indexes found on the Edges table. Indexes are required for optimization."

    useful = False
    for (name,) in indexes:
        escaped = name.replace("'", "''")
        cursor.execute(f"PRAGMA index_info('{escaped}')")
        indexed_columns = [row[2].lower() for row in cursor.fetchall()]
        if indexed_columns[:2] == ["source", "timestamp"]:
            useful = True
    assert useful, "A composite index beginning with (source, timestamp) is required for time-ordered traversal lookups"


def test_database_and_schema():
    assert os.path.isfile(DB_FILE), f"Database file is missing: {DB_FILE}"

    conn = sqlite3.connect(DB_FILE)
    check_schema_and_indexes(conn)
    cursor = conn.cursor()

    # Check data loaded
    cursor.execute("SELECT COUNT(*) FROM Edges")
    count = cursor.fetchone()[0]
    expected_edges = get_expected_edges()
    expected_count = len(expected_edges)
    assert count == expected_count, f"Expected {expected_count} rows in Edges table, found {count}"

    cursor.execute("SELECT source, target, timestamp, amount FROM Edges ORDER BY rowid")
    actual = [(r[0], r[1], int(r[2]), float(r[3])) for r in cursor.fetchall()]
    expected = [(e["source"], e["target"], int(e["timestamp"]), float(e["amount"])) for e in expected_edges]
    assert actual == expected, "Edges table rows do not exactly match the extracted successful transfers"

    conn.close()


def test_results_csv_exists_and_correct():
    assert os.path.isfile(RESULTS_CSV), f"Results CSV file is missing: {RESULTS_CSV}"

    expected_paths = get_expected_top_paths()

    with open(RESULTS_CSV, 'r') as f:
        reader = csv.reader(f)
        headers = next(reader, None)
        assert headers == ["start_node", "end_node", "total_amount"], f"Incorrect headers in {RESULTS_CSV}"

        rows = list(reader)
        assert len(rows) == len(expected_paths), f"Expected {len(expected_paths)} paths, found {len(rows)}"

        for i, (row, exp) in enumerate(zip(rows, expected_paths)):
            assert row[0] == exp["start_node"], f"Row {i+1}: expected start_node {exp['start_node']}, got {row[0]}"
            assert row[1] == exp["end_node"], f"Row {i+1}: expected end_node {exp['end_node']}, got {row[1]}"
            assert float(row[2]) == pytest.approx(exp["total_amount"]), f"Row {i+1}: expected total_amount {exp['total_amount']}, got {row[2]}"


def test_z_required_artifacts_execute_on_fresh_input():
    for path in (EXTRACT_SCRIPT, SCHEMA_SCRIPT, ANALYZE_SCRIPT):
        assert os.path.isfile(path), f"Required script is missing: {path}"
        assert os.path.getsize(path) > 0, f"Required script is empty: {path}"

    with open(ANALYZE_SCRIPT, 'r') as f:
        analyze_sql = f.read()
    sql_without_comments = re.sub(r"/\*.*?\*/", " ", analyze_sql, flags=re.S)
    sql_without_comments = re.sub(r"--[^\n]*", " ", sql_without_comments)
    assert re.search(
        r"\b(?:row_number|rank|dense_rank)\s*\(\s*\)\s*over\s*\(\s*partition\s+by\b",
        sql_without_comments,
        flags=re.I | re.S,
    ), "analyze.sql must implement ranking with a window function partitioned by the starting node"
    assert re.search(r"\bpath_rank\b", sql_without_comments, flags=re.I), "analyze.sql must assign/use path_rank"

    token = uuid.uuid4().hex[:10]
    events = [{"event_type": "login", "user": token, "timestamp": 1}]
    # Seven disconnected paths exercise per-source ranking, global ordering, and LIMIT 5.
    totals = [930.0, 810.0, 720.0, 640.0, 550.0, 460.0, 370.0]
    for i, total in enumerate(totals):
        a, b, c, d = [f"{token}_{i}_{x}" for x in "ABCD"]
        base = 1000 + i * 20
        events.extend([
            {"event_type": "transfer", "status": "success", "sender": a, "receiver": b, "timestamp": base, "amount": total - 30.0},
            {"event_type": "transfer", "status": "success", "sender": b, "receiver": c, "timestamp": base + 2, "amount": 10.0},
            {"event_type": "transfer", "status": "success", "sender": c, "receiver": d, "timestamp": base + 5, "amount": 20.0},
        ])

    # A lower-valued competing path for the first source must lose its partition rank.
    first = f"{token}_0_A"
    x, y, z = f"{token}_alt_X", f"{token}_alt_Y", f"{token}_alt_Z"
    events.extend([
        {"event_type": "transfer", "status": "success", "sender": first, "receiver": x, "timestamp": 2000, "amount": 1.0},
        {"event_type": "transfer", "status": "success", "sender": x, "receiver": y, "timestamp": 2001, "amount": 2.0},
        {"event_type": "transfer", "status": "success", "sender": y, "receiver": z, "timestamp": 2002, "amount": 3.0},
        {"event_type": "transfer", "status": "failed", "sender": "bad", "receiver": "bad2", "timestamp": 3000, "amount": 99999.0},
    ])

    with open(DATA_FILE, 'w') as f:
        for event in events:
            f.write(json.dumps(event) + "\n")

    if os.path.exists(EDGES_CSV):
        os.remove(EDGES_CSV)
    subprocess.run(["python3", EXTRACT_SCRIPT], cwd="/home/user", check=True, timeout=30)
    test_edges_csv_exists_and_correct()
    expected_edges = get_expected_edges()
    expected_paths = get_expected_top_paths()

    if os.path.exists(DB_FILE):
        os.remove(DB_FILE)
    with open(SCHEMA_SCRIPT, 'rb') as schema_in:
        subprocess.run(
            ["sqlite3", DB_FILE], stdin=schema_in, cwd="/home/user",
            check=True, timeout=30, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )

    conn = sqlite3.connect(DB_FILE)
    check_schema_and_indexes(conn)
    conn.execute("DELETE FROM Edges")
    conn.executemany(
        "INSERT INTO Edges(source, target, timestamp, amount) VALUES (?, ?, ?, ?)",
        [(e["source"], e["target"], e["timestamp"], e["amount"]) for e in expected_edges]
    )
    conn.commit()
    conn.close()

    if os.path.exists(RESULTS_CSV):
        os.remove(RESULTS_CSV)
    completed = subprocess.run(
        ["sqlite3", "-header", "-csv", DB_FILE],
        input=analyze_sql, text=True, cwd="/home/user",
        check=True, timeout=30, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    if not os.path.isfile(RESULTS_CSV) or os.path.getsize(RESULTS_CSV) == 0:
        assert completed.stdout.strip(), "Executing analyze.sql produced no CSV output"
        with open(RESULTS_CSV, 'w') as f:
            f.write(completed.stdout)

    test_results_csv_exists_and_correct()
    assert len(expected_paths) == 5
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

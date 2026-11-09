#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import sqlite3
import subprocess
from collections import deque

AUDIT_DIR = "/home/user/audit_tool"
DB_PATH = "/home/user/compliance.db"

CANONICAL_EDGES = [
    (101, 101, 102, 50.0, 1600000000),
    (102, 102, 103, 50.0, 1600000001),
    (103, 103, 205, 50.0, 1600000002),
    (101, 101, 999, 10.0, 1600000003),
    (999, 999, 205, 10.0, 1600000004),
]


def create_database(path, edges=CANONICAL_EDGES):
    for suffix in ("", "-wal", "-shm"):
        try:
            os.remove(path + suffix)
        except FileNotFoundError:
            pass

    db = sqlite3.connect(path)
    db.executescript("""
        CREATE TABLE accounts (id INTEGER PRIMARY KEY, risk_score INTEGER);
        CREATE TABLE transactions (
            id INTEGER PRIMARY KEY,
            account_id INTEGER,
            sender_id INTEGER,
            receiver_id INTEGER,
            amount REAL,
            timestamp INTEGER
        );
        INSERT INTO accounts (id, risk_score)
        VALUES (101, 0), (102, 0), (103, 0), (205, 0), (999, 0);
    """)
    db.executemany(
        "INSERT INTO transactions "
        "(account_id, sender_id, receiver_id, amount, timestamp) "
        "VALUES (?, ?, ?, ?, ?)",
        edges,
    )
    db.commit()
    db.close()


def shortest_distance(edges, start=101, target=205):
    graph = {}
    for _, sender, receiver, _, _ in edges:
        graph.setdefault(sender, []).append(receiver)

    queue = deque([(start, 0)])
    seen = {start}
    while queue:
        node, distance = queue.popleft()
        if node == target:
            return distance
        for nxt in graph.get(node, []):
            if nxt not in seen:
                seen.add(nxt)
                queue.append((nxt, distance + 1))
    return None


def run_path_query(sql_path, db_path):
    with open(sql_path, "r") as f:
        sql = f.read()
    result = subprocess.run(
        ["sqlite3", "-batch", "-noheader", db_path],
        input=sql,
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert result.returncode == 0, f"path.sql failed: {result.stderr}"
    rows = [line.strip() for line in result.stdout.splitlines() if line.strip()]
    assert len(rows) == 1, f"path.sql must output exactly one row, got: {result.stdout!r}"
    assert re.fullmatch(r"-?\d+", rows[0]), f"path_length is not an integer: {rows[0]!r}"
    return int(rows[0])


def test_audit_tool_compiles_runs_and_applies_both_updates():
    source = os.path.join(AUDIT_DIR, "main.cpp")
    binary = "/tmp/verified_audit_tool"
    log_path = os.path.join(AUDIT_DIR, "audit_success.log")
    assert os.path.isfile(source), f"C++ source {source} is missing."

    create_database(DB_PATH)
    try:
        os.remove(log_path)
    except FileNotFoundError:
        pass

    compiled = subprocess.run(
        ["g++", "-std=c++17", "-pthread", source, "-lsqlite3", "-o", binary],
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert compiled.returncode == 0, f"main.cpp did not compile:\n{compiled.stderr}"

    executed = subprocess.run(
        [binary],
        cwd=AUDIT_DIR,
        text=True,
        capture_output=True,
        timeout=12,
    )
    assert executed.returncode == 0, (
        f"audit_tool exited with {executed.returncode}:\n"
        f"stdout: {executed.stdout}\nstderr: {executed.stderr}"
    )

    assert os.path.isfile(log_path), (
        f"Log file {log_path} is missing. Did the C++ program run successfully?"
    )
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert "AUDIT_COMPLETE" in content, (
        f"Expected 'AUDIT_COMPLETE' in {log_path}, but found: {content}"
    )

    db = sqlite3.connect(DB_PATH)
    scores = dict(db.execute(
        "SELECT id, risk_score FROM accounts WHERE id IN (101, 102)"
    ).fetchall())
    db.close()
    assert scores == {101: 30, 102: 30}, (
        "Both concurrent transactions must complete successfully; expected each "
        f"account to receive the +10 and +20 updates, but got {scores}."
    )


def test_optimize_sql_executes_and_avoids_sort_and_table_scan(tmp_path):
    sql_path = "/home/user/optimize.sql"
    assert os.path.isfile(sql_path), f"SQL script {sql_path} is missing."
    with open(sql_path, "r") as f:
        content = f.read()

    assert re.search(r"CREATE\s+(UNIQUE\s+)?INDEX", content, re.IGNORECASE), (
        f"{sql_path} does not contain a CREATE INDEX statement."
    )
    assert re.search(r"transactions", content, re.IGNORECASE), (
        f"{sql_path} does not seem to create an index on the 'transactions' table."
    )

    fixture = str(tmp_path / "index_fixture.db")
    create_database(fixture)
    db = sqlite3.connect(fixture)
    try:
        db.executescript(content)
        indexes = db.execute("PRAGMA index_list('transactions')").fetchall()
        user_indexes = [row[1] for row in indexes if row[3] == "c"]
        assert user_indexes, "optimize.sql did not create an index on transactions."

        ordered_index_found = False
        for name in user_indexes:
            quoted = name.replace("'", "''")
            columns = [
                row[2] for row in db.execute(f"PRAGMA index_info('{quoted}')").fetchall()
            ]
            if columns[:2] == ["account_id", "timestamp"]:
                ordered_index_found = True
                break
        assert ordered_index_found, (
            "An index used for this window query must begin with "
            "(account_id, timestamp)."
        )

        query = """
            SELECT account_id, timestamp, amount,
                   SUM(amount) OVER (
                       PARTITION BY account_id
                       ORDER BY timestamp
                       ROWS BETWEEN 6 PRECEDING AND CURRENT ROW
                   ) AS rolling_7_tx_sum
            FROM transactions
        """
        db.execute(query).fetchall()
        plan_rows = db.execute("EXPLAIN QUERY PLAN " + query).fetchall()
        plan = "\n".join(str(row[3]) for row in plan_rows)
        assert "USE TEMP B-TREE" not in plan.upper(), (
            f"Query plan still sorts using a temporary B-tree:\n{plan}"
        )
        assert not re.search(
            r"\bSCAN\s+(?:\w+\.)?transactions\b(?!.*\bUSING\b.*\bINDEX\b)",
            plan,
            re.IGNORECASE,
        ), f"Query plan still performs an unindexed transactions table scan:\n{plan}"
        assert re.search(
            r"\bSCAN\s+(?:\w+\.)?transactions\b.*\bUSING\b.*\bINDEX\b",
            plan,
            re.IGNORECASE,
        ), f"Query plan does not use the ordering index:\n{plan}"
    finally:
        db.close()


def test_path_sql_is_recursive_and_computes_shortest_paths(tmp_path):
    sql_path = "/home/user/path.sql"
    assert os.path.isfile(sql_path), f"SQL script {sql_path} is missing."
    with open(sql_path, "r") as f:
        content = f.read()
    assert re.search(r"\bWITH\s+RECURSIVE\b", content, re.IGNORECASE), (
        "path.sql must use a recursive CTE."
    )
    assert re.search(r"\btransactions\b", content, re.IGNORECASE), (
        "path.sql must traverse the transactions table."
    )
    assert re.search(r"\bsender_id\b", content, re.IGNORECASE)
    assert re.search(r"\breceiver_id\b", content, re.IGNORECASE)

    fixture_sets = [
        CANONICAL_EDGES,
        [
            (1, 101, 77, 1.0, 1),
            (2, 77, 101, 1.0, 2),
            (3, 77, 205, 1.0, 3),
            (4, 101, 205, 1.0, 4),
            (5, 205, 101, 1.0, 5),
        ],
        [
            (1, 101, 11, 1.0, 1),
            (2, 11, 12, 1.0, 2),
            (3, 12, 13, 1.0, 3),
            (4, 13, 205, 1.0, 4),
            (5, 12, 11, 1.0, 5),
            (6, 101, 50, 1.0, 6),
            (7, 50, 51, 1.0, 7),
            (8, 51, 52, 1.0, 8),
            (9, 52, 53, 1.0, 9),
            (10, 53, 205, 1.0, 10),
        ],
    ]

    for number, edges in enumerate(fixture_sets):
        fixture = str(tmp_path / f"path_fixture_{number}.db")
        create_database(fixture, edges)
        expected = shortest_distance(edges)
        actual = run_path_query(sql_path, fixture)
        assert actual == expected, (
            f"path.sql returned {actual}, but the derived shortest path is {expected} "
            f"for fixture {number}."
        )


def test_shortest_path_csv_matches_executed_query():
    sql_path = "/home/user/path.sql"
    csv_path = "/home/user/shortest_path.csv"
    assert os.path.isfile(csv_path), f"Output file {csv_path} is missing."
    with open(csv_path, "r") as f:
        content = f.read().strip()
    assert content == "2", (
        f"Expected shortest path length to be '2', but found: '{content}'"
    )

    actual = run_path_query(sql_path, DB_PATH)
    expected = shortest_distance(CANONICAL_EDGES)
    assert actual == expected == 2
    assert content == str(actual), (
        "shortest_path.csv does not match the result produced by path.sql."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

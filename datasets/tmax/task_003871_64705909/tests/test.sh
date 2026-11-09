#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import sqlite3
import tempfile
import pytest

FIXED_QUERY_PATH = "/home/user/fixed_query.sql"
AUDIT_SUMMARY_PATH = "/home/user/audit_summary.json"
DB_PATH = "/home/user/compliance.db"


def load_query():
    assert os.path.exists(FIXED_QUERY_PATH), f"Fixed query file missing at {FIXED_QUERY_PATH}"
    assert os.path.isfile(FIXED_QUERY_PATH), f"{FIXED_QUERY_PATH} is not a file"
    with open(FIXED_QUERY_PATH, "r") as f:
        query = f.read().strip()
    assert query, "Fixed query file is empty"
    return query


def execute_read_only_query(db_path, query):
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    allowed = {
        sqlite3.SQLITE_SELECT,
        sqlite3.SQLITE_READ,
        sqlite3.SQLITE_FUNCTION,
    }
    if hasattr(sqlite3, "SQLITE_RECURSIVE"):
        allowed.add(sqlite3.SQLITE_RECURSIVE)

    def authorizer(action, arg1, arg2, db_name, trigger_name):
        return sqlite3.SQLITE_OK if action in allowed else sqlite3.SQLITE_DENY

    conn.set_authorizer(authorizer)
    cursor = conn.cursor()
    try:
        cursor.execute(query)
        rows = cursor.fetchall()
        columns = [description[0].lower() for description in cursor.description] if cursor.description else []
        return columns, rows
    except sqlite3.Error as e:
        pytest.fail(f"Executing fixed_query.sql failed with error: {e}")
    finally:
        conn.close()


def test_fixed_query_exists_and_correct():
    query = load_query()
    columns, rows = execute_read_only_query(DB_PATH, query)

    assert "name" in columns and "total_sent" in columns, \
        f"Query must return 'name' and 'total_sent' columns. Got: {columns}"

    results_dict = {row["name"]: row["total_sent"] for row in rows}
    expected_results = {"Alice": 350, "Charlie": 600}
    assert len(rows) == len(expected_results), \
        f"Query returned an incorrect number of rows: {len(rows)}"
    assert results_dict == expected_results, \
        f"Query results are incorrect. Expected {expected_results}, got {results_dict}"


def make_random_database(path):
    rng = secrets.SystemRandom()
    employee_ids = rng.sample(range(1000, 1000000), 7)
    names = [f"Employee_{secrets.token_hex(6)}" for _ in employee_ids]
    departments = ["Trading", "Research", "Sales", "Operations", "Trading", "Legal", "Trading"]
    rng.shuffle(departments)
    urgent_indexes = set(rng.sample(range(len(employee_ids)), 3))

    conn = sqlite3.connect(path)
    cur = conn.cursor()
    cur.executescript("""
        CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, department TEXT);
        CREATE TABLE transfers (
            id INTEGER PRIMARY KEY, sender_id INTEGER, receiver_id INTEGER,
            amount INTEGER, date TEXT
        );
        CREATE TABLE messages (
            id INTEGER PRIMARY KEY, sender_id INTEGER, receiver_id INTEGER,
            content TEXT, date TEXT
        );
    """)
    cur.executemany(
        "INSERT INTO employees(id, name, department) VALUES (?, ?, ?)",
        list(zip(employee_ids, names, departments)),
    )

    transfer_id = 1
    message_id = 1
    expected = {}
    for i, (sender_id, name) in enumerate(zip(employee_ids, names)):
        transfer_count = rng.randint(1, 6)
        total = 0
        for j in range(transfer_count):
            receiver_id = employee_ids[(i + j + 1) % len(employee_ids)]
            amount = rng.randint(11, 997)
            total += amount
            cur.execute(
                "INSERT INTO transfers VALUES (?, ?, ?, ?, ?)",
                (transfer_id, sender_id, receiver_id, amount, f"2025-02-{transfer_id:02d}"),
            )
            transfer_id += 1

        if i in urgent_indexes:
            expected[name] = total
            # Multiple matching messages ensure a cross join would duplicate totals.
            for content in ("urgent: review required", "This is URGENT now"):
                cur.execute(
                    "INSERT INTO messages VALUES (?, ?, ?, ?, ?)",
                    (message_id, sender_id, employee_ids[(i + 1) % len(employee_ids)], content,
                     f"2025-03-{message_id:02d}"),
                )
                message_id += 1
        else:
            cur.execute(
                "INSERT INTO messages VALUES (?, ?, ?, ?, ?)",
                (message_id, sender_id, employee_ids[(i + 1) % len(employee_ids)],
                 "routine status update", f"2025-03-{message_id:02d}"),
            )
            message_id += 1

    conn.commit()
    conn.close()
    return expected


def test_fixed_query_generalizes_to_unseen_databases():
    query = load_query()
    for _ in range(3):
        fd, path = tempfile.mkstemp(prefix="compliance_case_", suffix=".db")
        os.close(fd)
        try:
            expected = make_random_database(path)
            columns, rows = execute_read_only_query(path, query)
            assert "name" in columns and "total_sent" in columns, \
                f"Query must return 'name' and 'total_sent' columns. Got: {columns}"
            actual = {row["name"]: row["total_sent"] for row in rows}
            assert len(rows) == len(expected), \
                f"Query returned {len(rows)} rows on an unseen database; expected {len(expected)}"
            assert actual == expected, \
                f"Query does not implement the required transfer/message logic. Expected {expected}, got {actual}"
        finally:
            os.unlink(path)


def independently_derive_summary():
    conn = sqlite3.connect(DB_PATH)
    try:
        totals = conn.execute("""
            SELECT e.name, SUM(t.amount) AS total_sent
            FROM employees AS e
            JOIN transfers AS t ON t.sender_id = e.id
            WHERE EXISTS (
                SELECT 1 FROM messages AS m
                WHERE m.sender_id = e.id AND m.content LIKE '%urgent%'
            )
            GROUP BY e.id, e.name
        """).fetchall()
        assert totals, "No qualifying employees found in compliance.db"
        highest_name = max(totals, key=lambda row: row[1])[0]

        traders = conn.execute("""
            SELECT e.id, COUNT(t.id) AS out_degree
            FROM employees AS e
            LEFT JOIN transfers AS t ON t.sender_id = e.id
            WHERE e.department = 'Trading'
            GROUP BY e.id
            ORDER BY out_degree DESC, e.id ASC
        """).fetchall()
        assert traders, "No Trading employees found in compliance.db"
        central_id = traders[0][0]
        return highest_name, central_id
    finally:
        conn.close()


def test_audit_summary_json():
    assert os.path.exists(AUDIT_SUMMARY_PATH), f"Audit summary file missing at {AUDIT_SUMMARY_PATH}"
    assert os.path.isfile(AUDIT_SUMMARY_PATH), f"{AUDIT_SUMMARY_PATH} is not a file"

    try:
        with open(AUDIT_SUMMARY_PATH, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError as e:
        pytest.fail(f"File {AUDIT_SUMMARY_PATH} is not valid JSON: {e}")

    assert isinstance(data, dict), f"JSON content must be a dictionary, got {type(data)}"
    assert set(data.keys()) == {"highest_transfer_employee", "central_trader_id"}, \
        f"JSON must contain exactly the two required keys, got {set(data.keys())}"

    expected_name, expected_central_id = independently_derive_summary()
    assert expected_name == "Charlie"
    assert expected_central_id == 5

    assert data["highest_transfer_employee"] == "Charlie", \
        f"Incorrect highest_transfer_employee. Expected 'Charlie', got {data['highest_transfer_employee']}"
    assert data["highest_transfer_employee"] == expected_name, \
        "highest_transfer_employee does not match the value derived from compliance.db"
    assert type(data["central_trader_id"]) is int, "central_trader_id must be an integer"
    assert data["central_trader_id"] == 5, \
        f"Incorrect central_trader_id. Expected 5, got {data['central_trader_id']}"
    assert data["central_trader_id"] == expected_central_id, \
        "central_trader_id does not match the graph analysis derived from compliance.db"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

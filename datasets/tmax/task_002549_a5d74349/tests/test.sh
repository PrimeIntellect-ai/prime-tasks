#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import os
import sqlite3
import subprocess
import tempfile
import pytest

DB_PATH = '/home/user/financial_graph.db'
SCRIPT_PATH = '/home/user/audit_transactions.py'
CSV_PATH = '/home/user/flagged_entities.csv'
CANONICAL_IDS = [10, 20, 30, 45, 55, 65]


def assert_original_database_shape():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} does not exist."
    conn = sqlite3.connect(DB_PATH)
    try:
        c = conn.cursor()
        c.execute("SELECT id, name FROM entities ORDER BY id")
        assert c.fetchall() == [(i, f'Entity_{i}') for i in range(1, 101)]

        c.execute("SELECT tx_id, sender_id, receiver_id, amount, timestamp FROM transactions ORDER BY tx_id")
        rows = c.fetchall()
        assert 489 <= len(rows) <= 509, "The original transaction data was deleted or replaced."
        assert [row[0] for row in rows] == list(range(1, len(rows) + 1)), "Transaction IDs are no longer intact."

        normal_rows = rows[:-9]
        assert 480 <= len(normal_rows) <= 500
        for _, sender, receiver, amount, timestamp in normal_rows:
            assert 1 <= sender <= 100 and 1 <= receiver <= 100 and sender != receiver
            assert 100 <= amount <= 5000
            assert timestamp == '2023-01-01'

        first_injected_id = len(normal_rows) + 1
        expected_suffix = [
            (first_injected_id + 0, 10, 20, 15000.0, '2023-01-02'),
            (first_injected_id + 1, 20, 30, 12000.0, '2023-01-03'),
            (first_injected_id + 2, 30, 10, 11000.0, '2023-01-04'),
            (first_injected_id + 3, 45, 55, 25000.0, '2023-01-02'),
            (first_injected_id + 4, 55, 65, 22000.0, '2023-01-03'),
            (first_injected_id + 5, 65, 45, 21000.0, '2023-01-04'),
            (first_injected_id + 6, 70, 80, 15000.0, '2023-01-02'),
            (first_injected_id + 7, 80, 90, 5000.0, '2023-01-03'),
            (first_injected_id + 8, 90, 70, 11000.0, '2023-01-04'),
        ]
        assert rows[-9:] == expected_suffix, "The seeded audit transactions were altered."
    finally:
        conn.close()


def read_actual_ids():
    assert os.path.exists(CSV_PATH), f"Output file {CSV_PATH} does not exist."
    with open(CSV_PATH, 'r') as f:
        lines = f.read().splitlines()

    actual_ids = []
    for line in lines:
        line = line.strip()
        if line:
            try:
                actual_ids.append(int(line))
            except ValueError:
                pytest.fail(f"Invalid non-integer value found in CSV: {line}")
    return actual_ids


def test_script_execution_and_flagged_entities_csv():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert_original_database_shape()

    completed = subprocess.run(
        ['python3', SCRIPT_PATH], capture_output=True, text=True, timeout=15
    )
    assert completed.returncode == 0, (
        f"The audit script failed with exit code {completed.returncode}: {completed.stderr}"
    )

    # The script must not obtain a passing result by rewriting the source data.
    assert_original_database_shape()
    actual_ids = read_actual_ids()

    # Preserve the original database-derived assertion.
    conn = sqlite3.connect(DB_PATH)
    try:
        c = conn.cursor()
        query = """
            SELECT DISTINCT t1.sender_id
            FROM transactions t1
            JOIN transactions t2 ON t1.receiver_id = t2.sender_id
            JOIN transactions t3 ON t2.receiver_id = t3.sender_id
            WHERE t3.receiver_id = t1.sender_id
              AND t1.amount > 10000
              AND t2.amount > 10000
              AND t3.amount > 10000
        """
        c.execute(query)
        expected_ids = sorted([row[0] for row in c.fetchall()])
    finally:
        conn.close()

    assert expected_ids == CANONICAL_IDS
    assert actual_ids == expected_ids, f"Expected flagged entities {expected_ids}, but got {actual_ids}."


def make_test_database(path):
    conn = sqlite3.connect(path)
    try:
        conn.execute('CREATE TABLE transactions (tx_id INTEGER PRIMARY KEY, sender_id INTEGER, receiver_id INTEGER, amount REAL, timestamp TEXT)')
        rows = [
            (1, 1, 2, 101, 'x'), (2, 2, 3, 102, 'x'), (3, 3, 1, 103, 'x'),
            (4, 4, 5, 101, 'x'), (5, 5, 6, 100, 'x'), (6, 6, 4, 102, 'x'),
            (7, 8, 9, 5000, 'x'), (8, 9, 10, 5000, 'x'),
            (9, 11, 12, 1100, 'x'), (10, 12, 13, 1200, 'x'), (11, 13, 11, 1300, 'x'),
            (12, 20, 21, 50, 'x'), (13, 21, 22, 50, 'x'), (14, 22, 20, 50, 'x'),
        ]
        conn.executemany('INSERT INTO transactions VALUES (?, ?, ?, ?, ?)', rows)
        conn.commit()
    finally:
        conn.close()


def test_function_traverses_graph_and_parameterizes_threshold():
    spec = importlib.util.spec_from_file_location('submitted_audit_transactions', SCRIPT_PATH)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert hasattr(module, 'find_circular_transactions'), "find_circular_transactions is missing."

    with tempfile.TemporaryDirectory() as tmpdir:
        test_db = os.path.join(tmpdir, 'graph.db')
        make_test_database(test_db)

        result_100 = sorted(set(module.find_circular_transactions(test_db, 100)))
        assert result_100 == [1, 2, 3, 11, 12, 13]

        result_1000 = sorted(set(module.find_circular_transactions(test_db, 1000)))
        assert result_1000 == [11, 12, 13]

        # A bound value must not be interpreted as SQL syntax.
        injected = module.find_circular_transactions(test_db, '0 OR 1=1')
        assert injected == [], "The threshold appears to be interpolated instead of parameterized."


def test_database_indexes():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} does not exist."
    conn = sqlite3.connect(DB_PATH)
    try:
        c = conn.cursor()
        c.execute("PRAGMA index_list('transactions');")
        indexes = c.fetchall()
        user_indexes = [idx for idx in indexes if not idx[1].startswith('sqlite_')]

        # Preserve the original count assertion.
        assert len(user_indexes) >= 2, f"Expected at least 2 user-created indexes on the 'transactions' table, but found {len(user_indexes)}."

        leading_columns = set()
        for idx in user_indexes:
            index_name = idx[1]
            c.execute("PRAGMA index_info(%s)" % ('"' + index_name.replace('"', '""') + '"'))
            columns = [row[2] for row in c.fetchall()]
            if columns:
                leading_columns.add(columns[0])

        assert 'sender_id' in leading_columns, "No transactions index starts with sender_id."
        assert 'receiver_id' in leading_columns, "No transactions index starts with receiver_id."
    finally:
        conn.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

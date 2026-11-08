#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import os
import secrets
import shutil
import sqlite3
import subprocess
from collections import Counter, defaultdict

import pytest

SCRIPT_PATH = "/home/user/analyze_graph.sh"
DB_PATH = "/home/user/graph.db"
CSV_PATH = "/home/user/transactions.csv"


def read_csv_records(path):
    with open(path, newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["user_id", "product_id", "timestamp"]
        return [(r["user_id"], r["product_id"], r["timestamp"]) for r in reader]


def derive_graph(records):
    products_by_user = defaultdict(set)
    for user_id, product_id, _ in records:
        products_by_user[user_id].add(product_id)

    users = sorted(products_by_user)
    rows = []
    for i, user1 in enumerate(users):
        for user2 in users[i + 1:]:
            weight = len(products_by_user[user1] & products_by_user[user2])
            if weight >= 2:
                rows.append((user1, user2, weight))
    return sorted(rows, key=lambda r: (-r[2], r[0], r[1]))


def format_rows(rows):
    return "\n".join(f"{u1},{u2},{weight}" for u1, u2, weight in rows)


def run_script(page, size):
    return subprocess.run(
        [SCRIPT_PATH, str(page), str(size)],
        capture_output=True,
        text=True,
        timeout=30,
    )


def test_script_exists_and_executable():
    """Test that the analyze_graph.sh script exists and is executable."""
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_script_execution_page_1():
    """Test the script output for page 1, size 3."""
    result = run_script(1, 3)
    assert result.returncode == 0, f"Script failed with error: {result.stderr}"

    expected_output = "1,4,3\n2,4,3\n1,2,2"
    actual_output = result.stdout.strip()
    assert actual_output == expected_output, f"Expected output:\n{expected_output}\nGot:\n{actual_output}"


def test_script_execution_page_2():
    """Test the script output for page 2, size 3."""
    result = run_script(2, 3)
    assert result.returncode == 0, f"Script failed with error: {result.stderr}"

    expected_output = "1,3,2\n1,5,2\n3,4,2"
    actual_output = result.stdout.strip()
    assert actual_output == expected_output, f"Expected output:\n{expected_output}\nGot:\n{actual_output}"


def test_database_exists():
    """Test that the graph.db database was created."""
    assert os.path.exists(DB_PATH), f"Database {DB_PATH} was not created."
    assert os.path.isfile(DB_PATH), f"{DB_PATH} is not a file."


def test_database_schema_and_indexes():
    """Test that the transactions table has indexes and user_graph is materialized."""
    assert os.path.exists(DB_PATH), f"Database {DB_PATH} is missing."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT count(*) FROM sqlite_master WHERE type='table' AND name='transactions';")
    assert cursor.fetchone()[0] == 1, "Table 'transactions' does not exist in the database."

    cursor.execute("SELECT count(*) FROM sqlite_master WHERE type='index' AND tbl_name='transactions';")
    index_count = cursor.fetchone()[0]
    assert index_count >= 1, "No indexes were created on the 'transactions' table."

    cursor.execute("SELECT count(*) FROM sqlite_master WHERE type='table' AND name='user_graph';")
    assert cursor.fetchone()[0] == 1, "Table 'user_graph' was not materialized."

    conn.close()


def test_transactions_were_imported_from_csv():
    """Ensure the database contains every source transaction, not fabricated graph data."""
    expected = Counter(read_csv_records(CSV_PATH))
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute("SELECT user_id, product_id, timestamp FROM transactions").fetchall()
    finally:
        conn.close()
    actual = Counter(tuple(str(value) for value in row) for row in rows)
    assert actual == expected, "The transactions table is not an exact import of transactions.csv."


def test_user_graph_content():
    """Test that the user_graph table contains the correct materialized data."""
    assert os.path.exists(DB_PATH), f"Database {DB_PATH} is missing."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    try:
        cursor.execute("SELECT user1, user2, weight FROM user_graph ORDER BY weight DESC, user1 ASC, user2 ASC;")
        rows = cursor.fetchall()
    except sqlite3.OperationalError as e:
        pytest.fail(f"Failed to query user_graph: {e}")
    finally:
        conn.close()

    expected_rows = [
        (1, 4, 3),
        (2, 4, 3),
        (1, 2, 2),
        (1, 3, 2),
        (1, 5, 2),
        (3, 4, 2),
        (4, 5, 2)
    ]

    rows_str = [(str(r[0]), str(r[1]), int(r[2])) for r in rows]
    expected_rows_str = [(str(r[0]), str(r[1]), int(r[2])) for r in expected_rows]

    assert rows_str == expected_rows_str, f"Materialized user_graph data is incorrect. Expected {expected_rows_str}, got {rows_str}"


def test_fresh_randomized_import_projection_pagination_and_materialization():
    """Exercise a fresh database using data and answers generated at verification time."""
    original_csv = open(CSV_PATH, "rb").read()
    db_backup = "/tmp/original_graph.db"
    had_db = os.path.isfile(DB_PATH)
    if had_db:
        shutil.copy2(DB_PATH, db_backup)

    for suffix in ("", "-wal", "-shm", "-journal"):
        try:
            os.remove(DB_PATH + suffix)
        except FileNotFoundError:
            pass

    users = sorted(secrets.SystemRandom().sample(range(100, 1000), 5))
    product = {name: f"{name}_{secrets.token_hex(8)}" for name in "ABCD"}
    purchases = {
        users[0]: ["A", "B", "C", "D"],
        users[1]: ["A", "B", "C", "A"],  # duplicate tests COUNT(DISTINCT product_id)
        users[2]: ["A", "B", "D"],
        users[3]: ["B", "C"],
        users[4]: ["C", "D"],
    }

    generated = []
    n = 1
    for user_id, names in purchases.items():
        for name in names:
            generated.append((str(user_id), product[name], f"2026-01-{n:02d}T00:00:00"))
            n += 1

    out = io.StringIO()
    writer = csv.writer(out, lineterminator="\n")
    writer.writerow(["user_id", "product_id", "timestamp"])
    writer.writerows(generated)

    try:
        with open(CSV_PATH, "w", newline="") as f:
            f.write(out.getvalue())

        expected = derive_graph(generated)
        result = run_script(1, 100)
        assert result.returncode == 0, f"Fresh randomized run failed: {result.stderr}"
        assert result.stdout.strip() == format_rows(expected)

        page_result = run_script(2, 2)
        assert page_result.returncode == 0, f"Randomized pagination run failed: {page_result.stderr}"
        assert page_result.stdout.strip() == format_rows(expected[2:4])

        conn = sqlite3.connect(DB_PATH)
        try:
            table_names = {r[0] for r in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
            assert "transactions" in table_names
            assert "user_graph" in table_names

            index_count = conn.execute(
                "SELECT count(*) FROM sqlite_master WHERE type='index' AND tbl_name='transactions'"
            ).fetchone()[0]
            assert index_count >= 1, "Freshly imported transactions table has no index."

            imported = conn.execute(
                "SELECT user_id, product_id, timestamp FROM transactions"
            ).fetchall()
            assert Counter(tuple(str(v) for v in row) for row in imported) == Counter(generated)

            graph_rows = conn.execute(
                "SELECT user1, user2, weight FROM user_graph "
                "ORDER BY weight DESC, user1 ASC, user2 ASC"
            ).fetchall()
            normalized = [(str(a), str(b), int(w)) for a, b, w in graph_rows]
            assert normalized == expected
            assert all(a < b and w >= 2 for a, b, w in normalized)
        finally:
            conn.close()

        # Once materialized, changing the CSV must not cause a subsequent call to recompute it.
        with open(CSV_PATH, "a") as f:
            f.write(f"{users[3]},{product['D']},2026-02-01T00:00:00\n")
            f.write(f"{users[4]},{product['B']},2026-02-02T00:00:00\n")
        repeat = run_script(1, 100)
        assert repeat.returncode == 0, f"Repeat run failed: {repeat.stderr}"
        assert repeat.stdout.strip() == format_rows(expected), "user_graph was recomputed instead of reused."
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
        for suffix in ("", "-wal", "-shm", "-journal"):
            try:
                os.remove(DB_PATH + suffix)
            except FileNotFoundError:
                pass
        if had_db:
            shutil.move(db_backup, DB_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

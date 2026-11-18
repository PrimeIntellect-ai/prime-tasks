#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import sqlite3
import stat
import subprocess
import tempfile

import pytest

DB_PATH = "/home/user/store.db"
PLAN_PATH = "/home/user/plan.txt"
JSON_PATH = "/home/user/top_pending.json"
SCRIPT_PATH = "/home/user/export_pending.py"

QUERY = """SELECT orders.id, customers.name, customers.email, orders.total, orders.created_at FROM orders JOIN customers ON orders.customer_id = customers.id WHERE orders.status = 'pending' ORDER BY orders.created_at DESC LIMIT 20;"""
EXPECTED_KEYS = {"order_id", "customer_name", "customer_email", "order_total", "order_date"}


def load_json_export():
    assert os.path.exists(JSON_PATH), f"JSON export file {JSON_PATH} is missing."
    with open(JSON_PATH, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {JSON_PATH} is not valid JSON.")


def assert_export_matches(data, expected_rows):
    assert isinstance(data, list), "JSON root should be an array (list)."
    assert len(data) == len(expected_rows), (
        f"Expected {len(expected_rows)} items in the JSON array, found {len(data)}."
    )

    for i, (expected, actual) in enumerate(zip(expected_rows, data)):
        assert isinstance(actual, dict), f"Item at index {i} is not a JSON object."
        assert set(actual.keys()) == EXPECTED_KEYS, (
            f"Item at index {i} has incorrect keys. Expected {EXPECTED_KEYS}, got {set(actual.keys())}."
        )
        assert isinstance(actual["order_id"], int), f"order_id at index {i} should be an integer."
        assert isinstance(actual["customer_name"], str), f"customer_name at index {i} should be a string."
        assert isinstance(actual["customer_email"], str), f"customer_email at index {i} should be a string."
        assert isinstance(actual["order_total"], (int, float)), f"order_total at index {i} should be a float."
        assert isinstance(actual["order_date"], str), f"order_date at index {i} should be a string."
        assert actual["order_id"] == expected[0], f"Mismatch in order_id at index {i}."
        assert actual["customer_name"] == expected[1], f"Mismatch in customer_name at index {i}."
        assert actual["customer_email"] == expected[2], f"Mismatch in customer_email at index {i}."
        assert abs(actual["order_total"] - expected[3]) < 0.01, f"Mismatch in order_total at index {i}."
        assert actual["order_date"] == expected[4], f"Mismatch in order_date at index {i}."


def run_export_script():
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"{SCRIPT_PATH} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_export_script_exists_and_runs():
    assert os.path.exists(SCRIPT_PATH), f"Export script {SCRIPT_PATH} is missing."
    assert stat.S_ISREG(os.stat(SCRIPT_PATH).st_mode), f"{SCRIPT_PATH} is not a regular file."
    run_export_script()
    assert os.path.exists(JSON_PATH), f"Script did not generate {JSON_PATH}."


def test_index_exists_and_correct():
    """Verify that the composite index was created on the correct table and columns."""
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} is missing."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name, tbl_name FROM sqlite_master WHERE type='index' AND name='idx_orders_status_date';")
    index_info = cursor.fetchone()
    assert index_info is not None, "Index 'idx_orders_status_date' does not exist."
    assert index_info[1] == "orders", "Index 'idx_orders_status_date' is not on the 'orders' table."

    cursor.execute("PRAGMA index_info('idx_orders_status_date');")
    columns = [row[2] for row in cursor.fetchall()]
    assert len(columns) == 2, f"Index should have 2 columns, found {len(columns)}."
    assert columns[0] == "status", f"First column in index should be 'status', found '{columns[0]}'."
    assert columns[1] == "created_at", f"Second column in index should be 'created_at', found '{columns[1]}'."

    conn.close()


def test_explain_query_plan_output():
    """Verify that the exact EXPLAIN QUERY PLAN output was saved and uses the index."""
    assert os.path.exists(PLAN_PATH), f"Plan output file {PLAN_PATH} is missing."

    with open(PLAN_PATH, "r") as f:
        plan_content = f.read()

    assert "idx_orders_status_date" in plan_content, (
        "The query plan in plan.txt does not show usage of 'idx_orders_status_date'."
    )

    expected = subprocess.run(
        ["sqlite3", DB_PATH, "EXPLAIN QUERY PLAN " + QUERY],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    ).stdout
    assert plan_content == expected, "plan.txt does not contain the exact EXPLAIN QUERY PLAN output."


def test_json_export_structure_and_data():
    """Verify the exported JSON file has the correct structure and data."""
    data = load_json_export()

    assert isinstance(data, list), "JSON root should be an array (list)."
    assert len(data) == 20, f"Expected 20 items in the JSON array, found {len(data)}."

    for i, item in enumerate(data):
        assert isinstance(item, dict), f"Item at index {i} is not a JSON object."
        item_keys = set(item.keys())
        assert item_keys == EXPECTED_KEYS, (
            f"Item at index {i} has incorrect keys. Expected {EXPECTED_KEYS}, got {item_keys}."
        )
        assert isinstance(item["order_id"], int), f"order_id at index {i} should be an integer."
        assert isinstance(item["customer_name"], str), f"customer_name at index {i} should be a string."
        assert isinstance(item["customer_email"], str), f"customer_email at index {i} should be a string."
        assert isinstance(item["order_total"], (int, float)), f"order_total at index {i} should be a float."
        assert isinstance(item["order_date"], str), f"order_date at index {i} should be a string."


def test_json_data_correctness():
    """Verify the JSON data matches the actual expected query results."""
    conn = sqlite3.connect(DB_PATH)
    expected_rows = conn.execute(QUERY).fetchall()
    conn.close()

    assert len(expected_rows) == 20, "The database must still contain at least 20 pending orders."
    data = load_json_export()
    assert_export_matches(data, expected_rows)


def test_script_uses_database_query_on_fresh_data():
    """Exercise the submitted pipeline against verifier-generated, unpredictable rows."""
    fd, backup_path = tempfile.mkstemp(prefix="store-backup-", suffix=".db")
    os.close(fd)

    source = sqlite3.connect(DB_PATH)
    backup = sqlite3.connect(backup_path)
    source.backup(backup)
    backup.close()
    source.close()

    token = secrets.token_hex(8)
    try:
        conn = sqlite3.connect(DB_PATH)
        cur = conn.cursor()
        cur.execute("UPDATE orders SET status = 'shipped'")
        max_customer = cur.execute("SELECT COALESCE(MAX(id), 0) FROM customers").fetchone()[0]
        max_order = cur.execute("SELECT COALESCE(MAX(id), 0) FROM orders").fetchone()[0]
        customer_id = max_customer + 1
        cur.execute(
            "INSERT INTO customers(id, name, email) VALUES (?, ?, ?)",
            (customer_id, "Verifier " + token, token + "@example.invalid"),
        )
        for i in range(25):
            cur.execute(
                "INSERT INTO orders(id, customer_id, status, total, created_at) VALUES (?, ?, 'pending', ?, ?)",
                (
                    max_order + i + 1,
                    customer_id,
                    float(1000 + i) + 0.25,
                    f"2099-12-{25 - i:02d} 12:34:{i:02d}",
                ),
            )
        conn.commit()
        expected_rows = cur.execute(QUERY).fetchall()
        conn.close()

        assert len(expected_rows) == 20
        run_export_script()
        data = load_json_export()
        assert_export_matches(data, expected_rows)
    finally:
        for suffix in ("", "-wal", "-shm"):
            path = DB_PATH + suffix
            if os.path.exists(path):
                os.remove(path)
        shutil.move(backup_path, DB_PATH)
        os.chmod(DB_PATH, 0o777)

        # Leave the requested export corresponding to the restored database.
        if os.path.exists(SCRIPT_PATH):
            subprocess.run(
                ["python3", SCRIPT_PATH],
                cwd="/home/user",
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=30,
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
import runpy
import secrets
import shutil
import sqlite3
import urllib.parse

import pytest

DB_PATH = "/home/user/ecommerce.db"
SCRIPT_PATH = "/home/user/export_backup.py"
BACKUP_PATH = "/home/user/backup_data.json"
DB_COPY = "/tmp/ecommerce.db.verifier-backup"

REAL_CONNECT = sqlite3.connect
EXPECTED_DATA = None
STATEMENTS = []
WRITE_ATTEMPTED = False


def get_expected_data():
    """Derive the expected JSON structure directly from the database."""
    conn = REAL_CONNECT(DB_PATH)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    cursor.execute("""
        SELECT DISTINCT c.id, c.name, c.email
        FROM customers c
        JOIN orders o ON c.id = o.customer_id
        WHERE o.status = 'completed'
        ORDER BY c.id ASC
    """)
    customers = cursor.fetchall()

    expected_output = []
    for cust in customers:
        cust_id = cust['id']
        cursor.execute("""
            SELECT id, order_date
            FROM orders
            WHERE customer_id = ? AND status = 'completed'
            ORDER BY id ASC
        """, (cust_id,))
        orders = cursor.fetchall()

        orders_list = []
        total_spent = 0.0
        for ord_row in orders:
            order_id = ord_row['id']
            cursor.execute("""
                SELECT product_name, price
                FROM items
                WHERE order_id = ?
                ORDER BY product_name ASC
            """, (order_id,))
            items = cursor.fetchall()

            items_list = []
            for item in items:
                items_list.append({
                    "product_name": item['product_name'],
                    "price": float(item['price'])
                })
                total_spent += float(item['price'])

            orders_list.append({
                "order_id": order_id,
                "order_date": ord_row['order_date'],
                "items": items_list
            })

        expected_output.append({
            "customer_id": cust_id,
            "name": cust['name'],
            "email": cust['email'],
            "total_spent": total_spent,
            "orders": orders_list
        })

    conn.close()
    return expected_output


def file_digest(path):
    if not os.path.exists(path):
        return None
    with open(path, "rb") as f:
        return hashlib.sha256(f.read()).hexdigest()


def db_state():
    return {
        path: file_digest(path)
        for path in (DB_PATH, DB_PATH + "-journal", DB_PATH + "-wal", DB_PATH + "-shm")
    }


WRITE_ACTIONS = {
    getattr(sqlite3, name)
    for name in (
        "SQLITE_INSERT", "SQLITE_UPDATE", "SQLITE_DELETE",
        "SQLITE_CREATE_INDEX", "SQLITE_CREATE_TABLE", "SQLITE_CREATE_TEMP_INDEX",
        "SQLITE_CREATE_TEMP_TABLE", "SQLITE_CREATE_TEMP_TRIGGER",
        "SQLITE_CREATE_TEMP_VIEW", "SQLITE_CREATE_TRIGGER", "SQLITE_CREATE_VIEW",
        "SQLITE_DROP_INDEX", "SQLITE_DROP_TABLE", "SQLITE_DROP_TEMP_INDEX",
        "SQLITE_DROP_TEMP_TABLE", "SQLITE_DROP_TEMP_TRIGGER", "SQLITE_DROP_TEMP_VIEW",
        "SQLITE_DROP_TRIGGER", "SQLITE_DROP_VIEW", "SQLITE_ALTER_TABLE",
        "SQLITE_REINDEX", "SQLITE_ANALYZE", "SQLITE_ATTACH", "SQLITE_DETACH"
    )
    if hasattr(sqlite3, name)
}


def trace_statement(sql):
    STATEMENTS.append(sql)


def authorize(action, arg1, arg2, database, source):
    global WRITE_ATTEMPTED
    if action in WRITE_ACTIONS:
        WRITE_ATTEMPTED = True
        return sqlite3.SQLITE_DENY
    return sqlite3.SQLITE_OK


class TrackingConnection(sqlite3.Connection):
    def set_trace_callback(self, callback):
        raise RuntimeError("The verifier's SQL trace callback may not be replaced")

    def set_authorizer(self, callback):
        raise RuntimeError("The verifier's read-only authorizer may not be replaced")


def monitored_connect(database, *args, **kwargs):
    try:
        supplied_path = os.path.realpath(os.fspath(database))
    except TypeError:
        raise AssertionError("The script must connect to /home/user/ecommerce.db")

    assert supplied_path == os.path.realpath(DB_PATH), \
        "The script must connect to /home/user/ecommerce.db"
    assert len(args) < 5, "A custom SQLite connection factory is not permitted"

    kwargs.pop("uri", None)
    kwargs["factory"] = TrackingConnection
    uri = "file:" + urllib.parse.quote(os.path.realpath(DB_PATH), safe="/") + "?mode=ro"
    conn = REAL_CONNECT(uri, *args, uri=True, **kwargs)
    sqlite3.Connection.set_trace_callback(conn, trace_statement)
    sqlite3.Connection.set_authorizer(conn, authorize)
    return conn


@pytest.fixture(scope="session")
def execute_submission():
    global EXPECTED_DATA, WRITE_ATTEMPTED

    shutil.copy2(DB_PATH, DB_COPY)
    try:
        # Add unpredictable but ordinary rows so a precomputed backup cannot pass.
        token = secrets.randbelow(1000000)
        customer_id = 10000000 + token
        order_id_1 = 20000000 + token * 2
        order_id_2 = order_id_1 + 1
        pending_order_id = order_id_1 + 2
        item_id = 30000000 + token * 4

        conn = REAL_CONNECT(DB_PATH)
        conn.execute("INSERT INTO customers VALUES (?, ?, ?)",
                     (customer_id, f"Verifier Customer {token}", f"verify{token}@example.com"))
        conn.executemany("INSERT INTO orders VALUES (?, ?, ?, ?)", [
            (order_id_1, customer_id, "2026-01-10", "completed"),
            (order_id_2, customer_id, "2026-01-11", "completed"),
            (pending_order_id, customer_id, "2026-01-12", "pending")
        ])
        conn.executemany("INSERT INTO items VALUES (?, ?, ?, ?)", [
            (item_id, order_id_1, f"Alpha Product {token}", 10.25),
            (item_id + 1, order_id_1, f"Zulu Product {token}", 7.5),
            (item_id + 2, order_id_2, f"Middle Product {token}", 3.75),
            (item_id + 3, pending_order_id, f"Ignored Product {token}", 999.0)
        ])
        conn.commit()
        conn.close()

        EXPECTED_DATA = get_expected_data()
        before_state = db_state()
        if os.path.exists(BACKUP_PATH):
            os.remove(BACKUP_PATH)

        STATEMENTS.clear()
        WRITE_ATTEMPTED = False
        sqlite3.connect = monitored_connect
        try:
            try:
                runpy.run_path(SCRIPT_PATH, run_name="__main__")
            except SystemExit as exc:
                assert exc.code in (None, 0), f"The export script exited with status {exc.code}"
        finally:
            sqlite3.connect = REAL_CONNECT

        assert not WRITE_ATTEMPTED, "The export script attempted to modify the database"
        assert db_state() == before_state, "The export script modified the database or its sidecar files"
        assert len(STATEMENTS) == 1, \
            f"The export script must execute exactly one SQL query; observed {len(STATEMENTS)} statements"
        yield
    finally:
        sqlite3.connect = REAL_CONNECT
        if os.path.exists(DB_COPY):
            os.replace(DB_COPY, DB_PATH)
        for suffix in ("-journal", "-wal", "-shm"):
            sidecar = DB_PATH + suffix
            if os.path.exists(sidecar):
                os.remove(sidecar)


def test_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"The script {SCRIPT_PATH} does not exist."


def test_backup_file_exists(execute_submission):
    assert os.path.isfile(BACKUP_PATH), f"The backup file {BACKUP_PATH} does not exist."


def test_backup_data_content_and_format(execute_submission):
    assert os.path.isfile(BACKUP_PATH), f"The backup file {BACKUP_PATH} does not exist."

    with open(BACKUP_PATH, 'r') as f:
        raw_content = f.read()

    try:
        actual_data = json.loads(raw_content)
    except json.JSONDecodeError:
        pytest.fail(f"The file {BACKUP_PATH} does not contain valid JSON.")

    expected_data = EXPECTED_DATA
    assert actual_data == expected_data, \
        "The JSON data does not match the expected output derived from the database."

    expected_raw = json.dumps(expected_data, indent=2)
    assert raw_content.strip() == expected_raw.strip(), \
        "The JSON file is not properly formatted with 2 spaces indentation."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

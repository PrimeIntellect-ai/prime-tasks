#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import sqlite3
import subprocess
import tempfile

DB_PATH = "/home/user/ecommerce.db"
SCRIPT_PATH = "/home/user/analyze.sh"
REPORT_PATH = "/home/user/report.json"

EXPECTED_ROWS = {
    "customers": [
        (1, "Alice", "Premium"),
        (2, "Bob", "Standard"),
        (3, "Charlie", "Premium"),
        (4, "David", "Standard"),
    ],
    "products": [
        (101, "Laptop", "Electronics", 1200.0),
        (102, "Mouse", "Electronics", 25.0),
        (103, "Desk", "Furniture", 300.0),
        (104, "Headphones", "Electronics", 150.0),
    ],
    "transactions": [
        (1001, 1, 101, "2023-05-14", 1),
        (1002, 2, 102, "2023-06-20", 2),
        (1003, 3, 104, "2023-11-05", 3),
        (1004, 4, 103, "2023-12-01", 1),
        (1005, 1, 102, "2024-01-15", 1),
        (1006, 2, 101, "2022-12-25", 1),
    ],
}

EXPECTED_COLUMNS = {
    "customers": ["customer_id", "name", "segment"],
    "products": ["product_id", "name", "category", "price"],
    "transactions": ["transaction_id", "customer_id", "product_id", "transaction_date", "quantity"],
}


def test_database_exists():
    assert os.path.isfile(DB_PATH), f"{DB_PATH} does not exist"


def test_tables_exist():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
    tables = [row[0] for row in cursor.fetchall()]
    conn.close()

    assert "customers" in tables, "Table 'customers' is missing"
    assert "products" in tables, "Table 'products' is missing"
    assert "transactions" in tables, "Table 'transactions' is missing"


def test_imported_schemas_and_rows():
    conn = sqlite3.connect(DB_PATH)
    try:
        for table, expected_columns in EXPECTED_COLUMNS.items():
            info = conn.execute(f'PRAGMA table_info("{table}")').fetchall()
            assert [row[1] for row in info] == expected_columns, f"Incorrect schema columns for {table}"
            declared = {row[1]: (row[2] or "").upper() for row in info}
            for column in expected_columns:
                assert declared[column], f"Column {table}.{column} has no inferred type"

        assert "INT" in declared_type(conn, "customers", "customer_id")
        assert "TEXT" in declared_type(conn, "customers", "name")
        assert "TEXT" in declared_type(conn, "customers", "segment")
        assert "INT" in declared_type(conn, "products", "product_id")
        assert "TEXT" in declared_type(conn, "products", "name")
        assert "TEXT" in declared_type(conn, "products", "category")
        assert any(token in declared_type(conn, "products", "price") for token in ("REAL", "FLOA", "DOUB", "NUM", "DEC"))
        assert "INT" in declared_type(conn, "transactions", "transaction_id")
        assert "INT" in declared_type(conn, "transactions", "customer_id")
        assert "INT" in declared_type(conn, "transactions", "product_id")
        assert any(token in declared_type(conn, "transactions", "transaction_date") for token in ("TEXT", "CHAR", "CLOB", "DATE"))
        assert "INT" in declared_type(conn, "transactions", "quantity")

        for table, expected in EXPECTED_ROWS.items():
            columns = EXPECTED_COLUMNS[table]
            order_column = columns[0]
            rows = conn.execute(
                f'SELECT {", ".join(columns)} FROM "{table}" ORDER BY "{order_column}"'
            ).fetchall()
            assert rows == expected, f"Imported rows in {table} do not match the CSV data"
    finally:
        conn.close()


def declared_type(conn, table, column):
    for row in conn.execute(f'PRAGMA table_info("{table}")'):
        if row[1] == column:
            return (row[2] or "").upper()
    raise AssertionError(f"Missing column {table}.{column}")


def test_indexes_exist():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='index';")
    indexes = [row[0] for row in cursor.fetchall()]

    assert "idx_transactions_date" in indexes, "Index 'idx_transactions_date' is missing"
    assert "idx_products_category" in indexes, "Index 'idx_products_category' is missing"
    assert "idx_transactions_customer" in indexes, "Index 'idx_transactions_customer' is missing"

    expected = {
        "idx_transactions_date": ("transactions", ["transaction_date"]),
        "idx_products_category": ("products", ["category"]),
        "idx_transactions_customer": ("transactions", ["customer_id"]),
    }
    for index_name, (table, columns) in expected.items():
        row = conn.execute(
            "SELECT tbl_name FROM sqlite_master WHERE type='index' AND name=?",
            (index_name,),
        ).fetchone()
        assert row is not None and row[0] == table, f"{index_name} is on the wrong table"
        actual_columns = [r[2] for r in conn.execute(f'PRAGMA index_info("{index_name}")')]
        assert actual_columns == columns, f"{index_name} must index {columns}"
    conn.close()


def test_script_executable_and_runs():
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} does not exist"
    assert os.access(SCRIPT_PATH, os.X_OK), f"{SCRIPT_PATH} is not executable"
    with open(SCRIPT_PATH, "r", errors="replace") as f:
        script_text = f.read()
    assert "sqlite3" in script_text, "analyze.sh must use sqlite3 for database operations"

    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)

    result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed to run. Return code: {result.returncode}, Stderr: {result.stderr}"
    assert os.path.isfile(REPORT_PATH), f"Script did not create {REPORT_PATH}"


def test_report_json_content():
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} does not exist"

    with open(REPORT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{REPORT_PATH} does not contain valid JSON"

    expected_data = [
        {"segment": "Premium", "total_revenue": 1650.0},
        {"segment": "Standard", "total_revenue": 50.0},
    ]

    assert isinstance(data, list), "JSON output should be a list"
    assert len(data) == len(expected_data), f"Expected {len(expected_data)} items, got {len(data)}"
    assert data == expected_data, f"JSON content is incorrect. Expected {expected_data}, got {data}"


def derive_expected(conn):
    customers = {row[0]: row[1] for row in conn.execute("SELECT customer_id, segment FROM customers")}
    products = {row[0]: (row[1], float(row[2])) for row in conn.execute("SELECT product_id, category, price FROM products")}
    totals = {}
    for customer_id, product_id, transaction_date, quantity in conn.execute(
        "SELECT customer_id, product_id, transaction_date, quantity FROM transactions"
    ):
        category, price = products[product_id]
        if category == "Electronics" and "2023-01-01" <= transaction_date <= "2023-12-31":
            segment = customers[customer_id]
            totals[segment] = totals.get(segment, 0.0) + float(quantity) * price
    return [
        {"segment": segment, "total_revenue": revenue}
        for segment, revenue in sorted(totals.items(), key=lambda item: (-item[1], item[0]))
    ]


def test_script_queries_changed_database_instead_of_emitting_fixed_report():
    fd, backup_path = tempfile.mkstemp(prefix="ecommerce-backup-", suffix=".db")
    os.close(fd)
    shutil.copy2(DB_PATH, backup_path)
    old_report = None
    if os.path.exists(REPORT_PATH):
        with open(REPORT_PATH, "rb") as f:
            old_report = f.read()

    high = secrets.randbelow(700) + 1100
    medium = secrets.randbelow(70) + 120
    low = secrets.randbelow(8) + 11

    try:
        conn = sqlite3.connect(DB_PATH)
        conn.execute("DELETE FROM transactions")
        conn.execute("DELETE FROM products")
        conn.execute("DELETE FROM customers")
        conn.executemany("INSERT INTO customers VALUES (?, ?, ?)", [
            (11, "Dynamic One", "Enterprise"),
            (12, "Dynamic Two", "Consumer"),
            (13, "Dynamic Three", "Startup"),
            (14, "Dynamic Four", "Enterprise"),
        ])
        conn.executemany("INSERT INTO products VALUES (?, ?, ?, ?)", [
            (201, "Server", "Electronics", high),
            (202, "Router", "Electronics", medium),
            (203, "Cable", "Electronics", low),
            (204, "Chair", "Furniture", high * 3),
        ])
        conn.executemany("INSERT INTO transactions VALUES (?, ?, ?, ?, ?)", [
            (2001, 11, 201, "2023-01-01", 2),
            (2002, 12, 202, "2023-08-17", 2),
            (2003, 13, 203, "2023-12-31", 1),
            (2004, 14, 203, "2023-06-10", 3),
            (2005, 11, 204, "2023-05-05", 20),
            (2006, 12, 201, "2022-12-31", 20),
            (2007, 13, 201, "2024-01-01", 20),
        ])
        conn.commit()
        expected = derive_expected(conn)
        conn.close()

        if os.path.exists(REPORT_PATH):
            os.remove(REPORT_PATH)
        result = subprocess.run([SCRIPT_PATH], capture_output=True, text=True)
        assert result.returncode == 0, f"Script failed on changed database: {result.stderr}"
        assert os.path.isfile(REPORT_PATH), "Script did not recreate report.json on changed database"
        with open(REPORT_PATH, "r") as f:
            actual = json.load(f)
        assert actual == expected, f"Script did not derive the report from the database. Expected {expected}, got {actual}"
    finally:
        shutil.copy2(backup_path, DB_PATH)
        os.remove(backup_path)
        if old_report is None:
            if os.path.exists(REPORT_PATH):
                os.remove(REPORT_PATH)
        else:
            with open(REPORT_PATH, "wb") as f:
                f.write(old_report)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sqlite3
import tempfile
from collections import Counter


def quote_identifier(name):
    return '"' + name.replace('"', '""') + '"'


def user_schema(conn):
    return conn.execute(
        "SELECT type, name, tbl_name, sql FROM sqlite_master "
        "WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name"
    ).fetchall()


def table_contents(conn):
    table_names = [
        row[0] for row in conn.execute(
            "SELECT name FROM sqlite_master "
            "WHERE type='table' AND name NOT LIKE 'sqlite_%' ORDER BY name"
        ).fetchall()
    ]
    return {
        name: Counter(conn.execute(f"SELECT * FROM {quote_identifier(name)}").fetchall())
        for name in table_names
    }


def test_extracted_csv_exists():
    csv_path = "/home/user/transactions.csv"
    assert os.path.isfile(csv_path), f"Expected extracted file {csv_path} is missing."


def test_database_and_data():
    db_path = "/home/user/metrics.db"
    assert os.path.isfile(db_path), f"Expected database file {db_path} is missing."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Check if table exists
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='category_metrics';")
    assert cursor.fetchone() is not None, "Table 'category_metrics' does not exist in the database."

    # Check schema
    cursor.execute("PRAGMA table_info(category_metrics);")
    table_info = cursor.fetchall()
    columns = {row[1]: row[2].upper() for row in table_info}

    expected_columns = {
        "category": "TEXT",
        "total_volume": "INTEGER",
        "total_value": "REAL",
        "vwap": "REAL"
    }

    for col, col_type in expected_columns.items():
        assert col in columns, f"Column '{col}' is missing from 'category_metrics'."
        assert columns[col].startswith(col_type), f"Column '{col}' has type {columns[col]}, expected {col_type}."

    actual_schema = [(row[1], row[2].upper()) for row in table_info]
    expected_schema = list(expected_columns.items())
    assert actual_schema == expected_schema, (
        f"category_metrics columns must be exactly {expected_schema}, got {actual_schema}."
    )

    # Check data and sorting
    cursor.execute("SELECT category, total_volume, total_value, vwap FROM category_metrics;")
    rows = cursor.fetchall()

    expected_rows = [
        ("Alpha", 150, 1650.00, 11.00),
        ("Beta", 300, 1450.00, 4.83),
        ("Delta", 60, 1000.00, 16.67),
        ("Gamma", 10, 1000.00, 100.00)
    ]

    assert len(rows) == len(expected_rows), f"Expected {len(expected_rows)} rows, but got {len(rows)}."

    for i, (actual, expected) in enumerate(zip(rows, expected_rows)):
        assert actual[0] == expected[0], f"Row {i+1}: Expected category {expected[0]}, got {actual[0]}. (Check sorting or parsing)"
        assert actual[1] == expected[1], f"Row {i+1} ({actual[0]}): Expected total_volume {expected[1]}, got {actual[1]}."
        assert abs(actual[2] - expected[2]) < 0.001, f"Row {i+1} ({actual[0]}): Expected total_value {expected[2]}, got {actual[2]}."
        assert abs(actual[3] - expected[3]) < 0.001, f"Row {i+1} ({actual[0]}): Expected vwap {expected[3]}, got {actual[3]}."

    conn.close()


def test_sql_export_exists_and_restores_entire_database():
    sql_path = "/home/user/export.sql"
    db_path = "/home/user/metrics.db"
    assert os.path.isfile(sql_path), f"Expected SQL export file {sql_path} is missing."

    with open(sql_path, "r", encoding="utf-8") as f:
        content = f.read()

    # Preserve the original checks.
    assert "CREATE TABLE" in content and "category_metrics" in content, "The SQL export file does not appear to contain the dump of 'category_metrics'."
    assert "INSERT INTO" in content, "The SQL export file does not appear to contain the data inserts."

    # A sqlite3 .dump is a transaction-wrapped SQL dump, not merely keyword text.
    stripped = content.strip()
    assert stripped.startswith("PRAGMA foreign_keys=OFF;"), "Export is not standard SQLite dump output."
    assert "BEGIN TRANSACTION;" in content, "SQLite dump is missing its transaction start."
    assert stripped.endswith("COMMIT;"), "SQLite dump is missing its final COMMIT."

    source = sqlite3.connect(db_path)
    expected_schema = user_schema(source)
    expected_contents = table_contents(source)
    source.close()

    fd, restored_path = tempfile.mkstemp(suffix=".db")
    os.close(fd)
    try:
        restored = sqlite3.connect(restored_path)

        # Standard dumps do not need access to any other database file.
        def authorizer(action, arg1, arg2, db_name, trigger_name):
            if action in (sqlite3.SQLITE_ATTACH, sqlite3.SQLITE_DETACH):
                return sqlite3.SQLITE_DENY
            return sqlite3.SQLITE_OK

        restored.set_authorizer(authorizer)
        try:
            restored.executescript(content)
        except sqlite3.Error as exc:
            raise AssertionError(f"export.sql is not a valid restorable SQLite dump: {exc}")

        actual_schema = user_schema(restored)
        actual_contents = table_contents(restored)
        restored.close()

        assert actual_schema == expected_schema, (
            "Restoring export.sql does not recreate the entire database schema."
        )
        assert actual_contents == expected_contents, (
            "Restoring export.sql does not recreate all database table data."
        )
    finally:
        if os.path.exists(restored_path):
            os.remove(restored_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

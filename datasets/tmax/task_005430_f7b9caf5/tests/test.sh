#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import shutil
import sqlite3
import subprocess
from decimal import Decimal, InvalidOperation

import pytest

HOME = "/home/user"
DATA = os.path.join(HOME, "data")
DB = os.path.join(HOME, "store.db")


def test_files_exist():
    expected_files = [
        "/home/user/build_db.py",
        "/home/user/store.db",
        "/home/user/indexes.sql",
        "/home/user/query.sql",
        "/home/user/top_spenders.csv"
    ]
    for file_path in expected_files:
        assert os.path.isfile(file_path), f"Expected file {file_path} is missing."


def test_database_schema():
    db_path = "/home/user/store.db"
    assert os.path.isfile(db_path), f"Database file {db_path} does not exist."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
    tables = {row[0] for row in cursor.fetchall()}
    expected_tables = {"clients", "items", "purchases", "purchase_lines"}
    assert expected_tables.issubset(tables), f"Database is missing expected tables. Found: {tables}"

    cursor.execute("PRAGMA foreign_key_list(purchases);")
    purchases_fks = cursor.fetchall()
    assert len(purchases_fks) >= 1, "No foreign keys defined for 'purchases' table."
    fk_clients = [fk for fk in purchases_fks if fk[2] == "clients"]
    assert fk_clients, "No foreign key referencing 'clients' found in 'purchases' table."

    cursor.execute("PRAGMA foreign_key_list(purchase_lines);")
    lines_fks = cursor.fetchall()
    assert len(lines_fks) >= 2, "Expected at least 2 foreign keys in 'purchase_lines' table."

    fk_purchases = [fk for fk in lines_fks if fk[2] == "purchases"]
    fk_items = [fk for fk in lines_fks if fk[2] == "items"]

    assert fk_purchases, "No foreign key referencing 'purchases' found in 'purchase_lines' table."
    assert fk_items, "No foreign key referencing 'items' found in 'purchase_lines' table."

    conn.close()


def test_indexes_created():
    sql_path = "/home/user/indexes.sql"
    assert os.path.isfile(sql_path), f"File {sql_path} does not exist."

    with open(sql_path, 'r') as f:
        content = f.read().lower()
        assert "create " in content and "index " in content, f"{sql_path} does not contain CREATE INDEX statements."

    db_path = "/home/user/store.db"
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_autoindex%';")
    indexes = cursor.fetchall()
    assert len(indexes) > 0, "No custom indexes found in the database. Ensure indexes.sql was executed."

    conn.close()


def test_top_spenders_csv():
    csv_path = "/home/user/top_spenders.csv"
    assert os.path.isfile(csv_path), f"File {csv_path} does not exist."

    with open(csv_path, 'r', newline='') as f:
        reader = list(csv.reader(f))

    assert len(reader) == 4, f"Expected exactly 1 header row and 3 data rows in {csv_path}, found {len(reader)}."

    headers = reader[0]
    assert headers == ["client_name", "total_spent"], f"Incorrect headers. Expected ['client_name', 'total_spent'], got {headers}."

    results = []
    for row in reader[1:]:
        assert len(row) == 2, f"Expected 2 columns per row, got {len(row)} in row {row}"
        client_name = row[0].strip()
        try:
            total_spent = float(row[1].strip())
        except ValueError:
            pytest.fail(f"Could not parse total_spent '{row[1]}' as float.")
        results.append((client_name, total_spent))

    top_two = sorted([results[0], results[1]])
    expected_top_two = sorted([("Alice Smith", 1200.0), ("Charlie Brown", 1200.0)])

    assert top_two == expected_top_two, f"Expected top two spenders to be Alice Smith and Charlie Brown with 1200.0, got {top_two}."
    assert results[2] == ("Bob Jones", 200.0), f"Expected third spender to be Bob Jones with 200.0, got {results[2]}."


def test_query_sql_exists():
    sql_path = "/home/user/query.sql"
    assert os.path.isfile(sql_path), f"File {sql_path} does not exist."
    with open(sql_path, 'r') as f:
        content = f.read().lower()
        assert "select" in content, f"{sql_path} does not appear to contain a valid SQL SELECT query."


def read_query():
    with open(os.path.join(HOME, "query.sql"), encoding="utf-8") as f:
        query = f.read().strip()
    assert query, "query.sql is empty"
    return query


def execute_query(db_path):
    conn = sqlite3.connect(db_path)
    try:
        cur = conn.execute(read_query())
        rows = cur.fetchall()
        assert cur.description is not None and len(cur.description) == 2, \
            "query.sql must return exactly two columns"
        return rows
    finally:
        conn.close()


def test_query_executes_and_generated_csv_matches_it():
    rows = execute_query(DB)
    assert len(rows) >= 3, "query.sql returned fewer than three spenders"
    query_top = [(str(row[0]).strip(), float(row[1])) for row in rows[:3]]

    with open(os.path.join(HOME, "top_spenders.csv"), newline="", encoding="utf-8") as f:
        csv_rows = list(csv.reader(f))[1:]
    exported = [(row[0].strip(), float(row[1])) for row in csv_rows]

    assert len(exported) == 3
    assert [name for name, _ in exported] == [name for name, _ in query_top], \
        "top_spenders.csv is not the top three output rows from query.sql"
    for (_, actual), (_, expected) in zip(exported, query_top):
        assert actual == pytest.approx(expected), \
            "top_spenders.csv totals do not match query.sql"


def read_csv_table(table):
    with open(os.path.join(DATA, table + ".csv"), newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        return reader.fieldnames, list(reader)


def values_equal(csv_value, db_value):
    if db_value is None:
        return csv_value == ""
    try:
        return Decimal(csv_value) == Decimal(str(db_value))
    except (InvalidOperation, ValueError):
        return csv_value == str(db_value)


def assert_database_loaded_from_current_csv(conn):
    for table in ("clients", "items", "purchases", "purchase_lines"):
        headers, expected = read_csv_table(table)
        info = conn.execute(f'PRAGMA table_info("{table}")').fetchall()
        columns = [row[1] for row in info]
        assert columns == headers, f"{table} columns do not match its CSV: {columns}"
        actual = conn.execute(f'SELECT * FROM "{table}"').fetchall()
        assert len(actual) == len(expected), f"{table} did not load every CSV row"
        unmatched = list(actual)
        for expected_row in expected:
            for i, actual_row in enumerate(unmatched):
                if all(values_equal(expected_row[col], actual_row[j]) for j, col in enumerate(headers)):
                    unmatched.pop(i)
                    break
            else:
                pytest.fail(f"CSV row was not loaded into {table}: {expected_row}")
        assert not unmatched


def assert_keys(conn):
    expected_pks = {
        "clients": "c_id",
        "items": "item_code",
        "purchases": "p_id",
        "purchase_lines": "line_id",
    }
    for table, key in expected_pks.items():
        info = conn.execute(f'PRAGMA table_info("{table}")').fetchall()
        pk_columns = [row[1] for row in info if row[5] > 0]
        assert pk_columns == [key], f"{table} must explicitly define {key} as its primary key"

    purchases_fks = {(r[3], r[2], r[4]) for r in conn.execute("PRAGMA foreign_key_list(purchases)")}
    lines_fks = {(r[3], r[2], r[4]) for r in conn.execute("PRAGMA foreign_key_list(purchase_lines)")}
    assert ("c_ref", "clients", "c_id") in purchases_fks
    assert ("p_ref", "purchases", "p_id") in lines_fks
    assert ("item_ref", "items", "item_code") in lines_fks
    assert conn.execute("PRAGMA foreign_key_check").fetchall() == []


def expected_dynamic_results():
    _, clients = read_csv_table("clients")
    _, items = read_csv_table("items")
    _, purchases = read_csv_table("purchases")
    _, lines = read_csv_table("purchase_lines")
    client_names = {r["c_id"]: r["full_name"] for r in clients}
    purchase_clients = {r["p_id"]: r["c_ref"] for r in purchases}
    item_data = {r["item_code"]: r for r in items}
    totals = {}
    for line in lines:
        item = item_data[line["item_ref"]]
        if item["category"] == "Electronics":
            name = client_names[purchase_clients[line["p_ref"]]]
            totals[name] = totals.get(name, Decimal("0")) + Decimal(item["unit_price"]) * Decimal(line["qty"])
    return sorted(totals.items(), key=lambda row: (-row[1], row[0]))[:3]


def assert_useful_indexes(conn):
    required = {
        ("purchases", "c_ref"),
        ("purchase_lines", "p_ref"),
        ("purchase_lines", "item_ref"),
        ("items", "category"),
    }
    indexed = set()
    for table in ("clients", "items", "purchases", "purchase_lines"):
        for index_row in conn.execute(f'PRAGMA index_list("{table}")'):
            name = index_row[1]
            if name.startswith("sqlite_autoindex"):
                continue
            columns = conn.execute(f'PRAGMA index_info("{name}")').fetchall()
            if columns:
                indexed.add((table, columns[0][2]))
    missing = required - indexed
    assert not missing, f"Missing useful leading-column indexes for: {sorted(missing)}"


def test_z_build_script_indexes_and_query_are_functional_on_changed_input():
    with open(os.path.join(HOME, "build_db.py"), encoding="utf-8") as f:
        source = f.read().lower()
    assert re.search(r"create\s+table", source), "build_db.py has no CREATE TABLE statement"
    assert "primary key" in source, "build_db.py must explicitly define primary keys"
    assert "foreign key" in source, "build_db.py must explicitly define foreign keys"

    protected = [
        os.path.join(DATA, name)
        for name in ("clients.csv", "items.csv", "purchases.csv", "purchase_lines.csv")
    ] + [DB]
    backups = {path: open(path, "rb").read() if os.path.exists(path) else None for path in protected}

    try:
        for filename in ("clients.csv", "items.csv", "purchase_lines.csv"):
            path = os.path.join(DATA, filename)
            with open(path, newline="", encoding="utf-8") as f:
                reader = csv.DictReader(f)
                fields, rows = reader.fieldnames, list(reader)
            if filename == "clients.csv":
                for row in rows:
                    row["full_name"] += " Dynamic"
            elif filename == "items.csv":
                for row in rows:
                    row["unit_price"] = str(Decimal(row["unit_price"]) + Decimal("13.25"))
            else:
                for row in rows:
                    row["qty"] = str(int(row["qty"]) + 1)
            with open(path, "w", newline="", encoding="utf-8") as f:
                writer = csv.DictWriter(f, fieldnames=fields)
                writer.writeheader()
                writer.writerows(rows)

        if os.path.exists(DB):
            os.remove(DB)
        result = subprocess.run(
            ["python3", os.path.join(HOME, "build_db.py")],
            cwd=HOME, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            timeout=30
        )
        assert result.returncode == 0, f"build_db.py failed:\n{result.stdout}\n{result.stderr}"
        assert os.path.isfile(DB), "build_db.py did not create store.db"

        conn = sqlite3.connect(DB)
        try:
            assert_database_loaded_from_current_csv(conn)
            assert_keys(conn)

            custom = conn.execute(
                "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_autoindex%'"
            ).fetchall()
            for (name,) in custom:
                conn.execute(f'DROP INDEX "{name.replace(chr(34), chr(34) * 2)}"')
            conn.commit()

            with open(os.path.join(HOME, "indexes.sql"), encoding="utf-8") as f:
                index_sql = f.read()
            conn.executescript(index_sql)
            conn.commit()
            assert_useful_indexes(conn)
        finally:
            conn.close()

        actual = execute_query(DB)
        assert len(actual) == 3, "query.sql must return the three clients with Electronics spending"
        actual = [(str(row[0]), Decimal(str(row[1]))) for row in actual]
        expected = expected_dynamic_results()
        assert [row[0] for row in actual] == [row[0] for row in expected], \
            "query.sql returned incorrect clients or ordering for changed CSV data"
        for (_, actual_total), (_, expected_total) in zip(actual, expected):
            assert actual_total == expected_total, \
                "query.sql did not calculate quantity times unit price from the changed CSV data"
    finally:
        for path, content in backups.items():
            if content is None:
                if os.path.exists(path):
                    os.remove(path)
            else:
                with open(path, "wb") as f:
                    f.write(content)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

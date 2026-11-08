#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import os
import re
import secrets
import sqlite3
import subprocess
from datetime import datetime
from decimal import Decimal

import pytest

HOME = "/home/user"
SOURCE_PATH = f"{HOME}/process.go"
CSV_PATH = f"{HOME}/data/sales_dump.csv"
DB_PATH = f"{HOME}/sales.db"
REPORT_PATH = f"{HOME}/report.csv"

ORIGINAL_TEXT = """TxnID,UserID,UserEmail,UserRegion,ProductID,ProductName,ProductCategory,Price,Quantity,TxnDate
1,101,alice@example.com,EU,501,Laptop,Electronics,1200.00,1,2023-08-15
2,102,bob@example.com,NA,502,Phone,Electronics,800.00,2,2023-08-20
3,103,charlie@example.com,EU,503,Desk,Furniture,300.00,2,2023-07-10
4,101,alice@example.com,EU,504,Chair,Furniture,150.00,4,2023-09-05
5,104,diana@example.com,EU,505,Book,Media,20.00,5,2023-10-12
6,105,evan@example.com,EU,501,Laptop,Electronics,1200.00,2,2023-09-29
7,106,fiona@example.com,AS,503,Desk,Furniture,300.00,1,2023-07-25
8,107,george@example.com,EU,506,Headphones,Electronics,150.00,3,2023-08-01
9,101,alice@example.com,EU,507,Monitor,Electronics,250.00,2,2023-06-15
10,103,charlie@example.com,EU,505,Book,Media,20.00,10,2023-09-15
"""


def remove_outputs():
    for path in (DB_PATH, DB_PATH + "-wal", DB_PATH + "-shm", REPORT_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def run_program(csv_text):
    with open(CSV_PATH, "w", newline="") as f:
        f.write(csv_text)
    remove_outputs()
    result = subprocess.run(
        ["go", "run", SOURCE_PATH],
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, "process.go failed:\n" + result.stdout


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    run_program(ORIGINAL_TEXT)
    try:
        yield
    finally:
        # Leave the requested artifacts corresponding to the original input.
        try:
            run_program(ORIGINAL_TEXT)
        except Exception:
            with open(CSV_PATH, "w", newline="") as f:
                f.write(ORIGINAL_TEXT)


def rows_from_text(text):
    return list(csv.DictReader(io.StringIO(text)))


def assert_schema_and_constraints():
    conn = sqlite3.connect(DB_PATH)
    try:
        expected = {
            "users": {"id": "INTEGER", "email": "TEXT", "region": "TEXT"},
            "products": {"id": "INTEGER", "name": "TEXT", "category": "TEXT"},
            "transactions": {
                "id": "INTEGER", "user_id": "INTEGER", "product_id": "INTEGER",
                "price": "REAL", "quantity": "INTEGER", "txn_date": "TEXT",
            },
        }
        for table, columns in expected.items():
            info = conn.execute(f"PRAGMA table_info({table})").fetchall()
            actual = {row[1]: row[2].upper() for row in info}
            assert set(actual) == set(columns), f"Incorrect columns in {table}: {actual}"
            for name, declared_type in columns.items():
                assert actual[name] == declared_type, f"{table}.{name} must be {declared_type}"

        fks = conn.execute("PRAGMA foreign_key_list(transactions)").fetchall()
        mappings = {(row[3], row[2], row[4]) for row in fks}
        assert ("user_id", "users", "id") in mappings
        assert ("product_id", "products", "id") in mappings

        index_starts = set()
        for table in ("users", "products", "transactions"):
            for index_row in conn.execute(f"PRAGMA index_list({table})").fetchall():
                index_name = index_row[1]
                cols = conn.execute(f"PRAGMA index_info('{index_name}')").fetchall()
                if cols:
                    index_starts.add((table, cols[0][2]))
        for required in {
            ("users", "region"),
            ("transactions", "txn_date"),
            ("transactions", "user_id"),
            ("transactions", "product_id"),
        }:
            assert required in index_starts, f"Missing an index beginning with {required[0]}.{required[1]}"
    finally:
        conn.close()


def assert_database_matches(csv_text):
    source_rows = rows_from_text(csv_text)
    expected_users = {
        (int(r["UserID"]), r["UserEmail"], r["UserRegion"]) for r in source_rows
    }
    expected_products = {
        (int(r["ProductID"]), r["ProductName"], r["ProductCategory"]) for r in source_rows
    }
    expected_transactions = {
        (
            int(r["TxnID"]), int(r["UserID"]), int(r["ProductID"]),
            Decimal(r["Price"]).quantize(Decimal("0.01")), int(r["Quantity"]), r["TxnDate"],
        )
        for r in source_rows
    }

    conn = sqlite3.connect(DB_PATH)
    try:
        users = set(conn.execute("SELECT id,email,region FROM users"))
        products = set(conn.execute("SELECT id,name,category FROM products"))
        raw_transactions = conn.execute(
            "SELECT id,user_id,product_id,price,quantity,txn_date FROM transactions"
        ).fetchall()
        transactions = {
            (r[0], r[1], r[2], Decimal(str(r[3])).quantize(Decimal("0.01")), r[4], r[5])
            for r in raw_transactions
        }
        assert users == expected_users
        assert products == expected_products
        assert transactions == expected_transactions
        assert len(users) == len({r["UserID"] for r in source_rows})
        assert len(products) == len({r["ProductID"] for r in source_rows})
        for row in raw_transactions:
            datetime.strptime(row[5], "%Y-%m-%d")
    finally:
        conn.close()


def expected_report(csv_text):
    totals = {}
    for r in rows_from_text(csv_text):
        if r["UserRegion"] == "EU" and "2023-07-01" <= r["TxnDate"] <= "2023-09-30":
            totals.setdefault(r["ProductCategory"], Decimal("0"))
            totals[r["ProductCategory"]] += Decimal(r["Price"]) * int(r["Quantity"])
    ordered = sorted(totals.items(), key=lambda item: (-item[1], item[0]))[:3]
    return [["Category", "TotalRevenue"]] + [
        [category, f"{revenue:.2f}"] for category, revenue in ordered
    ]


def read_report():
    with open(REPORT_PATH, "r", newline="") as f:
        return [row for row in csv.reader(f) if row]


def test_process_go_exists_and_contains_sql_pipeline():
    assert os.path.isfile(SOURCE_PATH), f"The Go source file {SOURCE_PATH} is missing."
    with open(SOURCE_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    assert re.search(r"\bpackage\s+main\b", source)
    assert re.search(r"\bfunc\s+main\s*\(", source)
    sql_text = re.sub(r"\s+", " ", source).upper()
    for token in ("SELECT", "JOIN", "SUM", "GROUP BY", "ORDER BY", "LIMIT", "USERS", "PRODUCTS", "TRANSACTIONS"):
        assert token in sql_text, f"process.go does not contain the required SQL query component: {token}"
    assert re.search(r"\.\s*(QUERY|QUERYCONTEXT|PREPARE|EXEC)\s*\(", source, re.I) or (
        "EXEC.COMMAND" in sql_text and "SQLITE3" in sql_text
    ), "process.go does not appear to execute its SQL query"


def test_sales_db_exists():
    """Check if the SQLite database was created."""
    assert os.path.isfile(DB_PATH), f"The database file {DB_PATH} is missing."


def test_sales_db_schema():
    """Check if the normalized tables exist in the database."""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table';")
    tables = {row[0] for row in cursor.fetchall()}
    expected_tables = {"users", "products", "transactions"}
    for table in expected_tables:
        assert table in tables, f"Table '{table}' is missing from the database."
    conn.close()


def test_sales_db_indexes():
    """Check if indexes were created."""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%';")
    indexes = cursor.fetchall()
    assert len(indexes) > 0, "No indexes were found in the database. You must create appropriate indexes."
    conn.close()


def test_normalized_schema_constraints_indexes_and_data():
    assert_schema_and_constraints()
    assert_database_matches(ORIGINAL_TEXT)


def test_report_csv_exists():
    """Check if the report CSV file was created."""
    assert os.path.isfile(REPORT_PATH), f"The report file {REPORT_PATH} is missing."


def test_report_csv_content():
    """Check if the report CSV has the correct content."""
    expected_data = [
        ["Category", "TotalRevenue"],
        ["Electronics", "4050.00"],
        ["Furniture", "1200.00"],
        ["Media", "200.00"]
    ]
    assert read_report() == expected_data, f"The contents of {REPORT_PATH} do not match the expected output."


def test_z_pipeline_on_unseen_input():
    tag = secrets.token_hex(5)
    categories = [f"Category_{tag}_{i}" for i in range(5)]
    rows = []
    txn = 70000
    product = 80000
    totals = [Decimal("5123.47"), Decimal("4388.26"), Decimal("3277.19"), Decimal("2166.08"), Decimal("1055.97")]

    for i, (category, total) in enumerate(zip(categories, totals)):
        # Two products per category ensure aggregation and joins are required.
        first = (total - Decimal("100.00")) / 3
        entries = [(first, 3), (Decimal("50.00"), 2)]
        for j, (price, quantity) in enumerate(entries):
            rows.append([
                txn, 90000 + i, f"eu{i}-{tag}@example.test", "EU",
                product, f"Product_{tag}_{i}_{j}", category,
                f"{price:.2f}", quantity, "2023-08-17" if j == 0 else "2023-09-30",
            ])
            txn += 1
            product += 1

    # High-value records that must be excluded by region and date filters.
    rows.append([txn, 91000, f"na-{tag}@example.test", "NA", product,
                 f"ExcludedRegion_{tag}", f"ExcludedRegionCategory_{tag}", "9999.99", 9, "2023-08-01"])
    txn += 1
    product += 1
    rows.append([txn, 91001, f"late-{tag}@example.test", "EU", product,
                 f"ExcludedDate_{tag}", f"ExcludedDateCategory_{tag}", "8888.88", 8, "2023-10-01"])

    output = io.StringIO()
    writer = csv.writer(output, lineterminator="\n")
    writer.writerow(["TxnID", "UserID", "UserEmail", "UserRegion", "ProductID", "ProductName",
                     "ProductCategory", "Price", "Quantity", "TxnDate"])
    writer.writerows(rows)
    generated_csv = output.getvalue()

    run_program(generated_csv)
    assert os.path.isfile(DB_PATH)
    assert os.path.isfile(REPORT_PATH)
    assert_schema_and_constraints()
    assert_database_matches(generated_csv)
    assert read_report() == expected_report(generated_csv)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

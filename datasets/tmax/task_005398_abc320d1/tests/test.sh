#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import re
import shutil
import sqlite3
import subprocess
import tempfile
import uuid
from decimal import Decimal

import pytest

DB = "/home/user/ecommerce.db"
QUERY = "/home/user/query.sql"
OPTIMIZE = "/home/user/optimize.sql"
SOURCE = "/home/user/report_generator.cpp"
BINARY = "/home/user/report_generator"
OUTPUT = "/home/user/top_products.csv"
COMPILED = "/tmp/report_generator_from_source"


def run_program(path):
    result = subprocess.run(
        [path], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, text=True, timeout=15
    )
    assert result.returncode == 0, (
        f"{path} failed with exit code {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )


def test_sql_files_exist():
    assert os.path.isfile(QUERY), f"{QUERY} is missing."
    assert os.path.isfile(OPTIMIZE), f"{OPTIMIZE} is missing."


def test_cpp_files_and_executable_exist():
    assert os.path.isfile(SOURCE), f"{SOURCE} is missing."
    assert os.path.isfile(BINARY), f"{BINARY} executable is missing."
    assert os.access(BINARY, os.X_OK), f"{BINARY} is not executable."

    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{BINARY} is not a compiled ELF executable."

    source_text = open(SOURCE, encoding="utf-8").read()
    assert "/home/user/query.sql" in source_text, "The C++ program must read /home/user/query.sql."
    assert re.search(r"\bsqlite3_open(?:_v2)?\s*\(", source_text), "The C++ program must open SQLite through its C API."
    assert re.search(r"\bsqlite3_prepare(?:_v2|_v3)?\s*\(", source_text), "The C++ program must prepare the SQL query through SQLite."

    result = subprocess.run(
        ["g++", "-O3", "-o", COMPILED, SOURCE, "-lsqlite3"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert result.returncode == 0, f"report_generator.cpp does not compile: {result.stderr}"


def test_indexes_created():
    assert os.path.isfile(DB), f"Database file {DB} is missing."

    conn = sqlite3.connect(DB)
    indexes = conn.execute("SELECT name FROM sqlite_master WHERE type='index';").fetchall()
    conn.close()
    assert len(indexes) >= 2, f"Expected at least 2 indexes to be created, but found {len(indexes)}."


def test_optimize_script_creates_useful_indexes():
    fd, clone = tempfile.mkstemp(suffix=".db")
    os.close(fd)
    try:
        source_conn = sqlite3.connect(DB)
        clone_conn = sqlite3.connect(clone)
        source_conn.backup(clone_conn)
        source_conn.close()

        existing = clone_conn.execute(
            "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'"
        ).fetchall()
        for (name,) in existing:
            clone_conn.execute('DROP INDEX "' + name.replace('"', '""') + '"')
        clone_conn.commit()

        with open(OPTIMIZE, encoding="utf-8") as f:
            script = f.read()
        clone_conn.executescript(script)

        created = clone_conn.execute(
            "SELECT name, tbl_name FROM sqlite_master "
            "WHERE type='index' AND name NOT LIKE 'sqlite_%'"
        ).fetchall()
        assert len(created) >= 2, "optimize.sql must itself create at least two indexes."

        useful = {
            ("orders", "order_date"),
            ("order_items", "order_id"),
            ("order_items", "product_id"),
            ("products", "category_id"),
        }
        useful_count = 0
        for name, table in created:
            escaped = name.replace('"', '""')
            columns = [row[2] for row in clone_conn.execute(f'PRAGMA index_info("{escaped}")')]
            if any((table, column) in useful for column in columns):
                useful_count += 1
        assert useful_count >= 2, "At least two indexes created by optimize.sql must target query filter or join columns."
        clone_conn.close()
    finally:
        if os.path.exists(clone):
            os.unlink(clone)


def test_csv_output_exact_match():
    if os.path.exists(OUTPUT):
        os.unlink(OUTPUT)
    run_program(BINARY)
    assert os.path.isfile(OUTPUT), f"CSV output file {OUTPUT} is missing."

    with open(OUTPUT, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "category_name,product_name,revenue,rank",
        "Books,Sci-Fi Novel,150.00,1",
        "Books,History Book,44.00,2",
        "Clothing,Jacket,120.00,1",
        "Electronics,Laptop,1999.98,1",
        "Electronics,Monitor,600.00,2",
    ]
    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in CSV, got {len(lines)}."
    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Mismatch at line {i+1}. Expected '{expected}', got '{actual}'."


def test_query_and_reporting_tool_on_derived_fixture():
    query_text = open(QUERY, encoding="utf-8").read()
    assert re.search(r"\bDENSE_RANK\s*\(", query_text, re.IGNORECASE), "query.sql must use DENSE_RANK()."

    backup = tempfile.mktemp(suffix=".db")
    shutil.copy2(DB, backup)
    old_csv = None
    if os.path.exists(OUTPUT):
        with open(OUTPUT, "rb") as f:
            old_csv = f.read()

    token = uuid.uuid4().hex[:8]
    rng = random.SystemRandom()
    cat_a = f"Alpha_{token}"
    cat_b = f"Beta_{token}"
    high = f"High_{token}"
    tie_a = f"TieA_{token}"
    tie_b = f"TieB_{token}"
    low = f"Low_{token}"
    unused = f"Unused_{token}"
    lead = f"Lead_{token}"
    next_product = f"Next_{token}"

    high_price = rng.randint(13, 19)
    tie_price = rng.randint(10, 12)
    lead_price = rng.randint(16, 20)
    next_price = rng.randint(8, 11)

    expected = [
        (cat_a, high, Decimal(high_price * 9), 1),
        (cat_a, tie_a, Decimal(tie_price * 5), 2),
        (cat_a, tie_b, Decimal(tie_price * 5), 2),
        (cat_b, lead, Decimal(lead_price * 6), 1),
        (cat_b, next_product, Decimal(next_price * 4), 2),
    ]
    expected.sort(key=lambda row: (row[0], row[3], row[1]))

    try:
        conn = sqlite3.connect(DB)
        conn.execute("DELETE FROM order_items")
        conn.execute("DELETE FROM orders")
        conn.execute("DELETE FROM products")
        conn.execute("DELETE FROM categories")
        conn.executemany("INSERT INTO categories(id,name) VALUES (?,?)", [(101, cat_a), (102, cat_b)])
        conn.executemany(
            "INSERT INTO products(id,category_id,name,price) VALUES (?,?,?,?)",
            [
                (201, 101, high, high_price),
                (202, 101, tie_a, tie_price),
                (203, 101, tie_b, tie_price),
                (204, 101, low, 5),
                (205, 101, unused, 999),
                (206, 102, lead, lead_price),
                (207, 102, next_product, next_price),
            ],
        )
        conn.executemany(
            "INSERT INTO orders(id,customer_id,order_date) VALUES (?,?,?)",
            [(301, 1, "2023-01-07"), (302, 2, "2023-12-19"), (303, 3, "2022-06-10")],
        )
        conn.executemany(
            "INSERT INTO order_items(id,order_id,product_id,quantity) VALUES (?,?,?,?)",
            [
                (401, 301, 201, 4), (402, 302, 201, 5),
                (403, 301, 202, 5), (404, 302, 203, 5),
                (405, 301, 204, 4), (406, 303, 204, 1000),
                (407, 301, 206, 2), (408, 302, 206, 4),
                (409, 302, 207, 4),
            ],
        )
        conn.commit()

        cursor = conn.execute(query_text)
        assert [d[0] for d in cursor.description] == ["category_name", "product_name", "total_revenue", "rank"]
        sql_rows = cursor.fetchall()
        normalized = [(r[0], r[1], Decimal(str(r[2])).quantize(Decimal("0.01")), int(r[3])) for r in sql_rows]
        expected_normalized = [(a, b, c.quantize(Decimal("0.01")), d) for a, b, c, d in expected]
        assert normalized == expected_normalized, "query.sql did not produce the required ranked 2023 results."
        conn.close()

        for executable in (BINARY, COMPILED):
            if os.path.exists(OUTPUT):
                os.unlink(OUTPUT)
            run_program(executable)
            assert os.path.isfile(OUTPUT), f"{executable} did not create {OUTPUT}."
            with open(OUTPUT, newline="", encoding="utf-8") as f:
                rows = list(csv.reader(f))
            assert rows and rows[0] == ["category_name", "product_name", "revenue", "rank"]
            assert len(rows) == len(expected) + 1
            actual = []
            for row in rows[1:]:
                assert len(row) == 4
                assert re.fullmatch(r"-?\d+\.\d{2}", row[2]), f"Revenue is not formatted to two decimals: {row[2]!r}"
                actual.append((row[0], row[1], Decimal(row[2]), int(row[3])))
            assert actual == expected_normalized, f"{executable} did not report the derived fixture correctly."
    finally:
        shutil.copy2(backup, DB)
        os.unlink(backup)
        if old_csv is None:
            if os.path.exists(OUTPUT):
                os.unlink(OUTPUT)
        else:
            with open(OUTPUT, "wb") as f:
                f.write(old_csv)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

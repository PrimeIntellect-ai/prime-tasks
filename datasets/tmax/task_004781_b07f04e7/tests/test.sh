#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import re
import secrets
import sqlite3
import subprocess
import pytest


def test_generate_report_executable_exists():
    path = "/home/user/generate_report"
    assert os.path.isfile(path), f"Executable missing at {path}"
    assert os.access(path, os.X_OK), f"File at {path} is not executable"


def test_revenue_report_csv_correctness():
    path = "/home/user/revenue_report.csv"
    assert os.path.isfile(path), f"CSV report missing at {path}"

    expected = {
        "Clothing": 330,
        "Electronics": 2400
    }

    try:
        with open(path, 'r') as f:
            reader = csv.DictReader(f)
            actual = {row['category']: int(row['total_revenue']) for row in reader}
    except Exception as e:
        pytest.fail(f"Failed to read or parse {path}: {e}")

    mse = 0
    for cat, exp_val in expected.items():
        act_val = actual.get(cat, 0)
        mse += (exp_val - act_val) ** 2

    mse /= len(expected)

    assert mse <= 0.0, f"MSE of total_revenue is {mse}, expected <= 0.0. Actual values: {actual}"


def create_dynamic_database():
    token = secrets.token_hex(8)
    categories = [f"Alpha_{token}", f"Beta_{token}", f"Gamma_{token}"]

    products = []
    orders = []
    expected = {category: 0 for category in categories}
    product_id = 1
    order_id = 1001

    for category in categories:
        for _ in range(2):
            price = secrets.randbelow(800) + 17
            products.append((product_id, category, price))
            for _ in range(secrets.randbelow(3) + 1):
                quantity = secrets.randbelow(9) + 1
                orders.append((order_id, product_id, quantity))
                expected[category] += quantity * price
                order_id += 1
            product_id += 1

    db_path = "/app/backup.db"
    if os.path.lexists(db_path):
        os.unlink(db_path)
    connection = sqlite3.connect(db_path)
    try:
        connection.executescript("""
            CREATE TABLE products (
                product_id INTEGER PRIMARY KEY,
                category TEXT,
                price INTEGER
            );
            CREATE TABLE orders (
                order_id INTEGER PRIMARY KEY,
                product_id INTEGER,
                quantity INTEGER
            );
        """)
        connection.executemany("INSERT INTO products VALUES (?, ?, ?)", products)
        connection.executemany("INSERT INTO orders VALUES (?, ?, ?)", orders)
        connection.commit()
    finally:
        connection.close()
    return expected


def read_exact_report(expected):
    path = "/home/user/revenue_report.csv"
    assert os.path.isfile(path), f"Program did not create {path}"

    try:
        with open(path, "r", encoding="utf-8", newline="") as report:
            text = report.read()
    except Exception as exc:
        pytest.fail(f"Failed to read {path}: {exc}")

    lines = text.splitlines()
    assert lines, "CSV report is empty"
    assert lines[0] == "category,total_revenue", f"Incorrect CSV header: {lines[0]!r}"
    assert len(lines) == len(expected) + 1, "CSV has missing, duplicate, blank, or extra rows"

    try:
        reader = csv.DictReader(lines)
        assert reader.fieldnames == ["category", "total_revenue"]
        rows = list(reader)
    except Exception as exc:
        pytest.fail(f"Failed to parse generated CSV: {exc}")

    actual = {}
    for row in rows:
        assert set(row.keys()) == {"category", "total_revenue"}, f"Malformed CSV row: {row}"
        category = row["category"]
        value = row["total_revenue"]
        assert category not in actual, f"Duplicate category row: {category}"
        assert re.fullmatch(r"0|[1-9][0-9]*", value or ""), f"Revenue is not formatted as an integer: {value!r}"
        actual[category] = int(value)

    assert actual == expected, f"Incorrect or extra report rows. Expected {expected}, got {actual}"


def run_and_check(executable, expected):
    report_path = "/home/user/revenue_report.csv"
    if os.path.lexists(report_path):
        os.unlink(report_path)
    result = subprocess.run(
        [executable],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"{executable} exited with {result.returncode}. "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    read_exact_report(expected)


def test_source_and_executable_generate_dynamic_report_using_sqlite():
    source = "/home/user/generate_report.c"
    executable = "/home/user/generate_report"
    compiled = "/tmp/generate_report_from_source"

    assert os.path.isfile(source), f"C source missing at {source}"
    assert os.path.isfile(executable), f"Executable missing at {executable}"
    assert os.access(executable, os.X_OK), f"File at {executable} is not executable"

    compile_result = subprocess.run(
        ["gcc", source, "-o", compiled, "-lsqlite3"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compile_result.returncode == 0, (
        f"Failed to compile {source} with SQLite3: {compile_result.stderr}"
    )

    symbols = subprocess.run(
        ["nm", "-u", compiled],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        check=True,
        timeout=10,
    ).stdout
    assert re.search(r"sqlite3_open(?:_v2)?(?:@|\s|$)", symbols), "Program does not use sqlite3_open/sqlite3_open_v2"
    assert re.search(r"sqlite3_(?:exec|get_table|prepare|prepare_v2|prepare_v3)(?:@|\s|$)", symbols), (
        "Program does not use a SQLite3 C API query function"
    )

    expected = create_dynamic_database()
    run_and_check(executable, expected)

    expected = create_dynamic_database()
    run_and_check(compiled, expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

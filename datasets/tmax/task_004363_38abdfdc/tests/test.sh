#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import shutil
import sqlite3
import subprocess
import tempfile
import pytest

DB_PATH = "/home/user/sales.db"
JSON_PATH = "/home/user/top_sales.json"
GO_PATH = "/home/user/generate_report.go"
MOD_PATH = "/home/user/go.mod"


def test_index_created():
    db_path = DB_PATH
    assert os.path.exists(db_path), f"Database file {db_path} does not exist."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_sales_perf';")
    index = cursor.fetchone()
    assert index is not None, "Index 'idx_sales_perf' was not created in the database."
    assert index[0] == 'idx_sales_perf', "Index name mismatch."

    cursor.execute("PRAGMA index_info('idx_sales_perf')")
    columns = [row[2] for row in cursor.fetchall()]
    conn.close()

    assert columns[:2] == ["region", "salesperson"], (
        "idx_sales_perf must begin with region and salesperson to optimize the requested grouping."
    )
    assert "amount" in columns, "idx_sales_perf must include amount so it is a covering index."


def test_json_output():
    json_path = JSON_PATH
    assert os.path.exists(json_path), f"JSON output file {json_path} does not exist."

    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {json_path} does not contain valid JSON.")

    expected = [
        {"region": "North", "salesperson": "Alice", "total_sales": 5000.5, "region_total": 12500.5, "rank": 1},
        {"region": "North", "salesperson": "Diana", "total_sales": 4000.0, "region_total": 12500.5, "rank": 2},
        {"region": "South", "salesperson": "Eve", "total_sales": 7000.0, "region_total": 11500.0, "rank": 1},
        {"region": "South", "salesperson": "Grace", "total_sales": 2500.0, "region_total": 11500.0, "rank": 2}
    ]

    assert isinstance(data, list), "JSON root should be a list of objects."
    assert len(data) == len(expected), f"Expected {len(expected)} elements in JSON, found {len(data)}."

    for i, (actual_item, expected_item) in enumerate(zip(data, expected)):
        assert actual_item == expected_item, f"Mismatch at index {i}. Expected {expected_item}, got {actual_item}."


def test_go_project_and_window_query():
    assert os.path.isfile(GO_PATH), f"Required Go program {GO_PATH} does not exist."
    assert os.path.isfile(MOD_PATH), f"Go module file {MOD_PATH} does not exist."

    with open(GO_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    with open(MOD_PATH, "r", encoding="utf-8") as f:
        go_mod = f.read()

    assert "github.com/mattn/go-sqlite3" in source, "The Go program must import the mattn/go-sqlite3 driver."
    assert "github.com/mattn/go-sqlite3" in go_mod, "The sqlite3 driver must be declared in go.mod."
    assert re.search(r'\bsql\s*\.\s*Open\s*\(', source), "The program must connect through database/sql."
    assert DB_PATH in source, f"The program must connect to {DB_PATH}."
    assert JSON_PATH in source, f"The program must write {JSON_PATH}."

    # Require the submitted query itself to contain both ranking and analytical
    # regional-total windows. Behavioral tests below ensure this query is used.
    assert re.search(r'(?is)\brank\s*\(\s*\)\s*over\s*\(', source), (
        "The SQL must use RANK() as a window function."
    )
    window_sums = re.findall(r'(?is)\bsum\s*\([^)]*\)\s*over\s*\(', source)
    assert window_sums, "The regional total must be calculated with SUM(...) OVER(...)."
    assert len(re.findall(r'(?is)\bover\s*\(', source)) >= 2, (
        "The query must use windows for both ranking and the regional total."
    )

    query_calls = re.findall(r'(?s)\.\s*Query(?:Context)?\s*\(', source)
    assert len(query_calls) == 1, "The report must be produced by a single SQL query execution."


def _expected_report(rows):
    totals = {}
    for region, salesperson, amount, _ in rows:
        totals[(region, salesperson)] = totals.get((region, salesperson), 0) + amount

    region_totals = {}
    for (region, _), amount in totals.items():
        region_totals[region] = region_totals.get(region, 0) + amount

    result = []
    for (region, salesperson), total in totals.items():
        rank = 1 + sum(
            1 for (other_region, _), other_total in totals.items()
            if other_region == region and other_total > total
        )
        if rank <= 2:
            result.append({
                "region": region,
                "salesperson": salesperson,
                "total_sales": total,
                "region_total": region_totals[region],
                "rank": rank,
            })
    return result


def test_compiled_program_on_unseen_database():
    token = secrets.token_hex(5)
    base = random.SystemRandom().randint(1000, 9000)
    r1, r2 = f"A_{token}", f"Z_{token}"
    people = [f"person_{token}_{i}" for i in range(7)]

    # Includes split sales and ties. RANK() yields ranks 1,2,2,4 in r1 and
    # 1,1,3 in r2, while region_total must include even filtered-out people.
    rows = [
        (r1, people[0], base + 40, "2025-01-01"),
        (r1, people[0], 60, "2025-01-02"),
        (r1, people[1], base + 80, "2025-01-03"),
        (r1, people[2], base + 30, "2025-01-04"),
        (r1, people[2], 50, "2025-01-05"),
        (r1, people[3], base + 10, "2025-01-06"),
        (r2, people[4], base + 70, "2025-02-01"),
        (r2, people[5], base + 20, "2025-02-02"),
        (r2, people[5], 50, "2025-02-03"),
        (r2, people[6], base + 60, "2025-02-04"),
    ]
    expected = _expected_report(rows)

    with tempfile.TemporaryDirectory() as td:
        db_backup = os.path.join(td, "sales.db")
        json_backup = os.path.join(td, "top_sales.json")
        binary = os.path.join(td, "generate_report")
        shutil.copy2(DB_PATH, db_backup)
        had_json = os.path.exists(JSON_PATH)
        if had_json:
            shutil.copy2(JSON_PATH, json_backup)

        try:
            subprocess.run(
                ["go", "build", "-o", binary, GO_PATH],
                cwd="/home/user",
                check=True,
                timeout=120,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )

            os.remove(DB_PATH)
            conn = sqlite3.connect(DB_PATH)
            conn.execute("""
                CREATE TABLE sales (
                    id INTEGER PRIMARY KEY,
                    region TEXT,
                    salesperson TEXT,
                    amount REAL,
                    sale_date DATE
                )
            """)
            conn.execute("CREATE INDEX idx_sales_perf ON sales(region, salesperson, amount)")
            conn.executemany(
                "INSERT INTO sales(region, salesperson, amount, sale_date) VALUES (?, ?, ?, ?)",
                rows,
            )
            conn.commit()
            conn.close()

            if os.path.exists(JSON_PATH):
                os.remove(JSON_PATH)
            subprocess.run(
                [binary],
                cwd="/home/user",
                check=True,
                timeout=30,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
            )
            assert os.path.isfile(JSON_PATH), "Running the compiled Go program did not create top_sales.json."
            with open(JSON_PATH, "r", encoding="utf-8") as f:
                actual = json.load(f)

            assert isinstance(actual, list), "Generated JSON root must be a list."
            assert all(isinstance(item, dict) for item in actual), "Each report entry must be an object."
            required_keys = {"region", "salesperson", "total_sales", "region_total", "rank"}
            assert all(set(item) == required_keys for item in actual), "Report objects have incorrect fields."
            assert [(x["region"], x["rank"]) for x in actual] == sorted(
                (x["region"], x["rank"]) for x in actual
            ), "Results are not ordered by region ascending and rank ascending."

            # Tie ordering is intentionally not prescribed beyond region and rank.
            key = lambda x: (x["region"], x["rank"], x["salesperson"])
            assert sorted(actual, key=key) == sorted(expected, key=key), (
                f"Program produced incorrect results for an unseen database. Expected {expected}, got {actual}."
            )
        finally:
            if os.path.exists(DB_PATH):
                os.remove(DB_PATH)
            shutil.copy2(db_backup, DB_PATH)
            if os.path.exists(JSON_PATH):
                os.remove(JSON_PATH)
            if had_json:
                shutil.copy2(json_backup, JSON_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

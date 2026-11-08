#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import sqlite3
import subprocess
import uuid

import pytest

PROJECT = "/home/user/review_cleaner"
MANIFEST = os.path.join(PROJECT, "Cargo.toml")
RAW_DATA = "/home/user/raw_data.jsonl"
SQL_PATH = "/home/user/insert.sql"
REPORT_PATH = "/home/user/report.md"
DB_PATH = "/home/user/reviews.db"


def test_rust_project_exists():
    assert os.path.isfile(MANIFEST), f"Rust project not found: {MANIFEST} is missing."
    assert os.path.isfile(os.path.join(PROJECT, "src", "main.rs")), "Rust project is missing src/main.rs."


def test_insert_sql_exists():
    assert os.path.isfile(SQL_PATH), f"SQL script not found: {SQL_PATH} is missing."
    with open(SQL_PATH, "r", encoding="utf-8") as f:
        content = f.read().lower()
        assert "create table" in content, "insert.sql does not contain CREATE TABLE statement."
        assert "insert into" in content, "insert.sql does not contain INSERT INTO statement."


def test_report_md_content():
    assert os.path.isfile(REPORT_PATH), f"Report file not found: {REPORT_PATH} is missing."

    expected_lines = [
        "# Category Report",
        "- apparel: 1 reviews",
        "- books: 1 reviews",
        "- electronics: 2 reviews"
    ]

    with open(REPORT_PATH, "r", encoding="utf-8") as f:
        content = f.read().strip()

    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]
    assert actual_lines == expected_lines, f"Report content does not match expected.\nExpected: {expected_lines}\nActual: {actual_lines}"


def test_sqlite_db_content():
    assert os.path.isfile(DB_PATH), f"SQLite database not found: {DB_PATH} is missing."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT id, category, product_name, review_text FROM reviews ORDER BY id ASC")
        rows = cursor.fetchall()
    except sqlite3.OperationalError as e:
        pytest.fail(f"Failed to query 'reviews' table: {e}")
    finally:
        conn.close()

    assert len(rows) == 4, f"Expected 4 rows in reviews table, found {len(rows)}."
    db_records = {str(row[0]): row[3] for row in rows}
    assert db_records.get("1") == "Très bien!", f"Record 1 review_text incorrect: {db_records.get('1')}"
    assert db_records.get("2") == "Great—book", f"Record 2 review_text incorrect: {db_records.get('2')}"
    assert db_records.get("3") == "It is ok.", f"Record 3 review_text incorrect: {db_records.get('3')}"
    assert "génial" in db_records.get("4", ""), f"Record 4 review_text incorrect: {db_records.get('4')}"


def build_and_run_submission():
    metadata_result = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1", "--manifest-path", MANIFEST],
        cwd=PROJECT,
        text=True,
        capture_output=True,
        timeout=60,
    )
    assert metadata_result.returncode == 0, metadata_result.stderr
    metadata = json.loads(metadata_result.stdout)
    root_id = metadata.get("resolve", {}).get("root")
    root_package = next((p for p in metadata["packages"] if p["id"] == root_id), None)
    assert root_package is not None, "Could not identify the root Cargo package."

    prohibited = {"rusqlite", "sqlx", "diesel", "sqlite", "sqlite3"}
    dependencies = {d["name"].lower() for d in root_package.get("dependencies", [])}
    assert not dependencies.intersection(prohibited), "A Rust SQLite driver is not allowed; insert.sql must be used with sqlite3."

    build_result = subprocess.run(
        ["cargo", "build", "--manifest-path", MANIFEST, "--message-format=json"],
        cwd=PROJECT,
        text=True,
        capture_output=True,
        timeout=180,
    )
    assert build_result.returncode == 0, build_result.stderr

    executables = []
    for line in build_result.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        if (
            message.get("reason") == "compiler-artifact"
            and message.get("package_id") == root_id
            and "bin" in message.get("target", {}).get("kind", [])
            and message.get("executable")
        ):
            executables.append((message["target"]["name"], message["executable"]))

    default_run = root_package.get("default_run")
    if default_run:
        executables = [item for item in executables if item[0] == default_run]
    assert len(executables) == 1, f"Expected one runnable Rust binary, found: {executables}"

    run_result = subprocess.run(
        [executables[0][1]],
        cwd=PROJECT,
        text=True,
        capture_output=True,
        timeout=60,
    )
    assert run_result.returncode == 0, f"Rust pipeline failed.\nstdout:\n{run_result.stdout}\nstderr:\n{run_result.stderr}"


def test_pipeline_on_unseen_fixture():
    nonce = uuid.uuid4().hex[:12]
    categories = [f"alpha-{nonce}", f"middle-{nonce}", f"zeta-{nonce}"]
    records = [
        {
            "id": f"id-a-{nonce}",
            "category": categories[2],
            "product_name": f"O'Brien {nonce}",
            "review_text": "caf\\u00e9 and d\\u00e9j\\u00e0 vu",
        },
        {
            "id": f"id-b-{nonce}",
            "category": categories[0],
            "product_name": f"Model\\u0041-{nonce}",
            "review_text": "Great\\u2014value",
        },
        {
            "id": f"id-c-{nonce}",
            "category": categories[0],
            "product_name": f"Plain {nonce}",
            "review_text": "It is still plain.",
        },
        {
            "id": f"id-d-{nonce}",
            "category": categories[1],
            "product_name": f"Quote {nonce}",
            "review_text": "L\\u2019été, c\\u2019est bon!",
        },
        {
            "id": f"id-e-{nonce}",
            "category": categories[2],
            "product_name": f"Extra {nonce}",
            "review_text": "smile: \\u263A",
        },
    ]

    with open(RAW_DATA, "w", encoding="utf-8") as f:
        for record in records:
            f.write(json.dumps(record, ensure_ascii=False) + "\n")

    for path in (SQL_PATH, REPORT_PATH, DB_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    build_and_run_submission()

    assert os.path.isfile(SQL_PATH), "The executed Rust binary did not generate /home/user/insert.sql."
    assert os.path.isfile(REPORT_PATH), "The executed Rust binary did not generate /home/user/report.md."

    with open(REPORT_PATH, "r", encoding="utf-8") as f:
        actual_report = f.read().strip()
    expected_report = "\n".join([
        "# Category Report",
        f"- {categories[0]}: 2 reviews",
        f"- {categories[1]}: 1 reviews",
        f"- {categories[2]}: 2 reviews",
    ])
    assert actual_report == expected_report, f"Generated report is incorrect.\nExpected:\n{expected_report}\nActual:\n{actual_report}"

    with open(SQL_PATH, "r", encoding="utf-8") as f:
        sql_content = f.read()
    assert "create table" in sql_content.lower(), "Generated insert.sql lacks CREATE TABLE."
    assert re.search(r"insert\s+into\s+reviews\s+values", sql_content, re.IGNORECASE), \
        "Generated insert.sql lacks standard INSERT INTO reviews VALUES statements."

    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    sqlite_result = subprocess.run(
        ["sqlite3", DB_PATH],
        input=sql_content,
        text=True,
        capture_output=True,
        timeout=60,
    )
    assert sqlite_result.returncode == 0, f"sqlite3 could not execute generated insert.sql: {sqlite_result.stderr}"

    expected_rows = {
        f"id-a-{nonce}": (categories[2], f"O'Brien {nonce}", "café and déjà vu"),
        f"id-b-{nonce}": (categories[0], f"Model\\u0041-{nonce}", "Great—value"),
        f"id-c-{nonce}": (categories[0], f"Plain {nonce}", "It is still plain."),
        f"id-d-{nonce}": (categories[1], f"Quote {nonce}", "L’été, c’est bon!"),
        f"id-e-{nonce}": (categories[2], f"Extra {nonce}", "smile: ☺"),
    }

    conn = sqlite3.connect(DB_PATH)
    try:
        schema = conn.execute("PRAGMA table_info(reviews)").fetchall()
        assert [(row[1], row[2].upper()) for row in schema] == [
            ("id", "TEXT"),
            ("category", "TEXT"),
            ("product_name", "TEXT"),
            ("review_text", "TEXT"),
        ], f"reviews table schema is incorrect: {schema}"
        rows = conn.execute("SELECT id, category, product_name, review_text FROM reviews").fetchall()
    finally:
        conn.close()

    actual_rows = {str(row[0]): (row[1], row[2], row[3]) for row in rows}
    assert actual_rows == expected_rows, f"Generated SQL/database rows are incorrect.\nExpected: {expected_rows}\nActual: {actual_rows}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

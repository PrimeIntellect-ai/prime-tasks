#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import re
import shutil
import sqlite3
import subprocess
import tempfile

SCRIPT_PATH = "/home/user/analyze_backups.sh"
TSV_PATH = "/home/user/user_storage.tsv"
DB_PATH = "/home/user/data/users.sqlite"
DOCS_PATH = "/home/user/data/docs.jsonl"
ACCESS_PATH = "/home/user/data/access.csv"


def run_pipeline():
    if os.path.lexists(TSV_PATH):
        if os.path.isdir(TSV_PATH) and not os.path.islink(TSV_PATH):
            shutil.rmtree(TSV_PATH)
        else:
            os.unlink(TSV_PATH)
    result = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"analyze_backups.sh exited with {result.returncode}. "
        f"stdout: {result.stdout!r}; stderr: {result.stderr!r}"
    )
    assert os.path.isfile(TSV_PATH), "The script did not generate /home/user/user_storage.tsv."


def read_tsv_rows():
    with open(TSV_PATH, "r", encoding="utf-8") as f:
        return [line.rstrip("\r\n") for line in f if line.strip()]


def derive_expected(db_path, docs_path, access_path):
    with sqlite3.connect(db_path) as conn:
        users = {
            str(user_id): (name, department)
            for user_id, name, department in conn.execute(
                "SELECT id, name, department FROM users"
            )
        }

    docs = {}
    with open(docs_path, "r", encoding="utf-8") as f:
        for line in f:
            if line.strip():
                doc = json.loads(line)
                docs[str(doc["doc_id"])] = int(doc["size_bytes"])

    totals = {}
    with open(access_path, "r", encoding="utf-8", newline="") as f:
        for row in csv.reader(f):
            assert len(row) == 2
            user_id, doc_id = row
            if user_id in users and doc_id in docs:
                totals[user_id] = totals.get(user_id, 0) + docs[doc_id]

    expected = [
        (users[user_id][0], users[user_id][1], total)
        for user_id, total in totals.items()
    ]
    return sorted(expected, key=lambda row: (-row[2], row[0]))


def test_analyze_backups_script_exists_and_executable():
    script_path = "/home/user/analyze_backups.sh"
    assert os.path.isfile(script_path), f"The script {script_path} does not exist."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."


def test_user_storage_tsv_content():
    run_pipeline()

    tsv_path = "/home/user/user_storage.tsv"
    assert os.path.isfile(tsv_path), f"The output file {tsv_path} does not exist. Did you run the script?"

    with open(tsv_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "Charlie\tEngineering\t10000",
        "Bob\tEngineering\t5512",
        "Alice\tHR\t3372"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {tsv_path}, but found {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch. Expected '{expected}', got '{actual}'."


def test_pipeline_on_altered_inputs():
    paths = [DB_PATH, DOCS_PATH, ACCESS_PATH]
    originals = {path: open(path, "rb").read() for path in paths}

    rng = random.SystemRandom()
    first = rng.randint(111, 9000)
    second = rng.randint(111, 9000)
    tied_total = first + second
    larger = tied_total + rng.randint(17, 5000)

    try:
        if os.path.lexists(DB_PATH):
            os.unlink(DB_PATH)
        with sqlite3.connect(DB_PATH) as conn:
            conn.execute(
                "CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, department TEXT, status TEXT)"
            )
            conn.executemany(
                "INSERT INTO users VALUES (?, ?, ?, ?)",
                [
                    (17, "Zelda", "Ops", "active"),
                    (28, "Aaron", "Research", "inactive"),
                    (39, "Miro", "Finance", "active"),
                    (40, "NoDocs", "Sales", "active"),
                ],
            )

        documents = [
            {"doc_id": "alpha", "size_bytes": first, "type": "pdf"},
            {"doc_id": "beta", "size_bytes": second, "type": "txt"},
            {"doc_id": "gamma", "size_bytes": tied_total, "type": "bin"},
            {"doc_id": "delta", "size_bytes": larger, "type": "zip"},
            {"doc_id": "unowned", "size_bytes": rng.randint(1, 9999), "type": "dat"},
        ]
        with open(DOCS_PATH, "w", encoding="utf-8") as f:
            for document in documents:
                f.write(json.dumps(document) + "\n")

        with open(ACCESS_PATH, "w", encoding="utf-8", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerows([
                (17, "alpha"),
                (17, "beta"),
                (28, "gamma"),
                (39, "delta"),
            ])

        expected = derive_expected(DB_PATH, DOCS_PATH, ACCESS_PATH)
        run_pipeline()
        lines = read_tsv_rows()

        actual = []
        for line_number, line in enumerate(lines, 1):
            columns = line.split("\t")
            assert len(columns) == 3, (
                f"Line {line_number} must contain exactly three tab-separated columns, got {line!r}."
            )
            try:
                total = int(columns[2])
            except ValueError:
                raise AssertionError(f"Line {line_number} has a non-integer total_bytes value: {columns[2]!r}")
            actual.append((columns[0], columns[1], total))

        assert actual == expected, f"Altered-input output mismatch. Expected {expected!r}, got {actual!r}."
    finally:
        os.makedirs("/home/user/data", exist_ok=True)
        for path, content in originals.items():
            if os.path.lexists(path):
                if os.path.isdir(path) and not os.path.islink(path):
                    shutil.rmtree(path)
                else:
                    os.unlink(path)
            with open(path, "wb") as f:
                f.write(content)
        if os.path.isfile(SCRIPT_PATH) and os.access(SCRIPT_PATH, os.X_OK):
            subprocess.run(
                [SCRIPT_PATH], cwd="/home/user", stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL, timeout=30, check=False
            )


def test_index_strategy_sql():
    sql_path = "/home/user/index_strategy.sql"
    assert os.path.isfile(sql_path), f"The file {sql_path} does not exist."

    with open(sql_path, "r") as f:
        content = f.read().strip()

    # Normalize whitespace and case
    normalized_content = re.sub(r'\s+', ' ', content).lower()

    # Check for the correct index creation
    # It must be a covering index for: WHERE department = ? AND status = 'active' ORDER BY name
    # So the index columns should be (department, status, name) or (status, department, name)
    assert "create index" in normalized_content, "The SQL statement must be a CREATE INDEX statement."
    assert "idx_dept_status_name" in normalized_content, "The index must be named 'idx_dept_status_name'."
    assert "on users" in normalized_content, "The index must be on the 'users' table."

    # Extract the column list
    match = re.search(r'\((.*?)\)', normalized_content)
    assert match is not None, "Could not find column list in parentheses."

    columns = [col.strip() for col in match.group(1).split(',')]
    assert len(columns) == 3, f"Expected exactly 3 columns in the index, found {len(columns)}."

    # The order of the first two columns (department, status) doesn't strictly matter for equality,
    # but 'name' must be the last column to optimize the ORDER BY.
    assert set(columns[:2]) == {"department", "status"}, "The first two columns of the index must be 'department' and 'status' (in any order)."
    assert columns[2] == "name", "The third column of the index must be 'name' to optimize the ORDER BY clause."

    # Execute the submitted artifact as one SQL statement against a clean copy of the database.
    with tempfile.TemporaryDirectory() as tmpdir:
        copied_db = os.path.join(tmpdir, "users.sqlite")
        shutil.copy2(DB_PATH, copied_db)
        with sqlite3.connect(copied_db) as conn:
            try:
                conn.execute(content)
            except sqlite3.Error as exc:
                raise AssertionError(f"index_strategy.sql is not one valid executable CREATE INDEX statement: {exc}")

            index_rows = conn.execute("PRAGMA index_info('idx_dept_status_name')").fetchall()
            actual_columns = [row[2].lower() for row in index_rows]
            assert actual_columns == columns, (
                f"Created index columns {actual_columns!r} do not match the required strategy {columns!r}."
            )

            plan = conn.execute(
                "EXPLAIN QUERY PLAN SELECT name FROM users "
                "WHERE department = ? AND status = 'active' ORDER BY name",
                ("Engineering",),
            ).fetchall()
            plan_text = " ".join(str(row[3]).lower() for row in plan)
            assert "idx_dept_status_name" in plan_text, f"Query planner did not use the submitted index: {plan_text}"
            assert "covering index" in plan_text, f"The submitted index does not cover the roster query: {plan_text}"
            assert "temp b-tree" not in plan_text, f"The submitted index did not optimize ORDER BY: {plan_text}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

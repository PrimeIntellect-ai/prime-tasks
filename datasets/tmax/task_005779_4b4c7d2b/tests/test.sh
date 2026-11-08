#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import sqlite3
import subprocess
import tempfile
from pathlib import Path

import pytest

REPORT_PATH = Path("/home/user/report.json")
WORKSPACE = Path("/home/user/workspace")
BACKUP_DIR = Path("/home/user/backups")
DATABASES = [BACKUP_DIR / f"shard_{i}.db" for i in range(1, 4)]
BINARY = Path("/tmp/submission_db_analyzer")
EXPECTED_INDEX = "CREATE INDEX idx_orders_user_id ON orders(user_id);"


def build_program():
    assert (WORKSPACE / "go.mod").is_file(), "Go module /home/user/workspace/go.mod is missing"
    go_sources = [p for p in WORKSPACE.rglob("*.go") if p.is_file()]
    assert go_sources, "No Go source files were found in /home/user/workspace"

    if BINARY.exists():
        BINARY.unlink()
    result = subprocess.run(
        ["go", "build", "-o", str(BINARY), "."],
        cwd=str(WORKSPACE),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert result.returncode == 0, f"Go program did not compile:\n{result.stdout}\n{result.stderr}"
    assert BINARY.is_file() and os.access(BINARY, os.X_OK), "Compilation did not produce an executable"


def run_program():
    if REPORT_PATH.exists():
        REPORT_PATH.unlink()
    result = subprocess.run(
        [str(BINARY)],
        cwd=str(WORKSPACE),
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, f"Compiled Go program failed:\n{result.stdout}\n{result.stderr}"
    assert REPORT_PATH.is_file(), f"Report file not found at {REPORT_PATH} after executing the program"
    try:
        with REPORT_PATH.open("r") as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"File {REPORT_PATH} is not valid JSON: {exc}")


def assert_required_keys(report):
    assert "total_users" in report, "Key 'total_users' missing from report"
    assert "total_orders" in report, "Key 'total_orders' missing from report"
    assert "missing_indexes" in report, "Key 'missing_indexes' missing from report"
    assert isinstance(report["missing_indexes"], list), "'missing_indexes' should be a list"


def derive_counts():
    users = 0
    orders = 0
    for db in DATABASES:
        with sqlite3.connect(db) as conn:
            users += conn.execute("SELECT COUNT(*) FROM users").fetchone()[0]
            orders += conn.execute("SELECT COUNT(*) FROM orders").fetchone()[0]
    return users, orders


def derive_missing_indexes():
    statements = set()
    for db in DATABASES:
        with sqlite3.connect(db) as conn:
            foreign_keys = conn.execute("PRAGMA foreign_key_list('orders')").fetchall()
            indexes = conn.execute("PRAGMA index_list('orders')").fetchall()
            indexed_first_columns = set()
            for index in indexes:
                index_name = index[1]
                columns = conn.execute(
                    'PRAGMA index_info("%s")' % index_name.replace('"', '""')
                ).fetchall()
                if columns:
                    indexed_first_columns.add(columns[0][2])
            for fk in foreign_keys:
                column = fk[3]
                if column not in indexed_first_columns:
                    statements.add(f"CREATE INDEX idx_orders_{column} ON orders({column});")
    return sorted(statements)


def test_compiled_program_analyzes_databases_and_generates_report():
    for db in DATABASES:
        assert db.is_file(), f"Required database is missing: {db}"

    saved_dir = Path(tempfile.mkdtemp(prefix="saved_shards_"))
    for db in DATABASES:
        shutil.copy2(db, saved_dir / db.name)

    try:
        build_program()

        # Preserve the original verifier's exact assertions on the supplied shards.
        report = run_program()
        assert_required_keys(report)
        assert report["total_users"] == 5, f"Expected total_users to be 5, got {report['total_users']}"
        assert report["total_orders"] == 6, f"Expected total_orders to be 6, got {report['total_orders']}"
        missing_indexes = report["missing_indexes"]
        assert len(missing_indexes) == 1, f"Expected exactly 1 missing index, got {len(missing_indexes)}"
        assert missing_indexes[0] == EXPECTED_INDEX, (
            f"Expected missing index statement '{EXPECTED_INDEX}', got '{missing_indexes[0]}'"
        )

        # Change row counts and add the required index to every shard. A freshly
        # executed analyzer must derive both the new totals and the empty strategy list.
        for shard_number, db in enumerate(DATABASES, start=1):
            with sqlite3.connect(db) as conn:
                user_id = 10000 + shard_number
                conn.execute("INSERT INTO users(id, name) VALUES (?, ?)", (user_id, f"Verifier User {shard_number}"))
                for n in range(shard_number):
                    conn.execute(
                        "INSERT INTO orders(id, user_id, amount, status) VALUES (?, ?, ?, ?)",
                        (20000 + shard_number * 10 + n, user_id, 10.0 + n, "verification"),
                    )
                conn.execute("CREATE INDEX IF NOT EXISTS idx_orders_user_id ON orders(user_id)")

        expected_users, expected_orders = derive_counts()
        expected_missing = derive_missing_indexes()
        report = run_program()
        assert_required_keys(report)
        assert report["total_users"] == expected_users
        assert report["total_orders"] == expected_orders
        assert report["missing_indexes"] == expected_missing
        assert expected_missing == [], "Verifier setup failed to index every shard"

        # Remove the index from only one shard to ensure all shards are inspected.
        with sqlite3.connect(DATABASES[2]) as conn:
            conn.execute("DROP INDEX idx_orders_user_id")

        expected_users, expected_orders = derive_counts()
        expected_missing = derive_missing_indexes()
        report = run_program()
        assert_required_keys(report)
        assert report["total_users"] == expected_users
        assert report["total_orders"] == expected_orders
        assert report["missing_indexes"] == expected_missing
        assert expected_missing == [EXPECTED_INDEX]
    finally:
        for db in DATABASES:
            saved = saved_dir / db.name
            if saved.exists():
                shutil.copy2(saved, db)
        shutil.rmtree(saved_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

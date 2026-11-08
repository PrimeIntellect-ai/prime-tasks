#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import csv
import os
import re
import sqlite3
import subprocess
from decimal import Decimal

import pytest

SOURCE = "/home/user/etl_processor.c"
EXE = "/home/user/etl_processor"
DB = "/home/user/analytics.db"
REPORT = "/home/user/report.out"
RAW = "/home/user/raw_events.csv"


def read_csv_rows(path=RAW):
    rows = []
    with open(path, newline="") as f:
        for row in csv.reader(f):
            assert len(row) == 4
            rows.append((row[0], int(row[1]), row[2], Decimal(row[3])))
    return rows


def expected_report(rows):
    totals = collections.defaultdict(Decimal)
    for _, user_id, event_type, item_price in rows:
        if event_type == "purchase":
            totals[user_id] += item_price
    ranked = sorted(totals.items(), key=lambda item: item[1], reverse=True)[5:10]
    return [f"User {user_id} spent {total:.2f}" for user_id, total in ranked]


def remove_outputs():
    for path in (DB, REPORT):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def run_processor():
    remove_outputs()
    subprocess.run(
        [EXE],
        cwd="/home/user",
        stdin=subprocess.DEVNULL,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        check=True,
    )


def normalized_rows(rows):
    return collections.Counter(
        (timestamp, int(user_id), event_type, int(round(float(price) * 100)))
        for timestamp, user_id, event_type, price in rows
    )


def assert_database_matches(rows):
    assert os.path.isfile(DB), f"{DB} does not exist."
    conn = sqlite3.connect(DB)
    try:
        schema = conn.execute("PRAGMA table_info(events)").fetchall()
        assert [(r[1], r[2].upper()) for r in schema] == [
            ("timestamp", "TEXT"),
            ("user_id", "INTEGER"),
            ("event_type", "TEXT"),
            ("item_price", "REAL"),
        ], f"Incorrect events schema: {schema}"

        count = conn.execute(
            "SELECT count(*) FROM sqlite_master WHERE type='index' AND name='idx_performance'"
        ).fetchone()[0]
        assert count == 1, "Index 'idx_performance' not found in the database."

        index_table = conn.execute(
            "SELECT tbl_name FROM sqlite_master WHERE type='index' AND name='idx_performance'"
        ).fetchone()
        assert index_table == ("events",), "idx_performance is not an index on events."

        index_columns = [r[2] for r in conn.execute("PRAGMA index_info(idx_performance)")]
        assert index_columns and index_columns[0] == "event_type", (
            f"idx_performance must lead with event_type; got {index_columns}"
        )
        assert "user_id" in index_columns[1:], (
            f"idx_performance must also support grouping by user_id; got {index_columns}"
        )

        actual = conn.execute(
            "SELECT timestamp, user_id, event_type, item_price FROM events"
        ).fetchall()
        assert len(actual) == len(rows), (
            f"events contains {len(actual)} rows, expected {len(rows)}"
        )
        assert normalized_rows(actual) == normalized_rows(rows), (
            "The events table does not exactly contain all CSV rows."
        )
    finally:
        conn.close()


def assert_report_matches(rows):
    assert os.path.isfile(REPORT), f"{REPORT} does not exist."
    with open(REPORT) as f:
        actual = f.read().splitlines()
    assert actual == expected_report(rows), (
        f"Incorrect report. Expected {expected_report(rows)}, got {actual}"
    )


ORIGINAL_ROWS = read_csv_rows()


def test_c_source_exists():
    """Test that the C source code file exists and uses the required SQLite API."""
    assert os.path.isfile(SOURCE), f"{SOURCE} does not exist."
    source = open(SOURCE, errors="replace").read()
    assert re.search(r"#\s*include\s*[<\"]sqlite3\.h[>\"]", source)
    assert re.search(r"\bsqlite3_open(?:_v2)?\s*\(", source)
    assert re.search(r"\bsqlite3_prepare_v2\s*\(", source)
    assert re.search(r"\bsqlite3_step\s*\(", source)
    upper = source.upper()
    assert "BEGIN" in upper and "COMMIT" in upper, "ETL must use a transaction."


def test_executable_exists():
    """Test that the compiled executable exists, is executable, and regenerates outputs."""
    assert os.path.isfile(EXE), f"{EXE} does not exist."
    assert os.access(EXE, os.X_OK), f"{EXE} is not executable."
    with open(EXE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{EXE} is not a compiled ELF executable."
    run_processor()


def test_database_and_index_exist():
    """Validate the required schema, index columns, and complete ingested dataset."""
    assert_database_matches(ORIGINAL_ROWS)


def test_report_content():
    """Test that report.out contains the correct paginated results."""
    expected_lines = [
        "User 80 spent 2901.69",
        "User 60 spent 2831.75",
        "User 70 spent 2822.40",
        "User 50 spent 2800.72",
        "User 19 spent 2742.02",
    ]
    assert os.path.isfile(REPORT), f"{REPORT} does not exist."
    with open(REPORT) as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    assert actual_lines == expected_lines, (
        f"Content of {REPORT} does not match expected output.\n"
        f"Expected: {expected_lines}\nActual: {actual_lines}"
    )
    assert expected_report(ORIGINAL_ROWS) == expected_lines


def test_executable_performs_etl_on_changed_input():
    """Exercise the submitted executable on verifier-generated data."""
    original_raw = open(RAW, "rb").read()
    rows = []
    for user_id in range(1, 16):
        rows.append((f"2024-02-{user_id:02d}T00:00:00", user_id, "purchase", Decimal(1000 - 37 * user_id) + Decimal("0.25")))
        rows.append((f"2024-03-{user_id:02d}T00:00:00", user_id, "purchase", Decimal("10.50")))
        rows.append((f"2024-04-{user_id:02d}T00:00:00", user_id, "view", Decimal("0.00")))
        rows.append((f"2024-05-{user_id:02d}T00:00:00", user_id, "Purchase", Decimal("9999.99")))
    try:
        with open(RAW, "w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            for timestamp, user_id, event_type, price in rows:
                writer.writerow([timestamp, user_id, event_type, f"{price:.2f}"])
        run_processor()
        assert_database_matches(rows)
        assert_report_matches(rows)
    finally:
        with open(RAW, "wb") as f:
            f.write(original_raw)
        run_processor()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

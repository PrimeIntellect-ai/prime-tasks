#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import sqlite3
import pytest

DB_PATH = "/home/user/analysis.db"
INPUT_PATH = "/home/user/transactions.csv"
INDEX_PATH = "/home/user/indexes.sql"
OUTPUT_PATH = "/home/user/peak_concurrency.csv"

EXPECTED_INPUT_ROWS = [
    (1, 100, 10, 20),
    (2, 100, 15, 25),
    (3, 100, 22, 30),
    (4, 101, 5, 10),
    (5, 101, 10, 15),
    (6, 101, 10, 12),
    (7, 102, 1, 100),
    (8, 102, 2, 3),
    (9, 102, 4, 5),
]


def normalize_sql(sql):
    return re.sub(r"\s+", " ", sql.strip().rstrip(";")).casefold()


def explicit_indexes(conn):
    rows = conn.execute(
        "SELECT name, tbl_name, sql FROM sqlite_master "
        "WHERE type='index' AND sql IS NOT NULL ORDER BY name"
    ).fetchall()
    result = {}
    for name, table, sql in rows:
        columns = tuple(
            row[0] for row in conn.execute(
                "SELECT name FROM pragma_index_info(?) ORDER BY seqno", (name,)
            ).fetchall()
        )
        unique = conn.execute(
            "SELECT [unique] FROM pragma_index_list(?) WHERE name = ?",
            (table, name),
        ).fetchone()
        result[name] = {
            "table": table,
            "sql": normalize_sql(sql),
            "columns": columns,
            "unique": unique[0] if unique else None,
        }
    return result


def test_analysis_db_exists_and_transactions_imported():
    assert os.path.exists(DB_PATH), f"The database file {DB_PATH} is missing."
    assert os.path.isfile(DB_PATH), f"The path {DB_PATH} is not a file."

    try:
        conn = sqlite3.connect(DB_PATH)
        table = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name='transactions'"
        ).fetchone()
        assert table is not None, "The 'transactions' table is missing from analysis.db."

        columns = [row[1] for row in conn.execute("PRAGMA table_info(transactions)")]
        assert columns == ["tx_id", "resource_id", "start_ts", "end_ts"], (
            f"Unexpected transactions schema: {columns}"
        )
        rows = conn.execute(
            "SELECT tx_id, resource_id, start_ts, end_ts FROM transactions ORDER BY tx_id"
        ).fetchall()
        assert rows == EXPECTED_INPUT_ROWS, (
            "The transactions table does not contain the complete, unmodified CSV data."
        )
        conn.close()
    except sqlite3.Error as e:
        pytest.fail(f"Failed to connect to analysis.db or query it: {e}")


def test_source_csv_is_unmodified():
    assert os.path.isfile(INPUT_PATH), f"The input file {INPUT_PATH} is missing."
    with open(INPUT_PATH, newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["tx_id", "resource_id", "start_ts", "end_ts"]
        try:
            rows = [tuple(map(int, row)) for row in reader if row]
        except (ValueError, TypeError) as e:
            pytest.fail(f"The input CSV contains invalid values: {e}")
    assert rows == EXPECTED_INPUT_ROWS, "The provided transactions.csv was modified."


def test_indexes_sql_exists_valid_and_matches_database():
    assert os.path.exists(INDEX_PATH), f"The file {INDEX_PATH} is missing."
    assert os.path.isfile(INDEX_PATH), f"The path {INDEX_PATH} is not a file."
    with open(INDEX_PATH) as f:
        content = f.read()

    upper = content.upper()
    assert "CREATE " in upper and " INDEX " in upper, (
        "The file indexes.sql does not contain a CREATE INDEX statement."
    )

    scratch = sqlite3.connect(":memory:")
    scratch.execute(
        "CREATE TABLE transactions "
        "(tx_id INTEGER, resource_id INTEGER, start_ts INTEGER, end_ts INTEGER)"
    )
    try:
        scratch.executescript(content)
    except sqlite3.Error as e:
        pytest.fail(f"indexes.sql is not executable SQL: {e}")

    extra_objects = scratch.execute(
        "SELECT type, name FROM sqlite_master "
        "WHERE name NOT LIKE 'sqlite_%' AND NOT (type='table' AND name='transactions') "
        "AND type != 'index'"
    ).fetchall()
    assert not extra_objects, f"indexes.sql creates unexpected objects: {extra_objects}"

    scripted = explicit_indexes(scratch)
    assert scripted, "indexes.sql did not create any actual index."
    assert all(item["table"] == "transactions" for item in scripted.values()), (
        "Every saved CREATE INDEX statement must index the transactions table."
    )
    assert any(
        len(item["columns"]) >= 2
        and item["columns"][0] == "resource_id"
        and any(c in ("start_ts", "end_ts") for c in item["columns"][1:])
        for item in scripted.values()
    ), "No index combines resource_id with a temporal bound."

    actual_conn = sqlite3.connect(DB_PATH)
    actual = explicit_indexes(actual_conn)
    actual_conn.close()
    scratch.close()

    assert set(actual) == set(scripted), (
        "The actual database indexes do not exactly match the indexes saved in indexes.sql."
    )
    for name in scripted:
        assert actual[name] == scripted[name], (
            f"Database index {name!r} does not match its saved CREATE INDEX statement."
        )


def test_peak_concurrency_csv():
    assert os.path.exists(OUTPUT_PATH), f"The file {OUTPUT_PATH} is missing."
    assert os.path.isfile(OUTPUT_PATH), f"The path {OUTPUT_PATH} is not a file."

    conn = sqlite3.connect(DB_PATH)
    expected = conn.execute("""
        WITH points AS (
            SELECT resource_id, start_ts AS ts FROM transactions
            UNION
            SELECT resource_id, end_ts AS ts FROM transactions
        ), concurrency AS (
            SELECT p.resource_id, p.ts,
                   (SELECT COUNT(*)
                    FROM transactions AS t
                    WHERE t.resource_id = p.resource_id
                      AND t.start_ts <= p.ts
                      AND t.end_ts >= p.ts) AS active_count
            FROM points AS p
        )
        SELECT resource_id, MAX(active_count) AS max_concurrent
        FROM concurrency
        GROUP BY resource_id
        ORDER BY resource_id
    """).fetchall()
    conn.close()

    with open(OUTPUT_PATH, newline="") as f:
        rows = list(csv.reader(f))

    assert rows, "peak_concurrency.csv is empty."
    assert all(len(row) == 2 for row in rows), "Output must contain exactly two columns."
    try:
        actual = [(int(row[0]), int(row[1])) for row in rows]
    except ValueError as e:
        pytest.fail(f"Output contains a header or non-integer value: {e}")

    assert actual == sorted(actual, key=lambda row: row[0]), (
        "Results are not sorted by resource_id ascending."
    )
    assert actual == expected, (
        f"Output does not match peak concurrency recomputed from transactions: "
        f"expected {expected}, got {actual}."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

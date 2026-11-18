#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import sqlite3
import pytest


def test_deadlock_report_exists_and_correct():
    report_path = "/home/user/deadlock_report.json"
    assert os.path.isfile(report_path), f"File {report_path} is missing."

    with open(report_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {report_path} is not valid JSON.")

    assert "deadlock_cycle" in data, "Key 'deadlock_cycle' is missing in the report."
    cycle = data["deadlock_cycle"]

    assert isinstance(cycle, list), "'deadlock_cycle' must be an array."

    expected_cycle = ["U_ALICE", "U_BOB", "U_CHARLIE", "U_DIANA"]
    assert cycle == expected_cycle, f"Expected deadlock cycle {expected_cycle}, but got {cycle}."


def _quote_identifier(identifier):
    return '"' + identifier.replace('"', '""') + '"'


def test_schema_sql_exists_is_executable_and_defines_lock_indexes():
    schema_path = "/home/user/schema.sql"
    assert os.path.isfile(schema_path), f"File {schema_path} is missing."

    with open(schema_path, "r") as f:
        content = f.read()
    upper_content = content.upper()

    # Preserve the original assertions.
    assert "CREATE TABLE" in upper_content, "schema.sql does not contain CREATE TABLE statements."
    assert "CREATE INDEX" in upper_content, "schema.sql does not contain CREATE INDEX statements as requested to optimize the join."
    assert "INDEX" in upper_content, "No indexes found in schema.sql."

    conn = sqlite3.connect(":memory:")
    try:
        # The submitted artifact must be executable DDL, not comments or fragments.
        try:
            conn.executescript(content)
        except sqlite3.Error as exc:
            pytest.fail(f"schema.sql is not valid executable SQLite DDL: {exc}")

        table_rows = conn.execute(
            "SELECT name FROM sqlite_master "
            "WHERE type = 'table' AND name NOT LIKE 'sqlite_%'"
        ).fetchall()

        required_lock_columns = {
            "timestamp", "trx_id", "resource_id", "lock_mode", "state"
        }
        lock_tables = []
        for (table_name,) in table_rows:
            columns = {
                row[1].lower()
                for row in conn.execute(
                    f"PRAGMA table_info({_quote_identifier(table_name)})"
                ).fetchall()
            }
            if required_lock_columns.issubset(columns):
                lock_tables.append(table_name)

        assert lock_tables, (
            "schema.sql must create a lock-data table containing timestamp, "
            "trx_id, resource_id, lock_mode, and state columns."
        )

        usable_indexes = []
        for table_name in lock_tables:
            for index_row in conn.execute(
                f"PRAGMA index_list({_quote_identifier(table_name)})"
            ).fetchall():
                index_name = index_row[1]
                index_sql_row = conn.execute(
                    "SELECT sql FROM sqlite_master WHERE type = 'index' AND name = ?",
                    (index_name,),
                ).fetchone()
                # Ignore implicit indexes from constraints: the task explicitly asks
                # for CREATE INDEX statements.
                if not index_sql_row or index_sql_row[0] is None:
                    continue

                index_columns = [
                    row[2].lower() if row[2] is not None else None
                    for row in conn.execute(
                        f"PRAGMA index_info({_quote_identifier(index_name)})"
                    ).fetchall()
                ]

                # resource_id must be searchable without an unrelated leading key.
                # Both (resource_id, ...) and (state, resource_id, ...) optimize the
                # wait-for join because state is filtered to WAITING or GRANTED.
                if index_columns and (
                    index_columns[0] == "resource_id"
                    or (
                        len(index_columns) >= 2
                        and index_columns[0] == "state"
                        and index_columns[1] == "resource_id"
                    )
                ):
                    usable_indexes.append((table_name, index_name))

        assert usable_indexes, (
            "schema.sql must create an explicit index on the lock table that can "
            "optimize resource_id matching, such as (resource_id, state) or "
            "(state, resource_id)."
        )
    finally:
        conn.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

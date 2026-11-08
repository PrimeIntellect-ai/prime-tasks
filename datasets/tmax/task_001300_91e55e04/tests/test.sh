#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import sqlite3
import subprocess
import tempfile
import uuid
import pytest

HOME = "/home/user"
DB = f"{HOME}/audit.db"
SOURCE = f"{HOME}/audit_tool.c"
BINARY = f"{HOME}/audit_tool"
OPTIMIZE = f"{HOME}/optimize.sql"
PLAN = f"{HOME}/query_plan.txt"
CENTRALITY = f"{HOME}/highest_centrality.txt"

QUERY = """
SELECT s.name AS sender_name, r.name AS receiver_name
FROM messages AS m
JOIN employees AS s ON s.id = m.sender_id
JOIN employees AS r ON r.id = m.receiver_id
WHERE m.flagged = 1
  AND s.department = 'Finance'
  AND r.department = 'Finance'
"""


def index_definitions(conn):
    result = set()
    rows = conn.execute("""
        SELECT name, tbl_name FROM sqlite_master
        WHERE type='index' AND sql IS NOT NULL
          AND tbl_name IN ('employees', 'messages')
    """).fetchall()
    for name, table in rows:
        columns = tuple(row[2].lower() for row in conn.execute(
            'PRAGMA index_info("%s")' % name.replace('"', '""')
        ))
        result.add((name.lower(), table.lower(), columns))
    return result


def plan_operations(text):
    operations = []
    for line in text.splitlines():
        match = re.search(r"\b(SCAN|SEARCH)\s+[^\s|`]+\s*(.*)", line.upper())
        if match:
            operations.append(" ".join((match.group(1) + " " + match.group(2)).split()))
    return operations


def test_optimize_sql_exists():
    assert os.path.exists(OPTIMIZE), "The file /home/user/optimize.sql is missing."
    with open(OPTIMIZE, "r") as f:
        content = f.read().upper()
    assert "CREATE INDEX" in content, "/home/user/optimize.sql does not contain CREATE INDEX statements."


def test_indexes_applied_to_db():
    conn = sqlite3.connect(DB)
    indexes = conn.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name IN ('employees', 'messages')").fetchall()
    conn.close()
    assert len(indexes) > 0, "No indexes were applied to the employees or messages tables in audit.db."

    with open(OPTIMIZE, "r") as f:
        script = f.read()
    with tempfile.TemporaryDirectory() as td:
        clean_db = os.path.join(td, "clean.db")
        clean = sqlite3.connect(clean_db)
        clean.executescript("""
            CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, department TEXT);
            CREATE TABLE messages (id INTEGER PRIMARY KEY, sender_id INTEGER, receiver_id INTEGER, timestamp DATETIME, flagged INTEGER);
        """)
        clean.executescript(script)
        generated = index_definitions(clean)
        clean.close()

    assert any(table == "employees" and "department" in columns for _, table, columns in generated), \
        "optimize.sql must create a useful department index on employees."
    assert any(table == "messages" and set(columns) & {"flagged", "sender_id", "receiver_id"} for _, table, columns in generated), \
        "optimize.sql must create a useful index on messages for the filtered join."

    actual = sqlite3.connect(DB)
    applied = index_definitions(actual)
    actual.close()
    assert generated <= applied, "The indexes created by optimize.sql were not all applied to audit.db."


def test_query_plan_extracted():
    assert os.path.exists(PLAN), "The file /home/user/query_plan.txt is missing."
    with open(PLAN, "r") as f:
        content = f.read()
    assert len(content.strip()) > 0, "The query_plan.txt file is empty."
    assert any(keyword in content.upper() for keyword in ["SCAN", "SEARCH", "USING INDEX", "COVERING INDEX"]), \
        "The query_plan.txt file does not appear to contain valid EXPLAIN QUERY PLAN output."

    conn = sqlite3.connect(DB)
    expected_details = [row[3] for row in conn.execute("EXPLAIN QUERY PLAN " + QUERY)]
    explicit_indexes = {name.upper() for name, _, _ in index_definitions(conn)}
    conn.close()

    expected_ops = plan_operations("\n".join(expected_details))
    supplied_ops = plan_operations(content)
    assert supplied_ops, "query_plan.txt contains no parseable EXPLAIN QUERY PLAN operations."
    assert sorted(supplied_ops) == sorted(expected_ops), \
        "query_plan.txt is not the execution plan for the required optimized query."
    assert not any(op.startswith("SCAN ") for op in supplied_ops), \
        "The required query plan still performs a full table scan."
    assert any(name in " ".join(expected_ops) for name in explicit_indexes), \
        "The required query does not use any index created by optimize.sql."


def test_audit_tool_compiled():
    assert os.path.exists(BINARY), "The compiled binary /home/user/audit_tool is missing."
    assert os.access(BINARY, os.X_OK), "The file /home/user/audit_tool is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/audit_tool is not a compiled executable."
    assert os.path.isfile(SOURCE), "/home/user/audit_tool.c is missing."


def test_highest_centrality():
    assert os.path.exists(CENTRALITY), "The file /home/user/highest_centrality.txt is missing."
    with open(CENTRALITY, "r") as f:
        content = f.read().strip()
    assert content == "Alice", f"Expected the highest centrality employee to be 'Alice', but got '{content}'."


def create_case(path, names, reverse=False):
    winner, b, c, d, hr = names
    conn = sqlite3.connect(path)
    conn.executescript("""
        CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, department TEXT);
        CREATE TABLE messages (id INTEGER PRIMARY KEY, sender_id INTEGER, receiver_id INTEGER, timestamp DATETIME, flagged INTEGER);
    """)
    conn.executemany("INSERT INTO employees VALUES (?, ?, ?)", [
        (1, winner, "Finance"), (2, b, "Finance"), (3, c, "Finance"),
        (4, d, "Finance"), (5, hr, "HR")
    ])
    if not reverse:
        valid = [(1, 2), (3, 1), (1, 4)]
    else:
        valid = [(2, 1), (1, 3), (4, 1)]
    rows = [(s, r, "2026-01-01", 1) for s, r in valid]
    rows += [
        (5, 1, "2026-01-02", 1),  # HR sender
        (1, 5, "2026-01-03", 1),  # HR receiver
        (2, 3, "2026-01-04", 0),  # unflagged Finance message
    ]
    conn.executemany("INSERT INTO messages(sender_id, receiver_id, timestamp, flagged) VALUES (?, ?, ?, ?)", rows)
    with open(OPTIMIZE, "r") as f:
        conn.executescript(f.read())
    conn.commit()
    conn.close()
    return valid


def assert_program_behavior(executable, names, valid):
    if os.path.exists(CENTRALITY):
        os.unlink(CENTRALITY)
    result = subprocess.run([executable], cwd=HOME, text=True, capture_output=True, timeout=10)
    assert result.returncode == 0, f"{executable} failed: {result.stderr}"
    assert os.path.exists(CENTRALITY), f"{executable} did not generate highest_centrality.txt."
    with open(CENTRALITY, "r") as f:
        assert f.read().strip() == names[0], f"{executable} computed the wrong degree-centrality winner."

    output_lines = [line for line in result.stdout.splitlines() if any(name in line for name in names)]
    assert len(output_lines) == len(valid), \
        f"{executable} returned extra or missing records; the query may contain a Cartesian product or bad filter."
    for sender_id, receiver_id in valid:
        sender, receiver = names[sender_id - 1], names[receiver_id - 1]
        matches = [line for line in output_lines
                   if re.search(re.escape(sender) + r".*" + re.escape(receiver), line)]
        assert len(matches) == 1, f"Missing or duplicated filtered edge {sender} -> {receiver}."
    assert names[4] not in result.stdout, "A message involving a non-Finance employee was returned."


def test_program_query_and_centrality_on_derived_inputs():
    with tempfile.TemporaryDirectory() as td:
        rebuilt = os.path.join(td, "audit_tool_rebuilt")
        build = subprocess.run(
            ["gcc", SOURCE, "-o", rebuilt, "-lsqlite3"],
            text=True, capture_output=True, timeout=30
        )
        assert build.returncode == 0, f"audit_tool.c does not compile: {build.stderr}"

        backup_db = os.path.join(td, "audit-backup.db")
        source_conn = sqlite3.connect(DB)
        backup_conn = sqlite3.connect(backup_db)
        source_conn.backup(backup_conn)
        source_conn.close()
        backup_conn.close()
        old_output = None
        if os.path.exists(CENTRALITY):
            with open(CENTRALITY, "rb") as f:
                old_output = f.read()

        try:
            for reverse in (False, True):
                token = uuid.uuid4().hex[:10]
                names = [f"Winner_{token}", f"PeerB_{token}", f"PeerC_{token}",
                         f"PeerD_{token}", f"Outsider_{token}"]
                if os.path.exists(DB):
                    os.unlink(DB)
                valid = create_case(DB, names, reverse)
                assert_program_behavior(BINARY, names, valid)
                assert_program_behavior(rebuilt, names, valid)
        finally:
            if os.path.exists(DB):
                os.unlink(DB)
            shutil.copy2(backup_db, DB)
            if old_output is None:
                if os.path.exists(CENTRALITY):
                    os.unlink(CENTRALITY)
            else:
                with open(CENTRALITY, "wb") as f:
                    f.write(old_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

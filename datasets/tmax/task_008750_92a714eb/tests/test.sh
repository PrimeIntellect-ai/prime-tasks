#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import sqlite3
import stat
import subprocess
import tempfile
import time

import pytest

DB_PATH = "/home/user/graph.db"
JSON_PATH = "/home/user/telemetry.json"
RESULT_PATH = "/home/user/result.txt"
SCRIPT_PATH = "/home/user/fast_query.sh"
SQL_PATH = "/home/user/optimize.sql"


def compute_expected_sum(db_path, json_path):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("""
        SELECT e.target
        FROM edges e
        JOIN nodes n ON e.target = n.id
        WHERE e.source = 1 AND n.status = 'active'
    """)
    intermediates = [row[0] for row in cursor.fetchall()]

    if not intermediates:
        conn.close()
        return 0

    placeholders = ','.join('?' for _ in intermediates)
    cursor.execute(f"""
        SELECT DISTINCT target
        FROM edges
        WHERE source IN ({placeholders})
    """, intermediates)
    target_nodes = {row[0] for row in cursor.fetchall()}
    conn.close()

    with open(json_path, 'r') as f:
        telemetry_data = json.load(f)

    return sum(item.get('value', 0) for item in telemetry_data
               if item.get('node_id') in target_nodes)


def run_submission(expected):
    if os.path.exists(RESULT_PATH):
        os.remove(RESULT_PATH)

    started = time.monotonic()
    try:
        proc = subprocess.run(
            [SCRIPT_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=2.0,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("fast_query.sh did not finish in less than 2 seconds.")
    elapsed = time.monotonic() - started

    assert proc.returncode == 0, (
        f"fast_query.sh exited with {proc.returncode}; stderr: {proc.stderr!r}"
    )
    assert elapsed < 2.0, f"fast_query.sh took {elapsed:.3f} seconds."
    assert proc.stdout == "", (
        "fast_query.sh must redirect its single integer result to result.txt "
        f"and not emit stdout; got {proc.stdout!r}."
    )
    assert os.path.isfile(RESULT_PATH), f"Output file {RESULT_PATH} is missing."

    with open(RESULT_PATH, 'r') as f:
        content = f.read().strip()

    assert content.isdigit(), (
        f"File {RESULT_PATH} must contain only an integer, got {content!r}."
    )
    assert int(content) == expected, (
        f"Expected sum {expected}, but got {content} in {RESULT_PATH}."
    )


def index_columns(conn, table):
    found = []
    for row in conn.execute(f"PRAGMA index_list('{table}')"):
        name = row[1]
        escaped = name.replace("'", "''")
        columns = [r[2].lower() for r in conn.execute(
            f"PRAGMA index_info('{escaped}')"
        )]
        found.append((name, columns))
    return found


def assert_appropriate_indexes(conn):
    edge_indexes = index_columns(conn, "edges")
    node_indexes = index_columns(conn, "nodes")

    assert any(cols[:2] == ["source", "target"] for _, cols in edge_indexes), (
        "An applied covering index on edges(source, target) is required for the "
        "two directed edge lookups."
    )
    assert any(cols and cols[0] == "status" for _, cols in node_indexes), (
        "An applied index beginning with nodes.status is required for status filtering."
    )


def write_fixture(nodes, edges, telemetry):
    for suffix in ("-wal", "-shm", "-journal"):
        try:
            os.remove(DB_PATH + suffix)
        except FileNotFoundError:
            pass
    try:
        os.remove(DB_PATH)
    except FileNotFoundError:
        pass

    conn = sqlite3.connect(DB_PATH)
    conn.execute("CREATE TABLE nodes (id INTEGER PRIMARY KEY, status TEXT)")
    conn.execute("CREATE TABLE edges (source INTEGER, target INTEGER)")
    conn.executemany("INSERT INTO nodes(id, status) VALUES (?, ?)", nodes)
    conn.executemany("INSERT INTO edges(source, target) VALUES (?, ?)", edges)
    with open(SQL_PATH, 'r') as f:
        conn.executescript(f.read())
    conn.commit()
    conn.close()

    with open(JSON_PATH, 'w') as f:
        json.dump(telemetry, f)


def test_result_txt_content():
    expected_sum = compute_expected_sum(DB_PATH, JSON_PATH)
    run_submission(expected_sum)


def test_optimize_sql_exists_and_valid():
    assert os.path.isfile(SQL_PATH), f"SQL file {SQL_PATH} is missing."

    with open(SQL_PATH, 'r') as f:
        content = f.read()

    assert "CREATE INDEX" in content.upper(), (
        f"File {SQL_PATH} does not seem to contain CREATE INDEX statements."
    )

    conn = sqlite3.connect(":memory:")
    conn.execute("CREATE TABLE nodes (id INTEGER PRIMARY KEY, status TEXT)")
    conn.execute("CREATE TABLE edges (source INTEGER, target INTEGER)")
    try:
        conn.executescript(content)
        assert_appropriate_indexes(conn)
    finally:
        conn.close()


def test_indexes_applied_to_db():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute(
        "SELECT name FROM sqlite_master "
        "WHERE type='index' AND name NOT LIKE 'sqlite_autoindex%';"
    )
    indexes = cursor.fetchall()
    assert len(indexes) > 0, (
        "No custom indexes were found in graph.db. Ensure optimize.sql was applied."
    )
    assert_appropriate_indexes(conn)
    conn.close()


def test_fast_query_sh_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Bash script {SCRIPT_PATH} is missing."
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."


def test_fast_query_on_varied_inputs():
    with tempfile.TemporaryDirectory() as backup:
        shutil.copy2(DB_PATH, os.path.join(backup, "graph.db"))
        shutil.copy2(JSON_PATH, os.path.join(backup, "telemetry.json"))
        had_result = os.path.isfile(RESULT_PATH)
        if had_result:
            shutil.copy2(RESULT_PATH, os.path.join(backup, "result.txt"))

        try:
            base = secrets.randbelow(50000) + 10000
            a, b, inactive = base, base + 1, base + 2
            x, y, z, invalid = base + 10, base + 11, base + 12, base + 13
            values = [secrets.randbelow(900) + 1 for _ in range(6)]

            nodes = [
                (1, "active"), (a, "active"), (b, "active"),
                (inactive, "inactive"), (x, "inactive"), (y, "active"),
                (z, "inactive"), (invalid, "active")
            ]
            edges = [
                (1, a), (1, b), (1, inactive),
                (a, x), (a, y), (b, x), (b, z),
                (inactive, invalid), (x, invalid), (invalid, 1)
            ]
            telemetry = [
                {"node_id": x, "event": "click", "value": values[0]},
                {"node_id": x, "event": "view", "value": values[1]},
                {"node_id": y, "event": "click", "value": values[2]},
                {"node_id": z, "event": "view", "value": values[3]},
                {"node_id": invalid, "event": "click", "value": values[4]},
                {"node_id": a, "event": "noise", "value": values[5]},
            ]
            write_fixture(nodes, edges, telemetry)
            expected = compute_expected_sum(DB_PATH, JSON_PATH)
            assert expected == sum(values[:4])
            run_submission(expected)

            base = secrets.randbelow(50000) + 70000
            inactive_mid, target = base, base + 1
            write_fixture(
                [(1, "active"), (inactive_mid, "inactive"), (target, "active")],
                [(1, inactive_mid), (inactive_mid, target)],
                [{"node_id": target, "event": "click", "value": values[0]}],
            )
            run_submission(0)
        finally:
            for suffix in ("-wal", "-shm", "-journal"):
                try:
                    os.remove(DB_PATH + suffix)
                except FileNotFoundError:
                    pass
            shutil.copy2(os.path.join(backup, "graph.db"), DB_PATH)
            shutil.copy2(os.path.join(backup, "telemetry.json"), JSON_PATH)
            if had_result:
                shutil.copy2(os.path.join(backup, "result.txt"), RESULT_PATH)
            else:
                try:
                    os.remove(RESULT_PATH)
                except FileNotFoundError:
                    pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

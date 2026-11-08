#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'RUNNER_EOF' > /tmp/instrument_graph_metrics.py
import re
import runpy
import sqlite3 as real_sqlite3
import sys
import types

_MISSING = object()
queries = []

class CursorProxy:
    def __init__(self, cursor):
        self._cursor = cursor

    def execute(self, sql, parameters=_MISSING):
        queries.append((str(sql), parameters))
        if parameters is _MISSING:
            self._cursor.execute(sql)
        else:
            self._cursor.execute(sql, parameters)
        return self

    def executemany(self, sql, parameters):
        queries.append((str(sql), parameters))
        self._cursor.executemany(sql, parameters)
        return self

    def __iter__(self):
        return iter(self._cursor)

    def __getattr__(self, name):
        return getattr(self._cursor, name)

class ConnectionProxy:
    def __init__(self, connection):
        self._connection = connection

    def cursor(self, *args, **kwargs):
        return CursorProxy(self._connection.cursor(*args, **kwargs))

    def execute(self, sql, parameters=_MISSING):
        cursor = self.cursor()
        return cursor.execute(sql, parameters)

    def executemany(self, sql, parameters):
        cursor = self.cursor()
        return cursor.executemany(sql, parameters)

    def __enter__(self):
        self._connection.__enter__()
        return self

    def __exit__(self, *args):
        return self._connection.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._connection, name)

def connect(*args, **kwargs):
    return ConnectionProxy(real_sqlite3.connect(*args, **kwargs))

fake_sqlite3 = types.ModuleType("sqlite3")
fake_sqlite3.__dict__.update(real_sqlite3.__dict__)
fake_sqlite3.connect = connect
sys.modules["sqlite3"] = fake_sqlite3

script = sys.argv[1]
sys.argv = [script] + sys.argv[2:]
exit_code = 0
try:
    runpy.run_path(script, run_name="__main__")
except SystemExit as exc:
    if exc.code is None:
        exit_code = 0
    elif isinstance(exc.code, int):
        exit_code = exc.code
    else:
        print(exc.code, file=sys.stderr)
        exit_code = 1

relevant = []
for sql, parameters in queries:
    lowered = sql.lower()
    if "hidden_rels" in lowered and re.search(r"\b(select|with)\b", lowered):
        marker = re.search(r"\?|[:@$][A-Za-z_]\w*", sql)
        parameterized = parameters is not _MISSING and marker is not None
        relevant.append(parameterized)

if exit_code == 0 and (not relevant or not all(relevant)):
    print("graph query was not executed using bound parameters", file=sys.stderr)
    exit_code = 97

raise SystemExit(exit_code)
RUNNER_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import sqlite3
import subprocess

DB_PATH = "/home/user/system_graph.db"
SCHEMA_PATH = "/home/user/schema.txt"
SCRIPT_PATH = "/home/user/graph_metrics.py"
METRICS_PATH = "/home/user/node_42_metrics.txt"
RUNNER_PATH = "/tmp/instrument_graph_metrics.py"


def expected_degree(node):
    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM hidden_rels WHERE u = ?", (node,))
        out_degree = cursor.fetchone()[0]
        cursor.execute("SELECT COUNT(*) FROM hidden_rels WHERE v = ?", (node,))
        in_degree = cursor.fetchone()[0]
        return out_degree + in_degree
    finally:
        conn.close()


def run_script(node):
    result = subprocess.run(
        ["python3", RUNNER_PATH, SCRIPT_PATH, str(node)],
        text=True,
        capture_output=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"graph_metrics.py failed for node {node}: {result.stderr}"
    )
    assert result.stderr == "", f"graph_metrics.py wrote to stderr: {result.stderr!r}"
    assert re.fullmatch(r"[0-9]+\n?", result.stdout), (
        f"graph_metrics.py must print only one integer, got {result.stdout!r}"
    )
    return int(result.stdout)


def test_schema_txt_exists_and_correct():
    assert os.path.isfile(SCHEMA_PATH), f"{SCHEMA_PATH} does not exist."
    with open(SCHEMA_PATH, "r") as f:
        raw = f.read()

    content = re.sub(r"\s+", " ", raw.strip().lower())
    assert "create table hidden_rels" in content
    assert "u integer" in content
    assert "v integer" in content

    expected = "CREATE TABLE hidden_rels (u INTEGER, v INTEGER)"
    assert raw.strip() == expected, (
        "schema.txt must contain the exact original CREATE TABLE statement"
    )


def test_indexes_created_and_target_correct_columns():
    assert os.path.isfile(DB_PATH), f"Database file not found at {DB_PATH}"
    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute(
            "SELECT name, tbl_name FROM sqlite_master "
            "WHERE type='index' AND name IN ('idx_source', 'idx_dest')"
        )
        index_dict = {name: table for name, table in cursor.fetchall()}

        assert "idx_source" in index_dict, "Index 'idx_source' was not created."
        assert index_dict["idx_source"] == "hidden_rels"
        assert "idx_dest" in index_dict, "Index 'idx_dest' was not created."
        assert index_dict["idx_dest"] == "hidden_rels"

        cursor.execute("PRAGMA index_info('idx_source')")
        source_columns = [row[2] for row in cursor.fetchall()]
        cursor.execute("PRAGMA index_info('idx_dest')")
        dest_columns = [row[2] for row in cursor.fetchall()]

        assert source_columns == ["u"], "idx_source must index source column u"
        assert dest_columns == ["v"], "idx_dest must index destination column v"
    finally:
        conn.close()


def test_graph_metrics_script_parameterized_and_general():
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} does not exist."
    with open(SCRIPT_PATH, "r") as f:
        content = f.read()

    # Preserve the original source-level assertion.
    assert "?" in content or re.search(r":\w+", content), (
        "graph_metrics.py does not appear to use parameterized queries"
    )

    conn = sqlite3.connect(DB_PATH)
    try:
        existing = [
            row[0] for row in conn.execute(
                "SELECT u FROM hidden_rels UNION SELECT v FROM hidden_rels "
                "ORDER BY RANDOM() LIMIT 5"
            )
        ]
    finally:
        conn.close()

    rng = secrets.SystemRandom()
    nodes = existing + [42] + [rng.randint(-1000000, 1000000) for _ in range(4)]
    for node in nodes:
        assert run_script(node) == expected_degree(node)


def test_script_requires_one_integer_argument():
    for args in ([], ["not-an-integer"], ["42", "43"]):
        result = subprocess.run(
            ["python3", RUNNER_PATH, SCRIPT_PATH] + args,
            text=True,
            capture_output=True,
            timeout=10,
        )
        assert result.returncode != 0, (
            f"graph_metrics.py should reject arguments {args!r}"
        )


def test_node_42_metrics_correct_and_matches_execution():
    assert os.path.isfile(METRICS_PATH), f"{METRICS_PATH} does not exist."

    # Preserve the original node-42 truth calculation.
    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT COUNT(*) FROM hidden_rels WHERE u = 42 OR v = 42;")
        expected = cursor.fetchone()[0]
    finally:
        conn.close()

    with open(METRICS_PATH, "r") as f:
        content = f.read().strip()

    assert content.isdigit(), f"{METRICS_PATH} should contain only an integer."
    actual = int(content)
    assert actual == expected, f"Expected degree {expected}, but found {actual}."
    assert actual == run_script(42), (
        "node_42_metrics.txt must contain graph_metrics.py's output for node 42"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

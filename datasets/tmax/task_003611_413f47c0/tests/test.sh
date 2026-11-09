#!/bin/bash
set -e
mkdir -p /logs/verifier

mkdir -p /tmp/analyze_instrument
cat <<'PY_EOF' > /tmp/analyze_instrument/sitecustomize.py
import json
import os
import sqlite3

_REAL_CONNECT = sqlite3.connect
_MISSING = object()
_LOG = os.environ.get("ANALYZE_SQL_LOG")

def _record(method, sql, parameterized):
    if not _LOG:
        return
    with open(_LOG, "a", encoding="utf-8") as f:
        f.write(json.dumps({
            "method": method,
            "sql": str(sql),
            "parameterized": bool(parameterized),
        }) + "\n")

class CursorProxy:
    def __init__(self, cursor):
        object.__setattr__(self, "_cursor", cursor)

    def execute(self, sql, parameters=_MISSING):
        _record("execute", sql, parameters is not _MISSING)
        if parameters is _MISSING:
            self._cursor.execute(sql)
        else:
            self._cursor.execute(sql, parameters)
        return self

    def executemany(self, sql, parameters):
        _record("executemany", sql, True)
        self._cursor.executemany(sql, parameters)
        return self

    def executescript(self, sql):
        _record("executescript", sql, False)
        self._cursor.executescript(sql)
        return self

    def __iter__(self):
        return iter(self._cursor)

    def __getattr__(self, name):
        return getattr(self._cursor, name)

    def __setattr__(self, name, value):
        setattr(self._cursor, name, value)

class ConnectionProxy:
    def __init__(self, connection):
        object.__setattr__(self, "_connection", connection)

    def cursor(self, *args, **kwargs):
        return CursorProxy(self._connection.cursor(*args, **kwargs))

    def execute(self, sql, parameters=_MISSING):
        _record("execute", sql, parameters is not _MISSING)
        if parameters is _MISSING:
            cursor = self._connection.execute(sql)
        else:
            cursor = self._connection.execute(sql, parameters)
        return CursorProxy(cursor)

    def executemany(self, sql, parameters):
        _record("executemany", sql, True)
        return CursorProxy(self._connection.executemany(sql, parameters))

    def executescript(self, sql):
        _record("executescript", sql, False)
        return CursorProxy(self._connection.executescript(sql))

    def __enter__(self):
        self._connection.__enter__()
        return self

    def __exit__(self, *args):
        return self._connection.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._connection, name)

    def __setattr__(self, name, value):
        setattr(self._connection, name, value)

def connect(*args, **kwargs):
    return ConnectionProxy(_REAL_CONNECT(*args, **kwargs))

sqlite3.connect = connect
PY_EOF

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import re
import sqlite3
import subprocess

SCRIPT = "/home/user/analyze.py"
NODES_CSV = "/home/user/nodes.csv"
EDGES_CSV = "/home/user/edges.csv"
DB = "/home/user/network.db"
REPORT = "/home/user/report.json"
TRACE = "/tmp/analyze_sql_trace.jsonl"

ORIGINAL_NODES = [
    (1, "Alice", "HR"),
    (2, "Bob", "HR"),
    (3, "Charlie", "IT"),
    (4, "Dave", "IT"),
    (5, "Eve", "IT"),
    (6, "Frank", "Sales"),
    (7, "Grace", "Sales"),
    (8, "Heidi", "Sales"),
]
ORIGINAL_EDGES = [
    (1, 2, 10), (1, 3, 50), (2, 1, 5), (3, 4, 20), (4, 5, 15),
    (5, 3, 10), (6, 7, 30), (7, 8, 30), (8, 6, 30), (1, 6, 5),
]


def write_fixture(nodes, edges):
    with open(NODES_CSV, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["id", "name", "dept"])
        w.writerows(nodes)
    with open(EDGES_CSV, "w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["source", "target", "weight"])
        w.writerows(edges)


def expected_result(nodes, edges):
    totals = {node_id: 0 for node_id, _, _ in nodes}
    departments = {}
    for node_id, _, dept in nodes:
        departments.setdefault(dept, []).append(node_id)
    for source, _, weight in edges:
        totals[source] += weight
    top = {
        dept: min(ids, key=lambda node_id: (-totals[node_id], node_id))
        for dept, ids in departments.items()
    }

    directed = {(source, target) for source, target, _ in edges}
    ids = [node_id for node_id, _, _ in nodes]
    triangles = set()
    for a in ids:
        for b in ids:
            for c in ids:
                if len({a, b, c}) == 3 and (a, b) in directed and (b, c) in directed and (c, a) in directed:
                    triangles.add(tuple(sorted((a, b, c))))
    return {"top_per_dept": top, "triangles": [list(t) for t in sorted(triangles)]}


def read_trace():
    assert os.path.isfile(TRACE), "No SQLite activity was recorded while analyze.py ran."
    records = []
    with open(TRACE, encoding="utf-8") as f:
        for line in f:
            if line.strip():
                records.append(json.loads(line))
    return records


def check_required_sql(records):
    def normalized(record):
        return " ".join(record["sql"].lower().split())

    insert_records = [r for r in records if re.search(r"\binsert\b", normalized(r))]
    assert insert_records, "analyze.py did not execute SQL INSERT statements."
    for record in insert_records:
        sql = normalized(record)
        assert record["parameterized"], f"An INSERT was executed without parameters: {record['sql']}"
        assert re.search(r"\?|[:@$][a-z_][a-z0-9_]*", sql), f"An INSERT has no SQL parameter placeholders: {record['sql']}"

    for table in ("nodes", "edges"):
        matching = [
            r for r in insert_records
            if re.search(r"\binto\s+(?:main\.)?[\"`\[]?" + table + r"\b", normalized(r))
        ]
        assert matching, f"No parameterized INSERT into {table} was executed."

    window_queries = []
    for record in records:
        sql = normalized(record)
        if (re.search(r"\b(row_number|rank|dense_rank)\s*\(\s*\)\s*over\s*\(", sql)
                and re.search(r"\bpartition\s+by\b", sql)
                and "dept" in sql):
            window_queries.append(record)
    assert window_queries, "No department-ranking SQL Window Function was executed."

    triangle_queries = []
    for record in records:
        sql = normalized(record)
        edge_refs = len(re.findall(r"\bedges\b", sql))
        if (re.search(r"\bselect\b", sql) and edge_refs >= 3
                and len(re.findall(r"\bjoin\b", sql)) >= 2
                and "source" in sql and "target" in sql):
            triangle_queries.append(record)
    assert triangle_queries, "No SQL query using self-joins of three edges instances was executed."


def run_and_check(nodes, edges, expected, original=False):
    write_fixture(nodes, edges)
    for path in (DB, REPORT, TRACE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env["PYTHONPATH"] = "/tmp/analyze_instrument" + (":" + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    env["ANALYZE_SQL_LOG"] = TRACE
    completed = subprocess.run(
        ["python3", SCRIPT], cwd="/home/user", env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert completed.returncode == 0, f"analyze.py failed:\n{completed.stdout}\n{completed.stderr}"

    # Preserve the original verifier's existence, schema, and count assertions.
    assert os.path.isfile(DB), "network.db database is missing."
    conn = sqlite3.connect(DB)
    try:
        tables = {row[0] for row in conn.execute("SELECT name FROM sqlite_master WHERE type='table'")}
        assert "nodes" in tables, "Table 'nodes' is missing in network.db."
        assert "edges" in tables, "Table 'edges' is missing in network.db."
        node_count = conn.execute("SELECT count(*) FROM nodes").fetchone()[0]
        edge_count = conn.execute("SELECT count(*) FROM edges").fetchone()[0]
        if original:
            assert node_count == 8, f"Expected 8 rows in nodes table, got {node_count}."
            assert edge_count == 10, f"Expected 10 rows in edges table, got {edge_count}."
        assert node_count == len(nodes), f"Expected {len(nodes)} node rows, got {node_count}."
        assert edge_count == len(edges), f"Expected {len(edges)} edge rows, got {edge_count}."
        actual_nodes = conn.execute("SELECT id, name, dept FROM nodes").fetchall()
        actual_edges = conn.execute("SELECT source, target, weight FROM edges").fetchall()
        assert sorted(actual_nodes) == sorted(nodes), "nodes table does not contain the CSV data exactly."
        assert sorted(actual_edges) == sorted(edges), "edges table does not contain the CSV data exactly."
    finally:
        conn.close()

    assert os.path.isfile(REPORT), "report.json is missing."
    try:
        with open(REPORT, encoding="utf-8") as f:
            report = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError("report.json is not valid JSON.") from exc

    assert "top_per_dept" in report, "Key 'top_per_dept' missing in report.json."
    assert "triangles" in report, "Key 'triangles' missing in report.json."
    if original:
        top = report["top_per_dept"]
        assert top.get("HR") == 1, f"Expected HR top employee to be 1, got {top.get('HR')}"
        assert top.get("IT") == 3, f"Expected IT top employee to be 3, got {top.get('IT')}"
        assert top.get("Sales") == 6, f"Expected Sales top employee to be 6, got {top.get('Sales')}"
        actual_triangles = [sorted(t) for t in report["triangles"]]
        assert len(actual_triangles) == 2, f"Expected 2 triangles, got {len(actual_triangles)}."
        for triangle in ([3, 4, 5], [6, 7, 8]):
            assert triangle in actual_triangles, f"Missing expected triangle {triangle} in report.json."

    assert set(report.keys()) == {"top_per_dept", "triangles"}, "report.json has an incorrect top-level structure."
    assert report["top_per_dept"] == expected["top_per_dept"], "Department rankings are incorrect."
    assert isinstance(report["triangles"], list), "triangles must be a list."
    actual_canonical = []
    for triangle in report["triangles"]:
        assert isinstance(triangle, list) and len(triangle) == 3, "Each triangle must be a three-item list."
        assert triangle == sorted(triangle), f"Triangle {triangle} is not sorted."
        actual_canonical.append(triangle)
    assert len(actual_canonical) == len({tuple(t) for t in actual_canonical}), "Duplicate triangles were reported."
    assert sorted(actual_canonical) == expected["triangles"], "Directed triangle results are incorrect."

    check_required_sql(read_trace())


def test_complete_analysis():
    assert os.path.isfile(SCRIPT), "analyze.py script is missing."
    with open(SCRIPT, "rb") as f:
        original_script = f.read()
    assert original_script.strip(), "analyze.py is empty."

    old_nodes = open(NODES_CSV, "rb").read() if os.path.exists(NODES_CSV) else None
    old_edges = open(EDGES_CSV, "rb").read() if os.path.exists(EDGES_CSV) else None
    try:
        run_and_check(ORIGINAL_NODES, ORIGINAL_EDGES, expected_result(ORIGINAL_NODES, ORIGINAL_EDGES), original=True)

        rng = random.SystemRandom()
        ids = rng.sample(range(101, 1000), 7)
        a, b, c, d, e, f, g = ids
        nodes = [
            (a, "Nora", "Alpha"), (b, "Omar", "Alpha"), (c, "Pia", "Alpha"),
            (d, "Quinn", "Beta"), (e, "Ravi", "Beta"),
            (f, "Sara", "Gamma"), (g, "Tomas", "Gamma"),
        ]
        tie_total = rng.randint(50, 100)
        first_part = rng.randint(10, tie_total - 10)
        edges = [
            (a, b, first_part), (a, d, tie_total - first_part),
            (b, c, tie_total), (c, a, rng.randint(1, 9)),
            (d, e, rng.randint(50, 80)), (e, f, rng.randint(10, 20)),
            (f, d, rng.randint(20, 30)), (g, a, rng.randint(60, 90)),
        ]
        run_and_check(nodes, edges, expected_result(nodes, edges))
    finally:
        if old_nodes is not None:
            with open(NODES_CSV, "wb") as f:
                f.write(old_nodes)
        if old_edges is not None:
            with open(EDGES_CSV, "wb") as f:
                f.write(old_edges)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

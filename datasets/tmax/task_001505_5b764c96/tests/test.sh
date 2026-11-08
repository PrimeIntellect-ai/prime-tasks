#!/bin/bash
set -e
mkdir -p /logs/verifier

INSTRUMENT_DIR="$(mktemp -d)"
cat << 'PY_EOF' > "$INSTRUMENT_DIR/sitecustomize.py"
import os
import sqlite3

_real_connect = sqlite3.connect
_log_path = os.environ.get("SQL_TRACE_LOG")

def _log(kind, value):
    if _log_path:
        with open(_log_path, "a", encoding="utf-8") as f:
            f.write(kind + "\t" + str(value).replace("\n", " ") + "\n")

class CursorProxy:
    def __init__(self, cursor):
        self._cursor = cursor

    def execute(self, sql, *args, **kwargs):
        _log("SQL", sql)
        self._cursor.execute(sql, *args, **kwargs)
        return self

    def executemany(self, sql, *args, **kwargs):
        _log("SQL", sql)
        self._cursor.executemany(sql, *args, **kwargs)
        return self

    def executescript(self, sql, *args, **kwargs):
        _log("SQL", sql)
        self._cursor.executescript(sql, *args, **kwargs)
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

    def execute(self, sql, *args, **kwargs):
        _log("SQL", sql)
        return self._connection.execute(sql, *args, **kwargs)

    def executemany(self, sql, *args, **kwargs):
        _log("SQL", sql)
        return self._connection.executemany(sql, *args, **kwargs)

    def executescript(self, sql, *args, **kwargs):
        _log("SQL", sql)
        return self._connection.executescript(sql, *args, **kwargs)

    def __enter__(self):
        self._connection.__enter__()
        return self

    def __exit__(self, *args):
        return self._connection.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._connection, name)

def connect(*args, **kwargs):
    database = args[0] if args else kwargs.get("database")
    _log("CONNECT", database)
    return ConnectionProxy(_real_connect(*args, **kwargs))

sqlite3.connect = connect
PY_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import json
import os
import random
import re
import sqlite3
import subprocess
import sys

import pytest

REPORT_PATH = "/home/user/report.json"
SCRIPT_PATH = "/home/user/analyze_backups.py"
DB_PATH = "/home/user/backups.db"
TRACE_PATH = "/tmp/analyze_backups_sql.log"
INSTRUMENT_DIR = os.environ["INSTRUMENT_DIR"]


def run_submission():
    if os.path.exists(TRACE_PATH):
        os.unlink(TRACE_PATH)

    env = os.environ.copy()
    env["SQL_TRACE_LOG"] = TRACE_PATH
    old_pythonpath = env.get("PYTHONPATH")
    env["PYTHONPATH"] = INSTRUMENT_DIR + (os.pathsep + old_pythonpath if old_pythonpath else "")

    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd="/home/user",
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Script exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(TRACE_PATH), "The script did not connect through the standard sqlite3 library."

    connects = []
    statements = []
    with open(TRACE_PATH, encoding="utf-8") as f:
        for line in f:
            kind, _, value = line.rstrip("\n").partition("\t")
            if kind == "CONNECT":
                connects.append(value)
            elif kind == "SQL":
                statements.append(value)

    assert DB_PATH in connects, f"The script did not connect to {DB_PATH}."

    edge_selects = []
    for statement in statements:
        normalized = " ".join(statement.split())
        if re.search(r'\bSELECT\b', normalized, re.I) and re.search(
            r'\bFROM\s+(?:[\"`\[]?edges[\"`\]]?)\b', normalized, re.I
        ):
            edge_selects.append(normalized)

    assert edge_selects, "The script did not execute a SELECT against the edges table."
    full_extractions = []
    for statement in edge_selects:
        select_part = re.split(r'\bFROM\b', statement, maxsplit=1, flags=re.I)[0]
        has_fields = "*" in select_part or all(
            re.search(rf'\b{name}\b', select_part, re.I)
            for name in ("source", "target", "cost")
        )
        if has_fields and not re.search(r'\bWHERE\b|\bLIMIT\b', statement, re.I):
            full_extractions.append(statement)

    assert full_extractions, (
        "The script must extract source, target, and cost for the entire edges table "
        "without filtering it with WHERE or LIMIT."
    )
    for statement in edge_selects:
        assert not re.search(
            r'\bWHERE\b[^;]*\bsource\b\s*(?:=|==|IS)\s*', statement, re.I
        ), "The script used a WHERE predicate on source instead of bypassing the index."


@pytest.fixture(scope="module", autouse=True)
def execute_on_original_database():
    assert os.path.exists(SCRIPT_PATH), f"Script file {SCRIPT_PATH} is missing."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    run_submission()


def test_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"Script file {SCRIPT_PATH} is missing."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."


def test_report_exists():
    assert os.path.exists(REPORT_PATH), f"Report file {REPORT_PATH} is missing."
    assert os.path.isfile(REPORT_PATH), f"{REPORT_PATH} is not a file."


def test_report_contents():
    with open(REPORT_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{REPORT_PATH} does not contain valid JSON.")

    required_keys = {"shortest_path", "total_cost", "most_critical_node"}
    missing_keys = required_keys - set(data.keys())
    assert not missing_keys, f"Report JSON is missing required keys: {missing_keys}"

    assert isinstance(data["shortest_path"], list), "'shortest_path' must be a list."
    assert all(isinstance(x, str) for x in data["shortest_path"]), "All items in 'shortest_path' must be strings."
    assert isinstance(data["total_cost"], int), "'total_cost' must be an integer."
    assert isinstance(data["most_critical_node"], str), "'most_critical_node' must be a string."

    assert data["shortest_path"] == ["ROOT", "C", "TARGET"], "Incorrect shortest path."
    assert data["total_cost"] == 25, "Incorrect total cost."
    assert data["most_critical_node"] == "CRITICAL", "Incorrect most critical node."


def derive_expected(nodes, edges):
    adjacency = {node: [] for node in nodes}
    indegree = {node: 0 for node in nodes}
    for source, target, cost in edges:
        adjacency.setdefault(source, []).append((target, cost))
        adjacency.setdefault(target, [])
        indegree.setdefault(source, 0)
        indegree[target] = indegree.get(target, 0) + 1

    distances = {"ROOT": 0}
    paths = {"ROOT": ["ROOT"]}
    queue = [(0, ["ROOT"], "ROOT")]
    while queue:
        distance, path, node = heapq.heappop(queue)
        if distance != distances.get(node) or path != paths.get(node):
            continue
        for target, cost in adjacency[node]:
            candidate_distance = distance + cost
            candidate_path = path + [target]
            if (candidate_distance, candidate_path) < (
                distances.get(target, float("inf")), paths.get(target, ["~"])
            ):
                distances[target] = candidate_distance
                paths[target] = candidate_path
                heapq.heappush(queue, (candidate_distance, candidate_path, target))

    highest = max(indegree.values())
    critical = min(node for node, degree in indegree.items() if degree == highest)
    return {
        "shortest_path": paths["TARGET"],
        "total_cost": distances["TARGET"],
        "most_critical_node": critical,
    }


def test_script_recomputes_from_database_and_handles_tie_breaking():
    rng = random.SystemRandom()
    first = rng.randint(2, 40)
    second = rng.randint(2, 40)
    alternate_total = first + second + rng.randint(5, 30)
    alternate_first = rng.randint(1, alternate_total - 1)

    nodes = ["ROOT", "TARGET", "P", "Q", "ALPHA", "BETA", "X1", "X2", "X3"]
    edges = [
        ("ROOT", "P", first),
        ("P", "TARGET", second),
        ("ROOT", "Q", alternate_first),
        ("Q", "TARGET", alternate_total - alternate_first),
        ("ROOT", "TARGET", alternate_total + rng.randint(3, 20)),
        ("X1", "ALPHA", rng.randint(1, 20)),
        ("X2", "ALPHA", rng.randint(1, 20)),
        ("X3", "ALPHA", rng.randint(1, 20)),
        ("X1", "BETA", rng.randint(1, 20)),
        ("X2", "BETA", rng.randint(1, 20)),
        ("X3", "BETA", rng.randint(1, 20)),
    ]
    expected = derive_expected(nodes, edges)

    replacement = DB_PATH + ".verifier-new"
    if os.path.exists(replacement):
        os.unlink(replacement)
    conn = sqlite3.connect(replacement)
    try:
        conn.execute("CREATE TABLE nodes (id INTEGER PRIMARY KEY, name TEXT)")
        conn.execute("CREATE TABLE edges (source TEXT, target TEXT, cost INTEGER)")
        conn.executemany("INSERT INTO nodes(id, name) VALUES (?, ?)", enumerate(nodes, 1))
        conn.executemany("INSERT INTO edges(source, target, cost) VALUES (?, ?, ?)", edges)
        conn.execute("CREATE INDEX idx_edges_source ON edges(source)")
        conn.commit()
    finally:
        conn.close()
    os.replace(replacement, DB_PATH)

    if os.path.exists(REPORT_PATH):
        os.unlink(REPORT_PATH)
    run_submission()
    assert os.path.isfile(REPORT_PATH), "The executed script did not generate report.json."
    with open(REPORT_PATH, encoding="utf-8") as f:
        data = json.load(f)

    required_keys = {"shortest_path", "total_cost", "most_critical_node"}
    assert required_keys <= set(data), "Dynamic report is missing required keys."
    assert isinstance(data["shortest_path"], list)
    assert all(isinstance(item, str) for item in data["shortest_path"])
    assert isinstance(data["total_cost"], int) and not isinstance(data["total_cost"], bool)
    assert isinstance(data["most_critical_node"], str)
    assert {key: data[key] for key in required_keys} == expected
TEST_EOF

if INSTRUMENT_DIR="$INSTRUMENT_DIR" python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

rm -rf "$INSTRUMENT_DIR"

#!/bin/bash
mkdir -p /logs/verifier

if python3 - <<'PY'
import ast
import json
import math
import os
import re
import secrets
import sqlite3
import subprocess
import sys
import tempfile

HOME = "/home/user"
DB_PATH = os.path.join(HOME, "backups.db")
OUTPUT_PATH = os.path.join(HOME, "restore_priority.json")


def find_candidate_scripts():
    candidates = []
    for root, dirs, files in os.walk(HOME):
        dirs[:] = [d for d in dirs if not d.startswith(".")]
        for filename in files:
            path = os.path.join(root, filename)
            if path in (DB_PATH, OUTPUT_PATH) or not os.path.isfile(path):
                continue
            try:
                if os.path.getsize(path) > 1024 * 1024:
                    continue
                with open(path, "r", encoding="utf-8") as f:
                    source = f.read()
                tree = ast.parse(source, filename=path)
            except (OSError, UnicodeError, SyntaxError):
                continue

            imports_networkx = any(
                (isinstance(node, ast.Import) and any(alias.name == "networkx" or alias.name.startswith("networkx.") for alias in node.names))
                or (isinstance(node, ast.ImportFrom) and node.module and (node.module == "networkx" or node.module.startswith("networkx.")))
                for node in ast.walk(tree)
            )
            if imports_networkx:
                candidates.append(path)
    return sorted(candidates)


def install_instrumentation(directory):
    sitecustomize = r'''
import os

_NX_MARKER = os.environ.get("VERIFY_NX_MARKER")
_SQL_MARKER = os.environ.get("VERIFY_SQL_MARKER")

try:
    import networkx as _nx
    _original_centrality = _nx.in_degree_centrality

    def _checked_centrality(*args, **kwargs):
        if _NX_MARKER:
            with open(_NX_MARKER, "a", encoding="utf-8") as _f:
                _f.write("called\n")
        return _original_centrality(*args, **kwargs)

    _nx.in_degree_centrality = _checked_centrality
    try:
        _nx.algorithms.centrality.in_degree_centrality = _checked_centrality
    except Exception:
        pass
    try:
        import networkx.algorithms.centrality.degree_alg as _degree_alg
        _degree_alg.in_degree_centrality = _checked_centrality
    except Exception:
        pass
except Exception:
    pass

try:
    import sqlite3 as _sqlite3
    _original_connect = _sqlite3.connect

    def _log_sql(sql):
        if _SQL_MARKER:
            with open(_SQL_MARKER, "a", encoding="utf-8") as _f:
                _f.write(str(sql).replace("\n", " ") + "\n")

    class _CursorProxy:
        def __init__(self, cursor):
            self._cursor = cursor
        def execute(self, sql, *args, **kwargs):
            _log_sql(sql)
            self._cursor.execute(sql, *args, **kwargs)
            return self
        def executemany(self, sql, *args, **kwargs):
            _log_sql(sql)
            self._cursor.executemany(sql, *args, **kwargs)
            return self
        def executescript(self, sql, *args, **kwargs):
            _log_sql(sql)
            self._cursor.executescript(sql, *args, **kwargs)
            return self
        def __iter__(self):
            return self
        def __next__(self):
            return next(self._cursor)
        def __getattr__(self, name):
            return getattr(self._cursor, name)

    class _ConnectionProxy:
        def __init__(self, connection):
            self._connection = connection
        def cursor(self, *args, **kwargs):
            return _CursorProxy(self._connection.cursor(*args, **kwargs))
        def execute(self, sql, *args, **kwargs):
            _log_sql(sql)
            return _CursorProxy(self._connection.execute(sql, *args, **kwargs))
        def executemany(self, sql, *args, **kwargs):
            _log_sql(sql)
            return _CursorProxy(self._connection.executemany(sql, *args, **kwargs))
        def executescript(self, sql, *args, **kwargs):
            _log_sql(sql)
            return _CursorProxy(self._connection.executescript(sql, *args, **kwargs))
        def __enter__(self):
            self._connection.__enter__()
            return self
        def __exit__(self, *args):
            return self._connection.__exit__(*args)
        def __getattr__(self, name):
            return getattr(self._connection, name)

    def _checked_connect(*args, **kwargs):
        return _ConnectionProxy(_original_connect(*args, **kwargs))

    _sqlite3.connect = _checked_connect
except Exception:
    pass
'''
    with open(os.path.join(directory, "sitecustomize.py"), "w", encoding="utf-8") as f:
        f.write(sitecustomize)


def create_database(servers, active_edges, inactive_edges):
    for suffix in ("", "-wal", "-shm"):
        try:
            os.remove(DB_PATH + suffix)
        except FileNotFoundError:
            pass

    connection = sqlite3.connect(DB_PATH)
    try:
        connection.executescript("""
            CREATE TABLE servers (id INTEGER PRIMARY KEY, name TEXT, size_gb INTEGER);
            CREATE TABLE dependencies (src INTEGER, dst INTEGER, is_active INTEGER);
            CREATE INDEX idx_active ON dependencies(is_active);
        """)
        connection.executemany("INSERT INTO servers VALUES (?, ?, ?)", servers)
        connection.executemany(
            "INSERT INTO dependencies VALUES (?, ?, 1)", active_edges
        )
        connection.executemany(
            "INSERT INTO dependencies VALUES (?, ?, 0)", inactive_edges
        )
        connection.commit()
    finally:
        connection.close()
    os.chmod(DB_PATH, 0o666)


def expected_results(servers, active_edges):
    names = {server_id: name for server_id, name, _ in servers}
    sizes = {server_id: size for server_id, _, size in servers}
    indegrees = {server_id: 0 for server_id in names}
    targets = {server_id: set() for server_id in names}

    # A DiGraph collapses duplicate edges, so derive expectations the same way.
    for src, dst in set(active_edges):
        indegrees[dst] += 1
        targets[src].add(dst)

    denominator = len(servers) - 1
    expected = {}
    for server_id in names:
        expected[names[server_id]] = {
            "server_name": names[server_id],
            "in_degree_centrality": indegrees[server_id] / denominator if denominator else 1.0,
            "total_backup_size": sizes[server_id] + sum(sizes[target] for target in targets[server_id]),
        }
    return expected


def validate_output(expected):
    assert os.path.exists(OUTPUT_PATH), f"Output file {OUTPUT_PATH} is missing."
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} should be a regular file."

    with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
        data = json.load(f)

    assert isinstance(data, list), f"Expected the JSON output to be a list, got {type(data).__name__}."
    assert len(data) == len(expected), f"Expected {len(expected)} items, found {len(data)}."

    expected_keys = {"server_name", "in_degree_centrality", "total_backup_size"}
    seen = set()
    ranking = []
    for i, actual in enumerate(data):
        assert isinstance(actual, dict), f"Item at index {i} is not a dictionary."
        assert set(actual.keys()) == expected_keys, f"Item at index {i} has incorrect keys."
        name = actual["server_name"]
        assert name in expected, f"Unexpected server_name {name!r} at index {i}."
        assert name not in seen, f"Duplicate server_name {name!r}."
        seen.add(name)

        wanted = expected[name]
        assert isinstance(actual["in_degree_centrality"], (int, float)) and not isinstance(actual["in_degree_centrality"], bool)
        assert math.isclose(actual["in_degree_centrality"], wanted["in_degree_centrality"], rel_tol=1e-9, abs_tol=0.001), f"Incorrect centrality for {name}."
        assert actual["total_backup_size"] == wanted["total_backup_size"], f"Incorrect total_backup_size for {name}."
        ranking.append((wanted["in_degree_centrality"], wanted["total_backup_size"]))

    assert seen == set(expected)
    for previous, current in zip(ranking, ranking[1:]):
        assert previous >= current, "Results are not sorted by centrality descending and backup size descending."


def run_fixture(script, servers, active_edges, inactive_edges, instrumentation_dir):
    create_database(servers, active_edges, inactive_edges)
    try:
        os.remove(OUTPUT_PATH)
    except FileNotFoundError:
        pass

    nx_marker = os.path.join(instrumentation_dir, "networkx.marker")
    sql_marker = os.path.join(instrumentation_dir, "sql.marker")
    for marker in (nx_marker, sql_marker):
        try:
            os.remove(marker)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env["VERIFY_NX_MARKER"] = nx_marker
    env["VERIFY_SQL_MARKER"] = sql_marker
    env["PYTHONPATH"] = instrumentation_dir + (os.pathsep + env["PYTHONPATH"] if env.get("PYTHONPATH") else "")
    result = subprocess.run(
        [sys.executable, script],
        cwd=os.path.dirname(script) or HOME,
        env=env,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Script failed:\n{result.stdout}\n{result.stderr}"
    assert os.path.isfile(nx_marker), "The script did not call networkx.in_degree_centrality."
    assert os.path.isfile(sql_marker), "The script did not query SQLite through sqlite3."

    with open(sql_marker, "r", encoding="utf-8") as f:
        statements = f.read().lower().splitlines()
    assert any(
        "dependencies" in statement
        and "is_active" in statement
        and re.search(r"\bnot\s+indexed\b", statement)
        for statement in statements
    ), "The active-dependency query was not executed with NOT INDEXED."

    validate_output(expected_results(servers, active_edges))


scripts = find_candidate_scripts()
assert scripts, "No Python script using NetworkX was found under /home/user."

original_servers = [
    (1, "DB-01", 500),
    (2, "APP-01", 50),
    (3, "APP-02", 50),
    (4, "CACHE-01", 20),
    (5, "WEB-01", 10),
]
original_active = [(2, 1), (3, 1), (5, 2), (5, 3), (2, 4), (3, 4)]
original_inactive = [(4, 1), (5, 1)]

# Generate an unpredictable second database so a fixed JSON file cannot pass.
token = secrets.token_hex(4)
random_servers = [
    (i, f"SRV-{token}-{i}", 10 + secrets.randbelow(490)) for i in range(1, 8)
]
all_edges = [(src, dst) for src in range(1, 8) for dst in range(1, 8) if src != dst]
active_indices = set()
while len(active_indices) < 11:
    active_indices.add(secrets.randbelow(len(all_edges)))
random_active = [all_edges[i] for i in active_indices]
remaining = [edge for i, edge in enumerate(all_edges) if i not in active_indices]
inactive_indices = set()
while len(inactive_indices) < 5:
    inactive_indices.add(secrets.randbelow(len(remaining)))
random_inactive = [remaining[i] for i in inactive_indices]

errors = []
with tempfile.TemporaryDirectory(prefix="restore_verify_") as instrumentation_dir:
    install_instrumentation(instrumentation_dir)
    passed_script = None
    for script in scripts:
        try:
            run_fixture(script, random_servers, random_active, random_inactive, instrumentation_dir)
            # Run the original fixture last, retaining all original content checks.
            # APP-01 and APP-02 may appear in either order because both sort keys tie.
            run_fixture(script, original_servers, original_active, original_inactive, instrumentation_dir)
            passed_script = script
            break
        except Exception as exc:
            errors.append(f"{script}: {exc}")

    assert passed_script is not None, "No candidate script passed:\n" + "\n".join(errors)
PY
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import shutil
import sqlite3
import subprocess
from collections import deque

SOURCE = "/home/user/planner.c"
BINARY = "/home/user/planner"
DATABASE = "/home/user/metadata.db"
CSV_PATH = "/home/user/backup_plan.csv"
TRACE = "/tmp/planner_sqlite_trace.log"
SHIM_SOURCE = "/tmp/sqlite_audit.c"
SHIM = "/tmp/sqlite_audit.so"
DB_BACKUP = "/tmp/metadata.db.verifier-backup"


def require_artifacts():
    assert os.path.isfile(SOURCE), f"C source missing at {SOURCE}"
    assert os.path.isfile(BINARY), f"Compiled planner missing at {BINARY}"
    assert os.access(BINARY, os.X_OK), f"Planner is not executable: {BINARY}"

    source = open(SOURCE, encoding="utf-8").read()
    assert re.search(r"#\s*include\s*[<\"]sqlite3\.h[>\"]", source), "planner.c must include sqlite3.h"
    assert re.search(r"\bsqlite3_(?:open|open_v2)\s*\(", source), "planner.c must open SQLite through the C API"
    assert re.search(r"\bsqlite3_(?:prepare_v2|prepare_v3|exec)\s*\(", source), "planner.c must execute SQL through the SQLite C API"
    assert re.search(r"\bWITH\b[\s\S]{0,4000}\bRECURSIVE\b", source, re.IGNORECASE), "planner.c must contain a recursive CTE"


def build_submission_and_audit_shim():
    compiled = BINARY + ".verified"
    subprocess.run(["gcc", "-o", compiled, SOURCE, "-lsqlite3"], check=True, capture_output=True, text=True)
    os.replace(compiled, BINARY)
    os.chmod(BINARY, 0o755)

    shim_code = r'''
#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void event(const char *s) {
    const char *p = getenv("SQLITE_TRACE_LOG");
    if (!p) return;
    FILE *f = fopen(p, "a");
    if (f) { fprintf(f, "%s\n", s); fclose(f); }
}

static int contains_ci(const char *s, int n, const char *needle) {
    int m = (int)strlen(needle);
    if (!s) return 0;
    if (n < 0) n = (int)strlen(s);
    for (int i = 0; i + m <= n; i++) {
        int ok = 1;
        for (int j = 0; j < m; j++)
            if (tolower((unsigned char)s[i+j]) != tolower((unsigned char)needle[j])) { ok = 0; break; }
        if (ok) return 1;
    }
    return 0;
}

static void inspect_sql(const char *sql, int n) {
    if (contains_ci(sql, n, "with") && contains_ci(sql, n, "recursive")) event("RECURSIVE_SQL");
}

int sqlite3_open(const char *name, sqlite3 **db) {
    static int (*real_fn)(const char *, sqlite3 **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_open");
    event("OPEN");
    return real_fn(name, db);
}

int sqlite3_open_v2(const char *name, sqlite3 **db, int flags, const char *vfs) {
    static int (*real_fn)(const char *, sqlite3 **, int, const char *) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_open_v2");
    event("OPEN");
    return real_fn(name, db, flags, vfs);
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    inspect_sql(sql, n);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v3(sqlite3 *db, const char *sql, int n, unsigned int flags, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, unsigned int, sqlite3_stmt **, const char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v3");
    inspect_sql(sql, n);
    return real_fn(db, sql, n, flags, stmt, tail);
}

int sqlite3_exec(sqlite3 *db, const char *sql, int (*cb)(void *, int, char **, char **), void *arg, char **err) {
    static int (*real_fn)(sqlite3 *, const char *, int (*)(void *, int, char **, char **), void *, char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_exec");
    inspect_sql(sql, -1);
    return real_fn(db, sql, cb, arg, err);
}
'''
    with open(SHIM_SOURCE, "w", encoding="utf-8") as f:
        f.write(shim_code)
    subprocess.run(["gcc", "-shared", "-fPIC", "-o", SHIM, SHIM_SOURCE, "-ldl"], check=True, capture_output=True, text=True)


def read_graph():
    con = sqlite3.connect(DATABASE)
    try:
        tables = con.execute("SELECT id, name FROM tables").fetchall()
        deps = con.execute("SELECT table_id, depends_on_id FROM deps").fetchall()
    finally:
        con.close()

    names = {row[0]: row[1] for row in tables}
    assert len(names) == len(tables)
    assert len(set(names.values())) == len(names), "Table names must be unique"
    graph = {name: [] for name in names.values()}
    for table_id, dependency_id in deps:
        assert table_id in names and dependency_id in names
        graph[names[table_id]].append(names[dependency_id])
    return graph


def expected_levels(graph):
    memo = {}
    visiting = set()

    def level(node):
        if node in memo:
            return memo[node]
        assert node not in visiting, "Test graph unexpectedly contains a cycle"
        visiting.add(node)
        memo[node] = 0 if not graph[node] else max(level(dep) for dep in graph[node]) + 1
        visiting.remove(node)
        return memo[node]

    for node in graph:
        level(node)
    return memo


def shortest_distance(graph, start):
    queue = deque([(start, 0)])
    seen = {start}
    while queue:
        node, distance = queue.popleft()
        if not graph[node]:
            return distance
        for dep in graph[node]:
            if dep not in seen:
                seen.add(dep)
                queue.append((dep, distance + 1))
    raise AssertionError(f"No level-0 table is reachable from {start}")


def validate_csv():
    assert os.path.isfile(CSV_PATH), f"CSV file missing at {CSV_PATH}"
    raw = open(CSV_PATH, "rb").read()
    text = raw.decode("utf-8")
    physical_lines = text.splitlines()
    assert physical_lines, "CSV is empty"
    assert physical_lines[0] == "table_name,backup_level,path", "CSV header is not exact"
    assert all(line and line == line.rstrip(" \t") for line in physical_lines), "CSV contains blank lines or trailing spaces"

    with open(CSV_PATH, newline="", encoding="utf-8") as f:
        rows = list(csv.reader(f, strict=True))
    assert rows and rows[0] == ["table_name", "backup_level", "path"]
    assert all(len(row) == 3 for row in rows), "Every CSV row must have exactly three fields"

    graph = read_graph()
    levels = expected_levels(graph)
    data = rows[1:]
    assert len(data) == len(graph), "CSV must contain exactly one row per table"
    assert [row[0] for row in data] == sorted(graph, key=lambda n: (levels[n], n)), "Rows are not sorted by backup_level then table_name"
    assert len({row[0] for row in data}) == len(data)

    for table_name, level_text, path_text in data:
        assert table_name in graph, f"Unknown table in CSV: {table_name}"
        assert level_text == str(levels[table_name]), f"Wrong backup level for {table_name}"
        path = path_text.split("->")
        assert path[0] == table_name, f"Path for {table_name} must start at that table"
        assert all(part in graph for part in path), f"Path for {table_name} contains an unknown table"
        for current, dependency in zip(path, path[1:]):
            assert dependency in graph[current], f"Invalid dependency edge {current}->{dependency}"
        assert not graph[path[-1]], f"Path for {table_name} does not end at a level-0 table"
        assert len(path) - 1 == shortest_distance(graph, table_name), f"Path for {table_name} is not shortest"


def run_and_validate():
    if os.path.exists(TRACE):
        os.remove(TRACE)
    env = os.environ.copy()
    env["LD_PRELOAD"] = SHIM
    env["SQLITE_TRACE_LOG"] = TRACE
    result = subprocess.run([BINARY], cwd="/home/user", env=env, capture_output=True, text=True, timeout=20)
    assert result.returncode == 0, f"planner exited with {result.returncode}: {result.stderr}"
    trace = open(TRACE, encoding="utf-8").read().splitlines() if os.path.exists(TRACE) else []
    assert "OPEN" in trace, "planner did not open SQLite through the SQLite C API"
    assert "RECURSIVE_SQL" in trace, "planner did not execute a recursive CTE"
    validate_csv()


def install_dynamic_graph():
    prefix = "v" + secrets.token_hex(5)
    names = [prefix + suffix for suffix in ("_root_a", "_root_b", "_mid", "_deep", "_branch", "_top", "_isolated")]
    ids = [107, 211, 359, 487, 593, 719, 887]
    root_a, root_b, mid, deep, branch, top, isolated = ids
    con = sqlite3.connect(DATABASE)
    try:
        con.execute("DELETE FROM deps")
        con.execute("DELETE FROM tables")
        con.executemany("INSERT INTO tables(id, name) VALUES (?, ?)", list(zip(ids, names)))
        con.executemany("INSERT INTO deps(table_id, depends_on_id) VALUES (?, ?)", [
            (mid, root_a),
            (deep, mid),
            (branch, deep),
            (branch, root_b),
            (top, branch),
            (top, mid),
        ])
        con.commit()
    finally:
        con.close()


def main():
    require_artifacts()
    build_submission_and_audit_shim()
    shutil.copy2(DATABASE, DB_BACKUP)
    try:
        run_and_validate()
        install_dynamic_graph()
        run_and_validate()
    finally:
        shutil.copy2(DB_BACKUP, DATABASE)
        subprocess.run([BINARY], cwd="/home/user", stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, timeout=20)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

#!/bin/bash
mkdir -p /logs/verifier

cat <<'SHIM_EOF' > /tmp/sqlite_trace_shim.c
#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void log_sql(const char *sql) {
    const char *path = getenv("SQLTRACE_LOG");
    if (!path || !sql) return;
    FILE *f = fopen(path, "ab");
    if (!f) return;
    size_t n = strlen(sql);
    fprintf(f, "%zu\n", n);
    fwrite(sql, 1, n, f);
    fputc('\n', f);
    fclose(f);
}

int sqlite3_prepare(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare");
    log_sql(sql);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    log_sql(sql);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v3(sqlite3 *db, const char *sql, int n, unsigned int flags, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, unsigned int, sqlite3_stmt **, const char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v3");
    log_sql(sql);
    return real_fn(db, sql, n, flags, stmt, tail);
}

int sqlite3_exec(sqlite3 *db, const char *sql, int (*cb)(void *, int, char **, char **), void *arg, char **errmsg) {
    static int (*real_fn)(sqlite3 *, const char *, int (*)(void *, int, char **, char **), void *, char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_exec");
    log_sql(sql);
    return real_fn(db, sql, cb, arg, errmsg);
}
SHIM_EOF

cat <<'PY_EOF' > /tmp/test_final_state.py
import json
import os
import random
import re
import secrets
import sqlite3
import subprocess

SOURCE = "/home/user/analyze_backup.c"
BINARY = "/home/user/analyze_backup"
DB = "/home/user/backup.db"
OUTPUT = "/home/user/analytics.jsonl"
SHIM = "/tmp/libsqlite_trace.so"

FIXED_ROWS = [
    {"id": 1, "name": "root", "total_size": 5570, "rank": 1},
    {"id": 3, "name": "var", "total_size": 3800, "rank": 2},
    {"id": 7, "name": "log", "total_size": 3800, "rank": 2},
    {"id": 8, "name": "syslog", "total_size": 3000, "rank": 4},
    {"id": 2, "name": "usr", "total_size": 1700, "rank": 5},
    {"id": 4, "name": "bin", "total_size": 1700, "rank": 5},
    {"id": 5, "name": "bash", "total_size": 1200, "rank": 7},
    {"id": 9, "name": "auth.log", "total_size": 800, "rank": 8},
    {"id": 6, "name": "ls", "total_size": 500, "rank": 9},
    {"id": 10, "name": "etc", "total_size": 70, "rank": 10},
    {"id": 11, "name": "passwd", "total_size": 50, "rank": 11},
    {"id": 12, "name": "hosts", "total_size": 20, "rank": 12},
]

FIXED_NODES = [
    (1, None, "root", 0), (2, 1, "usr", 0), (3, 1, "var", 0),
    (4, 2, "bin", 0), (5, 4, "bash", 1200), (6, 4, "ls", 500),
    (7, 3, "log", 0), (8, 7, "syslog", 3000), (9, 7, "auth.log", 800),
    (10, 1, "etc", 0), (11, 10, "passwd", 50), (12, 10, "hosts", 20),
]

def read_output():
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} is missing."
    rows = []
    with open(OUTPUT, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            row = json.loads(line)
            assert set(row) == {"id", "name", "total_size", "rank"}, f"Incorrect JSON keys: {row}"
            assert type(row["id"]) is int
            assert type(row["name"]) is str
            assert type(row["total_size"]) is int
            assert type(row["rank"]) is int
            rows.append(row)
    ids = [r["id"] for r in rows]
    assert len(ids) == len(set(ids)), "Output contains duplicate node ids."
    return rows

def assert_rows(actual, expected):
    actual_dict = {r["id"]: r for r in actual}
    expected_dict = {r["id"]: r for r in expected}
    assert len(actual_dict) == len(expected_dict), f"Expected {len(expected_dict)} rows, got {len(actual_dict)}"
    for node_id, expected_row in expected_dict.items():
        assert node_id in actual_dict, f"Node id {node_id} missing from output."
        actual_row = actual_dict[node_id]
        assert actual_row["name"] == expected_row["name"]
        assert actual_row["total_size"] == expected_row["total_size"]
        assert actual_row["rank"] == expected_row["rank"]

def create_db(nodes):
    if os.path.exists(DB):
        os.remove(DB)
    conn = sqlite3.connect(DB)
    conn.execute("CREATE TABLE fs_nodes(id INTEGER PRIMARY KEY, parent_id INTEGER, name TEXT, size INTEGER)")
    conn.executemany("INSERT INTO fs_nodes VALUES (?,?,?,?)", nodes)
    conn.execute("CREATE INDEX idx_stale_size ON fs_nodes(size)")
    conn.commit()
    conn.close()

def expected_for(nodes):
    by_id = {row[0]: row for row in nodes}
    children = {node_id: [] for node_id in by_id}
    for node_id, parent_id, _, _ in nodes:
        if parent_id is not None:
            children[parent_id].append(node_id)

    memo = {}
    def total(node_id):
        if node_id not in memo:
            own = by_id[node_id][3] or 0
            memo[node_id] = own + sum(total(child) for child in children[node_id])
        return memo[node_id]

    totals = {node_id: total(node_id) for node_id in by_id}
    result = []
    for node_id, _, name, _ in nodes:
        rank = 1 + sum(1 for value in totals.values() if value > totals[node_id])
        result.append({"id": node_id, "name": name, "total_size": totals[node_id], "rank": rank})
    return result

def random_nodes():
    rng = random.SystemRandom()
    ids = rng.sample(range(101, 5000), 15)
    tag = secrets.token_hex(4)
    parents = [None, 0, 0, 1, 1, 2, 2, 3, 3, 4, 4, 5, 6, 7, 8]
    directory_positions = set(parents[1:])
    leaf_sizes = [137, 137, 509, 823, 1201, 41, 277, 661]
    rng.shuffle(leaf_sizes)
    leaf_index = 0
    nodes = []
    for pos, node_id in enumerate(ids):
        parent_id = None if parents[pos] is None else ids[parents[pos]]
        if pos in directory_positions:
            size = None if pos % 2 else 0
        else:
            size = leaf_sizes[leaf_index]
            leaf_index += 1
        nodes.append((node_id, parent_id, f"node_{tag}_{pos}", size))
    return nodes

def parse_trace(path):
    data = open(path, "rb").read()
    statements = []
    pos = 0
    while pos < len(data):
        end = data.find(b"\n", pos)
        assert end >= 0, "Malformed SQL trace."
        length = int(data[pos:end])
        start = end + 1
        statements.append(data[start:start + length].decode("utf-8", "replace"))
        pos = start + length
        assert pos < len(data) and data[pos:pos + 1] == b"\n", "Malformed SQL trace."
        pos += 1
    return statements

def run_and_check(executable, nodes, trace_path):
    create_db(nodes)
    with open(OUTPUT, "w", encoding="utf-8") as f:
        f.write("this stale output must be replaced\n")
    if os.path.exists(trace_path):
        os.remove(trace_path)
    env = os.environ.copy()
    env["LD_PRELOAD"] = SHIM
    env["SQLTRACE_LOG"] = trace_path
    proc = subprocess.run([executable], cwd="/home/user", env=env, text=True,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20)
    assert proc.returncode == 0, f"Program failed: {proc.stderr}"
    assert_rows(read_output(), expected_for(nodes))

    statements = parse_trace(trace_path)
    advanced = []
    for sql in statements:
        upper = sql.upper()
        if re.search(r"WITH\s+RECURSIVE", upper) and re.search(r"RANK\s*\(\s*\)\s*OVER", upper):
            advanced.append(upper)
    assert advanced, "No executed SQL statement used both WITH RECURSIVE and RANK() OVER."

    conn = sqlite3.connect(DB)
    index_exists = conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type='index' AND name='idx_stale_size'"
    ).fetchone() is not None
    conn.close()
    if index_exists:
        assert any("NOT INDEXED" in sql for sql in advanced), (
            "idx_stale_size remained present and the analytics query did not bypass indexes with NOT INDEXED."
        )

def test_complete_task():
    assert os.path.isfile(SOURCE), f"C source file {SOURCE} is missing."
    assert os.path.isfile(BINARY), f"Compiled binary {BINARY} is missing."
    assert os.access(BINARY, os.X_OK), f"Binary {BINARY} is not executable."
    with open(BINARY, "rb") as f:
        assert f.read(4) == b"\x7fELF", "analyze_backup is not a compiled executable."

    # Preserve the original verifier's assertion about the initially generated result.
    assert_rows(read_output(), FIXED_ROWS)

    source = open(SOURCE, "r", encoding="utf-8").read()
    assert re.search(r"^\s*#\s*include\s*[<\"]sqlite3\.h[>\"]", source, re.MULTILINE), (
        "The source does not include sqlite3.h."
    )
    upper_source = source.upper()
    assert re.search(r"WITH\s+RECURSIVE", upper_source), "Source lacks WITH RECURSIVE."
    assert re.search(r"RANK\s*\(\s*\)\s*OVER", upper_source), "Source lacks RANK() OVER."
    assert re.search(r"SQLITE3_(OPEN|OPEN_V2)\s*\(", upper_source), "Source does not open SQLite through its C API."
    assert re.search(r"SQLITE3_(PREPARE|PREPARE_V2|PREPARE_V3|EXEC)\s*\(", upper_source), (
        "Source does not execute SQL through the SQLite C API."
    )

    rebuilt = "/tmp/analyze_backup_rebuilt"
    compile_proc = subprocess.run(
        ["gcc", "-std=c11", SOURCE, "-lsqlite3", "-o", rebuilt],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert compile_proc.returncode == 0, f"Source does not compile and link with -lsqlite3: {compile_proc.stderr}"

    # Execute the submitted artifact on the known data, then execute a fresh build
    # on unpredictable data so a pre-generated JSON file cannot pass.
    run_and_check(BINARY, FIXED_NODES, "/tmp/sqltrace_submitted.log")
    run_and_check(rebuilt, random_nodes(), "/tmp/sqltrace_rebuilt.log")
PY_EOF

if gcc -shared -fPIC /tmp/sqlite_trace_shim.c -o /tmp/libsqlite_trace.so -ldl -lsqlite3 \
   && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import heapq
import os
import re
import secrets
import shutil
import sqlite3
import subprocess
import textwrap

import pytest

DB_PATH = "/home/user/network.db"
C_SOURCE_PATH = "/home/user/analyze_network.c"
EXECUTABLE_PATH = "/home/user/analyze_network"
CSV_PATH = "/home/user/optimized_path_stats.csv"


def get_expected_data(db_path):
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cur = conn.cursor()

    cur.execute("SELECT * FROM nodes")
    nodes = {row['id']: row['hostname'] for row in cur.fetchall()}
    cur.execute("SELECT * FROM edges")
    edges = cur.fetchall()

    gateway_id = next((k for k, v in nodes.items() if v == 'Gateway'), None)
    db_id = next((k for k, v in nodes.items() if v == 'Database'), None)
    if gateway_id is None or db_id is None:
        pytest.fail("Database missing 'Gateway' or 'Database' nodes.")

    queue = [(0, gateway_id, [gateway_id])]
    visited = set()
    shortest_path = []
    while queue:
        cost, curr, path = heapq.heappop(queue)
        if curr == db_id:
            shortest_path = path
            break
        if curr in visited:
            continue
        visited.add(curr)
        for edge in edges:
            if edge['source_id'] == curr:
                heapq.heappush(queue, (
                    cost + edge['latency'], edge['target_id'],
                    path + [edge['target_id']]
                ))

    cur.execute("SELECT * FROM bandwidth_logs ORDER BY timestamp")
    logs = cur.fetchall()
    expected_csv = []
    for node_id in shortest_path:
        node_logs = [log for log in logs if log['node_id'] == node_id]
        node_logs.sort(key=lambda row: row['timestamp'])
        for i, log in enumerate(node_logs):
            window = node_logs[max(0, i - 1):min(len(node_logs), i + 2)]
            avg = sum(row['bytes_transferred'] for row in window) / len(window)
            expected_csv.append([
                str(node_id), nodes[node_id], log['timestamp'], f"{avg:.2f}"
            ])

    conn.close()
    return expected_csv


def assert_csv(expected_data):
    assert os.path.isfile(CSV_PATH), f"CSV output file missing at {CSV_PATH}"
    with open(CSV_PATH, 'r', newline='') as handle:
        reader = csv.reader(handle)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail(f"CSV file {CSV_PATH} is empty.")
        expected_header = ['node_id', 'hostname', 'timestamp', 'smoothed_bytes']
        assert header == expected_header, \
            f"CSV header mismatch. Expected {expected_header}, got {header}"
        actual_data = list(reader)

    assert len(actual_data) == len(expected_data), \
        f"CSV row count mismatch. Expected {len(expected_data)} rows, got {len(actual_data)}"
    for i, (actual_row, expected_row) in enumerate(zip(actual_data, expected_data)):
        assert actual_row == expected_row, \
            f"Row {i+1} mismatch. Expected {expected_row}, got {actual_row}"


def test_c_source_exists():
    assert os.path.isfile(C_SOURCE_PATH), f"C source file missing at {C_SOURCE_PATH}"


def test_executable_exists():
    assert os.path.isfile(EXECUTABLE_PATH), f"Compiled executable missing at {EXECUTABLE_PATH}"
    assert os.access(EXECUTABLE_PATH, os.X_OK), f"File at {EXECUTABLE_PATH} is not executable"
    with open(EXECUTABLE_PATH, 'rb') as handle:
        assert handle.read(4) == b'\x7fELF', \
            f"File at {EXECUTABLE_PATH} is not a compiled native executable"


def test_csv_output_exists_and_correct():
    assert_csv(get_expected_data(DB_PATH))


def build_trace_library():
    source = r'''
#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

typedef int (*open_fn)(const char *, sqlite3 **);
typedef int (*open_v2_fn)(const char *, sqlite3 **, int, const char *);
typedef int (*trace_fn)(sqlite3 *, unsigned, int (*)(unsigned, void *, void *, void *), void *);

static int trace_callback(unsigned kind, void *ctx, void *stmt, void *sqlptr) {
    (void)ctx;
    (void)stmt;
    if ((kind & SQLITE_TRACE_STMT) && sqlptr) {
        const char *path = getenv("SQL_TRACE_FILE");
        const char *sql = (const char *)sqlptr;
        if (path && *path && sql) {
            size_t n = strlen(sql);
            char *record = malloc(n + 1);
            if (record) {
                memcpy(record, sql, n);
                record[n] = '\0';
                int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0600);
                if (fd >= 0) {
                    (void)write(fd, record, n + 1);
                    close(fd);
                }
                free(record);
            }
        }
    }
    return 0;
}

static void install_trace(sqlite3 *db) {
    trace_fn trace = (trace_fn)dlsym(RTLD_NEXT, "sqlite3_trace_v2");
    if (trace && db)
        trace(db, SQLITE_TRACE_STMT, trace_callback, NULL);
}

int sqlite3_open(const char *name, sqlite3 **db) {
    open_fn real_open = (open_fn)dlsym(RTLD_NEXT, "sqlite3_open");
    int rc = real_open(name, db);
    if (rc == SQLITE_OK)
        install_trace(*db);
    return rc;
}

int sqlite3_open_v2(const char *name, sqlite3 **db, int flags, const char *vfs) {
    open_v2_fn real_open = (open_v2_fn)dlsym(RTLD_NEXT, "sqlite3_open_v2");
    int rc = real_open(name, db, flags, vfs);
    if (rc == SQLITE_OK)
        install_trace(*db);
    return rc;
}
'''
    shim_c = "/tmp/sqlite_trace_shim.c"
    shim_so = "/tmp/sqlite_trace_shim.so"
    with open(shim_c, "w") as handle:
        handle.write(source)
    result = subprocess.run(
        ["gcc", "-shared", "-fPIC", shim_c, "-o", shim_so, "-ldl", "-lsqlite3"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert result.returncode == 0, f"Could not build verification shim: {result.stderr}"
    return shim_so


def install_random_database():
    ids = secrets.SystemRandom().sample(range(20, 900), 6)
    gateway, fast_a, fast_b, slow, database, unused = ids
    salt = secrets.randbelow(10000) + 1000

    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.executescript("DELETE FROM bandwidth_logs; DELETE FROM edges; DELETE FROM nodes;")
    cur.executemany("INSERT INTO nodes(id, hostname) VALUES (?, ?)", [
        (gateway, 'Gateway'), (fast_a, 'Relay-' + str(salt)),
        (fast_b, 'Core-' + str(salt)), (slow, 'Detour-' + str(salt)),
        (database, 'Database'), (unused, 'Unused-' + str(salt))
    ])
    cur.executemany("INSERT INTO edges VALUES (?, ?, ?)", [
        (gateway, fast_a, 4), (fast_a, fast_b, 7), (fast_b, database, 5),
        (gateway, slow, 40), (slow, database, 30),
        (fast_a, slow, 50), (gateway, database, 90)
    ])

    timestamps = [
        '2041-07-03 09:00:00', '2041-07-03 09:03:00',
        '2041-07-03 09:09:00', '2041-07-03 09:20:00'
    ]
    rows = []
    for position, node_id in enumerate([gateway, fast_a, fast_b, database, slow, unused]):
        base = salt + position * 137
        values = [base + 11, base + 83, base + 29, base + 197]
        rows.extend((node_id, ts, value) for ts, value in zip(timestamps, values))
    cur.executemany("INSERT INTO bandwidth_logs VALUES (?, ?, ?)", rows)
    conn.commit()
    conn.close()


def strip_sql_comments(sql):
    sql = re.sub(r"/\*.*?\*/", " ", sql, flags=re.S)
    sql = re.sub(r"--[^\r\n]*", " ", sql)
    return re.sub(r"\s+", " ", sql).strip().lower()


def run_and_verify_program(program, trace_file, shim, expected):
    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)
    if os.path.exists(trace_file):
        os.remove(trace_file)

    env = os.environ.copy()
    env['LD_PRELOAD'] = shim
    env['SQL_TRACE_FILE'] = trace_file
    result = subprocess.run(
        [program], cwd="/home/user", env=env, timeout=20,
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert result.returncode == 0, \
        f"{program} failed when executed: {result.stderr or result.stdout}"
    assert_csv(expected)
    assert os.path.isfile(trace_file), \
        f"{program} did not execute SQLite statements through its database connection"

    with open(trace_file, 'rb') as handle:
        statements = [part.decode('utf-8', 'replace') for part in handle.read().split(b'\0') if part]
    cleaned = [strip_sql_comments(statement) for statement in statements]
    table_statements = [
        statement for statement in cleaned
        if re.search(r"\b(nodes|edges|bandwidth_logs)\b", statement)
    ]
    assert len(table_statements) == 1, \
        f"Expected one data-extraction SQL statement, observed {len(table_statements)}: {table_statements}"

    query = table_statements[0]
    assert re.search(r"\bwith\s+recursive\b", query), "Executed query lacks a recursive CTE"
    assert all(re.search(rf"\b{name}\b", query) for name in ('nodes', 'edges', 'bandwidth_logs')), \
        "Executed query must combine nodes, edges, and bandwidth_logs"
    assert re.search(r"\bjoin\b", query), "Executed query does not join the required tables"
    assert re.search(r"\blatency\b", query), "Recursive path query does not use edge latency"
    assert re.search(r"\bavg\s*\([^)]*bytes_transferred[^)]*\)\s*over\s*\(", query), \
        "Executed query lacks the required AVG window function"
    assert re.search(r"rows\s+between\s+1\s+preceding\s+and\s+1\s+following", query), \
        "Window frame is not current row plus one preceding and one following"


def test_program_and_source_execute_required_pipeline_on_new_data():
    backup = "/tmp/network.db.verifier-backup"
    shutil.copy2(DB_PATH, backup)
    shim = build_trace_library()
    compiled = "/tmp/analyze_network_from_source"
    try:
        install_random_database()
        expected = get_expected_data(DB_PATH)

        compile_result = subprocess.run(
            ["gcc", "-std=c11", "-O2", C_SOURCE_PATH, "-o", compiled, "-lsqlite3", "-lm"],
            text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
        )
        assert compile_result.returncode == 0, \
            f"Submitted C source does not compile: {compile_result.stderr}"

        run_and_verify_program(EXECUTABLE_PATH, "/tmp/submitted_executable.sqltrace", shim, expected)
        run_and_verify_program(compiled, "/tmp/compiled_source.sqltrace", shim, expected)
    finally:
        for suffix in ('', '-wal', '-shm'):
            path = DB_PATH + suffix
            if os.path.exists(path):
                os.remove(path)
        shutil.copy2(backup, DB_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

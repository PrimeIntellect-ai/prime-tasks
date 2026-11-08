#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TRACE_EOF' > /tmp/sqlite_trace.c
#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <stdlib.h>
#include <unistd.h>

static void mark(char c) {
    const char *path = getenv("SQLITE_API_TRACE");
    if (!path) return;
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (fd >= 0) {
        write(fd, &c, 1);
        close(fd);
    }
}

int sqlite3_open(const char *filename, sqlite3 **db) {
    static int (*real_fn)(const char *, sqlite3 **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_open");
    mark('O');
    return real_fn(filename, db);
}

int sqlite3_open_v2(const char *filename, sqlite3 **db, int flags, const char *vfs) {
    static int (*real_fn)(const char *, sqlite3 **, int, const char *) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_open_v2");
    mark('O');
    return real_fn(filename, db, flags, vfs);
}

int sqlite3_open16(const void *filename, sqlite3 **db) {
    static int (*real_fn)(const void *, sqlite3 **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_open16");
    mark('O');
    return real_fn(filename, db);
}

int sqlite3_prepare(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare");
    mark('Q');
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    mark('Q');
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v3(sqlite3 *db, const char *sql, int n, unsigned int flags, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, unsigned int, sqlite3_stmt **, const char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v3");
    mark('Q');
    return real_fn(db, sql, n, flags, stmt, tail);
}

int sqlite3_exec(sqlite3 *db, const char *sql, int (*cb)(void *, int, char **, char **), void *arg, char **errmsg) {
    static int (*real_fn)(sqlite3 *, const char *, int (*)(void *, int, char **, char **), void *, char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_exec");
    mark('Q');
    return real_fn(db, sql, cb, arg, errmsg);
}

int sqlite3_get_table(sqlite3 *db, const char *sql, char ***result, int *rows, int *cols, char **errmsg) {
    static int (*real_fn)(sqlite3 *, const char *, char ***, int *, int *, char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_get_table");
    mark('Q');
    return real_fn(db, sql, result, rows, cols, errmsg);
}
TRACE_EOF

gcc -shared -fPIC /tmp/sqlite_trace.c -o /tmp/sqlite_trace.so -ldl -lsqlite3

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import secrets
import shutil
import sqlite3
import subprocess
import pytest

CSV_PATH = "/home/user/hubs.csv"
DB_PATH = "/home/user/kg_data.db"
CPP_PATH = "/home/user/process_kg.cpp"
BIN_PATH = "/home/user/process_kg"
TRACE_LIB = "/tmp/sqlite_trace.so"
TRACE_PATH = "/tmp/sqlite_api_calls.log"
TIMESTAMP = 1700000000


def get_expected_hubs():
    if not os.path.exists(DB_PATH):
        pytest.fail(f"Database file {DB_PATH} is missing. Cannot compute expected results.")

    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    c = conn.cursor()

    c.execute("SELECT id, label FROM nodes WHERE valid_from <= ? AND valid_to > ?", (TIMESTAMP, TIMESTAMP))
    active_nodes = {row['id']: row['label'] for row in c.fetchall()}

    c.execute("SELECT source_id, target_id FROM edges WHERE valid_from <= ? AND valid_to > ?", (TIMESTAMP, TIMESTAMP))
    in_degree = {n: 0 for n in active_nodes}
    out_degree = {n: 0 for n in active_nodes}

    for row in c.fetchall():
        src = row['source_id']
        tgt = row['target_id']
        if src in active_nodes and tgt in active_nodes:
            out_degree[src] += 1
            in_degree[tgt] += 1

    conn.close()

    hubs = []
    for n, label in active_nodes.items():
        total = in_degree[n] + out_degree[n]
        if total >= 3:
            hubs.append({
                'node_id': n,
                'label': label,
                'in_degree': in_degree[n],
                'out_degree': out_degree[n],
                'total_degree': total
            })
    hubs.sort(key=lambda x: (-x['total_degree'], x['node_id']))
    return hubs


def run_program():
    if os.path.lexists(CSV_PATH):
        os.remove(CSV_PATH)
    if os.path.exists(TRACE_PATH):
        os.remove(TRACE_PATH)

    env = os.environ.copy()
    env['LD_PRELOAD'] = TRACE_LIB
    env['SQLITE_API_TRACE'] = TRACE_PATH
    result = subprocess.run(
        [BIN_PATH], cwd="/home/user", env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert result.returncode == 0, f"process_kg exited with {result.returncode}: {result.stderr}"
    assert os.path.isfile(CSV_PATH), f"Expected output file {CSV_PATH} was not generated."
    trace = b''
    if os.path.exists(TRACE_PATH):
        with open(TRACE_PATH, 'rb') as f:
            trace = f.read()
    assert b'O' in trace, "The program did not connect to SQLite through the sqlite3 C/C++ API."
    assert b'Q' in trace, "The program did not execute a query through the sqlite3 C/C++ API."


def read_csv_rows():
    with open(CSV_PATH, 'r', encoding='utf-8', newline='') as f:
        return list(csv.reader(f))


def assert_csv_matches_expected(expected_hubs):
    rows = read_csv_rows()
    expected_header = ['node_id', 'label', 'in_degree', 'out_degree', 'total_degree']
    assert rows, f"{CSV_PATH} is empty."
    assert rows[0] == expected_header, f"CSV header is incorrect. Expected {expected_header}, got {rows[0]}"
    actual_rows = rows[1:]
    assert len(actual_rows) == len(expected_hubs), \
        f"Expected {len(expected_hubs)} hub nodes, but found {len(actual_rows)} in the CSV."
    for i, (actual, expected) in enumerate(zip(actual_rows, expected_hubs)):
        assert len(actual) == 5, f"Row {i+1} is malformed: {actual}"
        try:
            parsed = [int(actual[0]), actual[1], int(actual[2]), int(actual[3]), int(actual[4])]
        except ValueError as e:
            pytest.fail(f"Row {i+1} is malformed: {actual}. Error: {e}")
        wanted = [expected['node_id'], expected['label'], expected['in_degree'], expected['out_degree'], expected['total_degree']]
        assert parsed == wanted, f"Row {i+1}: expected {wanted}, got {parsed}"


def create_random_database(seed):
    rng = random.Random(seed)
    nonce = secrets.token_hex(6)
    ids = rng.sample(range(1000, 9000), 10)
    active_ids = ids[:8]
    stale_ids = ids[8:]

    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("CREATE TABLE nodes (id INTEGER, label TEXT, valid_from INTEGER, valid_to INTEGER)")
    c.execute("CREATE TABLE edges (source_id INTEGER, target_id INTEGER, type TEXT, valid_from INTEGER, valid_to INTEGER)")

    nodes = []
    for i, node_id in enumerate(active_ids):
        nodes.append((node_id, f"N{nonce}_{i}", TIMESTAMP - rng.randint(1, 50000), TIMESTAMP + rng.randint(1, 50000)))
    nodes.append((stale_ids[0], f"STALE_{nonce}_0", TIMESTAMP - 50000, TIMESTAMP))
    nodes.append((stale_ids[1], f"FUTURE_{nonce}_1", TIMESTAMP + 1, TIMESTAMP + 50000))
    c.executemany("INSERT INTO nodes VALUES (?,?,?,?)", nodes)

    pairs = [(a, b) for a in active_ids for b in active_ids if a != b]
    rng.shuffle(pairs)
    chosen = pairs[:18]
    edges = [(a, b, f"R{nonce}", TIMESTAMP - rng.randint(1, 10000), TIMESTAMP + rng.randint(1, 10000)) for a, b in chosen]
    edges.extend([
        (active_ids[0], stale_ids[0], 'INVALID_ENDPOINT', TIMESTAMP - 10, TIMESTAMP + 10),
        (stale_ids[1], active_ids[1], 'INVALID_ENDPOINT', TIMESTAMP - 10, TIMESTAMP + 10),
        (active_ids[2], active_ids[3], 'EXPIRED', TIMESTAMP - 100, TIMESTAMP),
        (active_ids[4], active_ids[5], 'FUTURE', TIMESTAMP + 1, TIMESTAMP + 100),
    ])
    c.executemany("INSERT INTO edges VALUES (?,?,?,?,?)", edges)
    conn.commit()
    conn.close()


def test_00_cpp_exists_and_compiles():
    assert os.path.exists(CPP_PATH), f"Expected C++ source {CPP_PATH} was not found."
    assert os.path.isfile(CPP_PATH), f"{CPP_PATH} is not a regular file."
    result = subprocess.run(
        ['g++', 'process_kg.cpp', '-o', 'process_kg', '-lsqlite3'],
        cwd='/home/user', stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert result.returncode == 0, f"C++ program failed to compile: {result.stderr}"
    assert os.path.isfile(BIN_PATH) and os.access(BIN_PATH, os.X_OK), "Compiled process_kg executable is missing."


def test_01_execute_program():
    run_program()


def test_hubs_csv_exists():
    assert os.path.exists(CSV_PATH), f"Expected output file {CSV_PATH} was not found."
    assert os.path.isfile(CSV_PATH), f"{CSV_PATH} is not a valid file."


def test_hubs_csv_contents():
    if not os.path.exists(CSV_PATH):
        pytest.fail(f"Cannot test contents because {CSV_PATH} does not exist.")

    expected_hubs = get_expected_hubs()
    with open(CSV_PATH, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail(f"{CSV_PATH} is empty.")

        expected_header = ['node_id', 'label', 'in_degree', 'out_degree', 'total_degree']
        assert header == expected_header, f"CSV header is incorrect. Expected {expected_header}, got {header}"
        actual_rows = list(reader)

    assert len(actual_rows) == len(expected_hubs), \
        f"Expected {len(expected_hubs)} hub nodes, but found {len(actual_rows)} in the CSV."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_hubs)):
        try:
            actual_node_id = int(actual[0])
            actual_label = actual[1]
            actual_in = int(actual[2])
            actual_out = int(actual[3])
            actual_total = int(actual[4])
        except (ValueError, IndexError) as e:
            pytest.fail(f"Row {i+1} is malformed: {actual}. Error: {e}")

        assert actual_node_id == expected['node_id'], f"Row {i+1}: expected node_id {expected['node_id']}, got {actual_node_id}"
        assert actual_label == expected['label'], f"Row {i+1}: expected label {expected['label']}, got {actual_label}"
        assert actual_in == expected['in_degree'], f"Row {i+1} (Node {actual_node_id}): expected in_degree {expected['in_degree']}, got {actual_in}"
        assert actual_out == expected['out_degree'], f"Row {i+1} (Node {actual_node_id}): expected out_degree {expected['out_degree']}, got {actual_out}"
        assert actual_total == expected['total_degree'], f"Row {i+1} (Node {actual_node_id}): expected total_degree {expected['total_degree']}, got {actual_total}"


def test_dynamic_databases_are_processed():
    backup = "/tmp/kg_data.original.db"
    shutil.copy2(DB_PATH, backup)
    try:
        for _ in range(2):
            if os.path.exists(DB_PATH):
                os.remove(DB_PATH)
            create_random_database(secrets.randbits(64))
            expected = get_expected_hubs()
            run_program()
            assert_csv_matches_expected(expected)
    finally:
        if os.path.exists(DB_PATH):
            os.remove(DB_PATH)
        shutil.copy2(backup, DB_PATH)
        run_program()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'WRAP_EOF' > /tmp/sqlite_trace.c
#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void log_sql(const char *sql) {
    const char *path = getenv("ANALYZER_SQL_LOG");
    if (!path || !sql) return;
    FILE *f = fopen(path, "ab");
    if (!f) return;
    fwrite(sql, 1, strlen(sql), f);
    fputc('\0', f);
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

int sqlite3_get_table(sqlite3 *db, const char *sql, char ***result, int *rows, int *cols, char **errmsg) {
    static int (*real_fn)(sqlite3 *, const char *, char ***, int *, int *, char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_get_table");
    log_sql(sql);
    return real_fn(db, sql, result, rows, cols, errmsg);
}
WRAP_EOF
gcc -shared -fPIC /tmp/sqlite_trace.c -o /tmp/sqlite_trace.so -ldl -lsqlite3

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import random
import re
import secrets
import sqlite3
import subprocess

SOURCE = "/home/user/analyzer.c"
EXE = "/home/user/analyzer"
DB = "/home/user/research_data.db"
CSV = "/home/user/descendant_metrics.csv"
TRACE = "/tmp/analyzer_sql.log"
PRELOAD = "/tmp/sqlite_trace.so"

ORIGINAL_EDGES = [
    (100, 101), (100, 102), (101, 103), (101, 104),
    (102, 104), (102, 105), (200, 104), (201, 104),
    (202, 105), (203, 101),
]
ORIGINAL_EXPECTED = [
    "104,4,1",
    "101,2,2",
    "105,2,2",
    "102,1,3",
    "103,1,3",
]

def create_db(edges):
    if os.path.exists(DB):
        os.remove(DB)
    con = sqlite3.connect(DB)
    try:
        con.execute("CREATE TABLE citations (source_id INTEGER, target_id INTEGER)")
        con.executemany("INSERT INTO citations VALUES (?, ?)", edges)
        con.commit()
    finally:
        con.close()


def read_csv():
    assert os.path.isfile(CSV), f"Output CSV file {CSV} is missing."
    with open(CSV, "r", newline="") as f:
        return [line.strip() for line in f if line.strip()]


def run_and_check_query():
    for path in (CSV, TRACE):
        if os.path.exists(path):
            os.remove(path)
    env = os.environ.copy()
    env["LD_PRELOAD"] = PRELOAD
    env["ANALYZER_SQL_LOG"] = TRACE
    completed = subprocess.run(
        [EXE], cwd="/home/user", env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=15
    )
    assert completed.returncode == 0, (
        f"Analyzer exited with status {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )
    assert os.path.isfile(TRACE), "Analyzer did not execute SQL through SQLite."
    with open(TRACE, "rb") as f:
        statements = [x.decode("utf-8", "replace").strip() for x in f.read().split(b"\0") if x.strip()]
    normalized = {re.sub(r"\s+", " ", s).strip() for s in statements}
    assert len(normalized) == 1, f"Analyzer must execute one SQL query; observed: {statements!r}"
    query = next(iter(normalized))
    assert re.search(r"\bWITH\s+RECURSIVE\b", query, re.I), "Executed query does not use a recursive CTE."
    assert re.search(r"\bDENSE_RANK\s*\(", query, re.I), "Executed query does not use DENSE_RANK()."
    return read_csv()


def dynamic_case():
    rng = random.Random(secrets.randbits(64))
    pool = list(range(1000, 9000))
    rng.shuffle(pool)
    direct = pool[:4]
    second = pool[4:9]
    edges = [(100, node) for node in direct]

    used = set(edges)
    for i, node in enumerate(second):
        edge = (direct[i % len(direct)], node)
        edges.append(edge)
        used.add(edge)
    for source in direct:
        choices = [node for node in second if (source, node) not in used]
        target = rng.choice(choices)
        edges.append((source, target))
        used.add((source, target))

    descendants = direct + second
    outsider = 20000
    for target in descendants:
        for _ in range(rng.randrange(0, 8)):
            edges.append((outsider, target))
            outsider += 1

    for _ in range(7):
        edges.append((outsider, outsider + 1))
        outsider += 2

    incoming = collections.Counter(target for _, target in edges)
    distinct_counts = sorted({incoming[node] for node in descendants}, reverse=True)
    ranks = {count: i + 1 for i, count in enumerate(distinct_counts)}
    expected = [
        f"{node},{incoming[node]},{ranks[incoming[node]]}"
        for node in sorted(descendants, key=lambda n: (ranks[incoming[n]], n))
    ]
    return edges, expected


def test_final_state_and_analysis():
    # Preserve the original final-state assertions.
    assert os.path.isfile(SOURCE), "C source file /home/user/analyzer.c is missing."
    assert os.path.isfile(EXE), "Compiled executable /home/user/analyzer is missing."
    assert os.access(EXE, os.X_OK), "/home/user/analyzer is not executable."

    # Compile the submitted source using the command required by the instruction.
    compiled = subprocess.run(
        ["gcc", SOURCE, "-o", EXE, "-lsqlite3"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert compiled.returncode == 0, f"analyzer.c failed to compile:\n{compiled.stderr}"

    # Exercise the supplied dataset and retain the original exact CSV assertion.
    create_db(ORIGINAL_EDGES)
    actual = run_and_check_query()
    assert actual == ORIGINAL_EXPECTED, (
        f"CSV output does not match expected results.\n"
        f"Expected:\n{ORIGINAL_EXPECTED}\nActual:\n{actual}"
    )

    # Exercise a hidden, varying graph so hardcoded CSV output cannot pass.
    edges, expected = dynamic_case()
    create_db(edges)
    actual = run_and_check_query()
    assert actual == expected, (
        f"Analyzer produced incorrect results on an additional citation graph.\n"
        f"Expected:\n{expected}\nActual:\n{actual}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

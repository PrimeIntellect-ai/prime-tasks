#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TRACE_EOF' > /tmp/sqlite_trace.c
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <sqlite3.h>

static void log_text(const char *kind, const char *text) {
    const char *path = getenv("SQLITE_TRACE_LOG");
    if (!path) return;
    FILE *f = fopen(path, "a");
    if (!f) return;
    fprintf(f, "%s ", kind);
    if (text) {
        for (const char *p = text; *p; ++p)
            fputc((*p == '\n' || *p == '\r') ? ' ' : *p, f);
    }
    fputc('\n', f);
    fclose(f);
}

int sqlite3_open(const char *filename, sqlite3 **db) {
    static int (*real_fn)(const char *, sqlite3 **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_open");
    log_text("OPEN", filename);
    return real_fn(filename, db);
}

int sqlite3_open_v2(const char *filename, sqlite3 **db, int flags, const char *vfs) {
    static int (*real_fn)(const char *, sqlite3 **, int, const char *) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_open_v2");
    log_text("OPEN_V2", filename);
    return real_fn(filename, db, flags, vfs);
}

int sqlite3_exec(sqlite3 *db, const char *sql, int (*cb)(void*,int,char**,char**), void *arg, char **errmsg) {
    static int (*real_fn)(sqlite3 *, const char *, int (*)(void*,int,char**,char**), void *, char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_exec");
    log_text("EXEC", sql);
    return real_fn(db, sql, cb, arg, errmsg);
}

int sqlite3_prepare(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare");
    log_text("PREPARE", sql);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    log_text("PREPARE_V2", sql);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v3(sqlite3 *db, const char *sql, int n, unsigned int flags, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, unsigned int, sqlite3_stmt **, const char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v3");
    log_text("PREPARE_V3", sql);
    return real_fn(db, sql, n, flags, stmt, tail);
}

int sqlite3_get_table(sqlite3 *db, const char *sql, char ***result, int *rows, int *cols, char **errmsg) {
    static int (*real_fn)(sqlite3 *, const char *, char ***, int *, int *, char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_get_table");
    log_text("GET_TABLE", sql);
    return real_fn(db, sql, result, rows, cols, errmsg);
}
TRACE_EOF

if ! gcc -shared -fPIC -o /tmp/sqlite_trace.so /tmp/sqlite_trace.c -ldl; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import os
import random
import re
import subprocess


def test_cpp_source_exists():
    """Verify that the C++ source file exists."""
    cpp_file = "/home/user/analyze.cpp"
    assert os.path.isfile(cpp_file), f"C++ source file {cpp_file} is missing."


def test_executable_exists():
    """Verify that the compiled executable exists and is executable."""
    exe_file = "/home/user/analyze"
    assert os.path.isfile(exe_file), f"Executable {exe_file} is missing."
    assert os.access(exe_file, os.X_OK), f"File {exe_file} is not executable."
    with open(exe_file, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The compiled analyze artifact is not an ELF executable."


def test_output_file_exists():
    """Verify that the output CSV file exists."""
    output_file = "/home/user/top_accounts.csv"
    assert os.path.isfile(output_file), f"Output file {output_file} is missing."


def test_output_file_content():
    """Verify that the output CSV file contains exactly the expected top 3 accounts."""
    output_file = "/home/user/top_accounts.csv"
    with open(output_file, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "7,4",
        "1,3",
        "4,3"
    ]

    assert len(lines) == 3, f"Expected exactly 3 lines in {output_file}, but found {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} mismatch: expected '{expected}', got '{actual}'."


def derive_expected(accounts, transactions):
    active = {account_id for account_id, status, _ in accounts if status == "ACTIVE"}
    degree = collections.Counter()
    nodes = set()
    for source, target, amount in transactions:
        if amount > 500.0 and source in active and target in active:
            nodes.add(source)
            nodes.add(target)
            degree[source] += 1
    ranked = sorted(nodes, key=lambda account_id: (-degree[account_id], account_id))
    assert len(ranked) >= 3
    return [f"{account_id},{degree[account_id]}" for account_id in ranked[:3]]


def write_inputs(accounts, transactions):
    with open("/home/user/accounts.csv", "w", newline="") as f:
        f.write("account_id,status,type\n")
        for account_id, status, kind in accounts:
            f.write(f"{account_id},{status},{kind}\n")
    with open("/home/user/transactions.csv", "w", newline="") as f:
        f.write("source,target,amount\n")
        for source, target, amount in transactions:
            f.write(f"{source},{target},{amount}\n")


def make_cases():
    rng = random.SystemRandom()
    cases = []

    ids = rng.sample(range(1000, 9000), 7)
    a, b, c, d, e, f, inactive = ids
    accounts = [(x, "ACTIVE", "Checking") for x in ids[:6]] + [(inactive, "INACTIVE", "Savings")]
    transactions = [
        (a, c, 501.25), (a, d, 700.0), (a, e, 1200.0),
        (b, c, 900.0), (b, d, 650.0), (b, e, 501.0),
        (c, d, 800.0), (c, f, 750.0), (d, e, 600.0),
        (a, inactive, 9999.0), (inactive, b, 9999.0),
        (e, f, 500.0), (f, a, 499.99)
    ]
    rng.shuffle(accounts)
    rng.shuffle(transactions)
    cases.append((accounts, transactions))

    ids = rng.sample(range(10000, 50000), 6)
    source1, source2, low_target, other_target, spare, inactive = ids
    accounts = [
        (source1, "ACTIVE", "A"), (source2, "ACTIVE", "B"),
        (low_target, "ACTIVE", "C"), (other_target, "ACTIVE", "D"),
        (spare, "ACTIVE", "E"), (inactive, "INACTIVE", "F")
    ]
    transactions = [
        (source1, low_target, 501.0),
        (source1, other_target, 777.0),
        (source2, source1, 600.0),
        (low_target, other_target, 500.0),
        (other_target, inactive, 800.0),
        (inactive, spare, 1000.0),
        (spare, source1, 12.0)
    ]
    rng.shuffle(accounts)
    rng.shuffle(transactions)
    cases.append((accounts, transactions))
    return cases


def test_executable_recomputes_using_sqlite_and_join():
    paths = ["/home/user/accounts.csv", "/home/user/transactions.csv", "/home/user/top_accounts.csv"]
    backups = {}
    for path in paths:
        backups[path] = open(path, "rb").read() if os.path.exists(path) else None

    trace_path = "/tmp/analyze_sqlite_trace.log"
    if os.path.exists(trace_path):
        os.unlink(trace_path)

    try:
        for accounts, transactions in make_cases():
            expected = derive_expected(accounts, transactions)
            write_inputs(accounts, transactions)
            if os.path.lexists("/home/user/top_accounts.csv"):
                os.unlink("/home/user/top_accounts.csv")

            env = os.environ.copy()
            env["LD_PRELOAD"] = "/tmp/sqlite_trace.so"
            env["SQLITE_TRACE_LOG"] = trace_path
            result = subprocess.run(
                ["/home/user/analyze"], cwd="/home/user", env=env,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15
            )
            assert result.returncode == 0, (
                f"analyze exited with {result.returncode}. stderr: {result.stderr}"
            )
            assert os.path.isfile("/home/user/top_accounts.csv"), "analyze did not generate top_accounts.csv"
            with open("/home/user/top_accounts.csv", "r") as f:
                lines = [line.strip() for line in f if line.strip()]
            assert len(lines) == 3, f"Expected exactly 3 output lines, got {lines!r}"
            assert all(re.fullmatch(r"[0-9]+,[0-9]+", line) for line in lines), \
                f"Output is not in account_id,out_degree format: {lines!r}"
            assert lines == expected, f"Expected recomputed output {expected!r}, got {lines!r}"

        assert os.path.isfile(trace_path), "No SQLite C API activity was observed"
        trace_lines = open(trace_path, "r", errors="replace").read().lower().splitlines()
        assert any(":memory:" in line for line in trace_lines if line.startswith("open")), \
            "The program did not open an in-memory SQLite database"
        query_lines = [line for line in trace_lines if "select" in line]
        assert any(
            line.count("join") >= 2 and "amount" in line and
            line.count("status") >= 2 and ">" in line
            for line in query_lines
        ), "No executed SQL query was observed joining both account endpoints and filtering amount/status"
    finally:
        for path, data in backups.items():
            if data is None:
                if os.path.lexists(path):
                    os.unlink(path)
            else:
                with open(path, "wb") as f:
                    f.write(data)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

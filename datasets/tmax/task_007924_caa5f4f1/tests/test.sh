#!/bin/bash
set -e
mkdir -p /logs/verifier
trap 'echo "0" > /logs/verifier/reward.txt' ERR

cat << 'LOGGER_EOF' > /tmp/sql_logger.c
#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static void log_sql(const char *sql) {
    const char *path = getenv("SQL_LOG_PATH");
    if (!path || !sql) return;
    FILE *f = fopen(path, "a");
    if (!f) return;
    fprintf(f, "%ld\t", (long)getpid());
    fputs(sql, f);
    fputs("\n--END--\n", f);
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

int sqlite3_exec(sqlite3 *db, const char *sql, int (*callback)(void *, int, char **, char **), void *arg, char **errmsg) {
    static int (*real_fn)(sqlite3 *, const char *, int (*)(void *, int, char **, char **), void *, char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_exec");
    log_sql(sql);
    return real_fn(db, sql, callback, arg, errmsg);
}
LOGGER_EOF

gcc -shared -fPIC /tmp/sql_logger.c -o /tmp/sql_logger.so -ldl

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import shutil
import sqlite3
import subprocess

C_FILE = "/home/user/analyze.c"
EXE_FILE = "/home/user/analyze"
DB_FILE = "/home/user/experiments.db"
CSV_FILE = "/home/user/results.csv"
VERIFIED_EXE = "/tmp/verified_analyze"
SQL_LOG = "/tmp/analyze_sql.log"
LOGGER = "/tmp/sql_logger.so"


def run_program(path, log_sql=False):
    if os.path.exists(CSV_FILE):
        os.remove(CSV_FILE)
    env = os.environ.copy()
    if log_sql:
        if os.path.exists(SQL_LOG):
            os.remove(SQL_LOG)
        env["LD_PRELOAD"] = LOGGER
        env["SQL_LOG_PATH"] = SQL_LOG
    result = subprocess.run(
        [path], cwd="/home/user", env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE,
        text=True, timeout=15
    )
    assert result.returncode == 0, (
        f"{path} exited with {result.returncode}; "
        f"stdout={result.stdout!r}, stderr={result.stderr!r}"
    )
    assert os.path.isfile(CSV_FILE), f"Program did not create {CSV_FILE}"
    return result


def assert_required_query_was_executed(pid):
    assert os.path.isfile(SQL_LOG), "No SQLite statements were observed while running the program"
    text = open(SQL_LOG, "r", encoding="utf-8", errors="replace").read()
    statements = []
    for record in text.split("\n--END--\n"):
        if "\t" not in record:
            continue
        pid_text, sql = record.split("\t", 1)
        if pid_text.strip() == str(pid):
            statements.append(sql)

    assert statements, "The compiled C program did not execute a statement through the SQLite3 C API"
    normalized = [re.sub(r"\s+", " ", sql.lower()) for sql in statements]
    matching = [sql for sql in normalized if
                re.search(r"json_extract\s*\(", sql) and
                re.search(r"dense_rank\s*\(\s*\)", sql) and
                re.search(r"\bover\b", sql) and
                re.search(r"\bpartition\s+by\b", sql)]
    assert matching, (
        "No executed SQLite query used JSON extraction together with "
        "DENSE_RANK() OVER and PARTITION BY"
    )


def read_csv_rows():
    assert os.path.isfile(CSV_FILE), f"Results CSV missing at {CSV_FILE}"
    with open(CSV_FILE, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]
    rows = []
    for i, line in enumerate(lines, 1):
        parts = line.split(',')
        assert len(parts) == 4, f"Line {i} is malformed: {line}"
        try:
            rows.append((parts[0], int(parts[1]), float(parts[2]), int(parts[3])))
        except ValueError as exc:
            raise AssertionError(f"Line {i} contains an invalid numeric field: {line}") from exc
    return rows


def test_01_c_source_exists():
    """Test that the C source code file exists."""
    assert os.path.isfile(C_FILE), f"C source file missing at {C_FILE}"


def test_02_executable_exists_and_executable():
    """Test that the compiled executable exists and is executable."""
    assert os.path.isfile(EXE_FILE), f"Executable missing at {EXE_FILE}"
    assert os.access(EXE_FILE, os.X_OK), f"File at {EXE_FILE} is not executable"
    with open(EXE_FILE, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"File at {EXE_FILE} is not a compiled executable"


def test_03_execute_submitted_program():
    """Run the submitted executable instead of trusting a pre-existing CSV."""
    run_program(EXE_FILE)


def test_04_results_csv_content():
    """Test that the results.csv file exists and contains the correct data."""
    csv_file = CSV_FILE
    assert os.path.isfile(csv_file), f"Results CSV missing at {csv_file}"

    expected_lines = [
        "Control,105,15.2,1",
        "Control,100,10.5,2",
        "Control,110,10.5,2",
        "Treatment,101,22.1,1",
        "Treatment,102,22.1,1",
        "Treatment,103,18.4,2"
    ]

    with open(csv_file, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in CSV, found {len(actual_lines)}"

    for i, (expected, actual) in enumerate(zip(expected_lines, actual_lines)):
        exp_parts = expected.split(',')
        act_parts = actual.split(',')

        assert len(exp_parts) == 4 and len(act_parts) == 4, f"Line {i+1} is malformed: {actual}"
        assert act_parts[0] == exp_parts[0], f"Line {i+1} group mismatch: expected {exp_parts[0]}, got {act_parts[0]}"
        assert act_parts[1] == exp_parts[1], f"Line {i+1} timestamp mismatch: expected {exp_parts[1]}, got {act_parts[1]}"
        assert abs(float(act_parts[2]) - float(exp_parts[2])) < 1e-6, f"Line {i+1} primary_metric mismatch: expected {exp_parts[2]}, got {act_parts[2]}"
        assert act_parts[3] == exp_parts[3], f"Line {i+1} rank mismatch: expected {exp_parts[3]}, got {act_parts[3]}"


def test_05_compile_source_and_exercise_on_unseen_database():
    compile_result = subprocess.run(
        ["gcc", C_FILE, "-o", VERIFIED_EXE, "-lsqlite3"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert compile_result.returncode == 0, (
        f"analyze.c did not compile with gcc and sqlite3: {compile_result.stderr}"
    )

    nonce = secrets.token_hex(4)
    groups = [f"Alpha_{nonce}", f"Beta_{nonce}", f"Gamma_{nonce}"]
    records = [
        (groups[0], 910, 7.25),
        (groups[0], 905, 12.5),
        (groups[0], 920, 7.25),
        (groups[0], 900, -1.75),
        (groups[1], 444, 3.125),
        (groups[1], 111, 20.0),
        (groups[1], 333, 20.0),
        (groups[1], 222, 9.5),
        (groups[2], 72, 0.5),
        (groups[2], 71, 0.5),
        (groups[2], 70, 100.75),
    ]
    insertion_order = [6, 2, 9, 0, 10, 3, 5, 8, 1, 7, 4]

    with open(DB_FILE, "rb") as f:
        original_db = f.read()

    try:
        os.remove(DB_FILE)
        conn = sqlite3.connect(DB_FILE)
        conn.execute("CREATE TABLE raw_records (document TEXT)")
        for idx in insertion_order:
            group, timestamp, metric = records[idx]
            document = {
                "experiment_id": f"dynamic-{idx}-{nonce}",
                "metadata": {"group": group, "timestamp": timestamp},
                "results": {"primary_metric": metric},
                "irrelevant": {"value": idx}
            }
            conn.execute("INSERT INTO raw_records(document) VALUES (?)", (json.dumps(document),))
        conn.commit()
        conn.close()

        result = run_program(VERIFIED_EXE, log_sql=True)
        assert_required_query_was_executed(result.pid)
        actual = read_csv_rows()

        expected = []
        for group in sorted(groups):
            group_records = [(ts, metric) for g, ts, metric in records if g == group]
            distinct_metrics = sorted({metric for ts, metric in group_records}, reverse=True)
            ranks = {metric: rank + 1 for rank, metric in enumerate(distinct_metrics)}
            for timestamp, metric in sorted(group_records, key=lambda item: (ranks[item[1]], item[0])):
                expected.append((group, timestamp, metric, ranks[metric]))

        assert len(actual) == len(expected), f"Expected {len(expected)} dynamic rows, found {len(actual)}"
        for i, (got, want) in enumerate(zip(actual, expected), 1):
            assert got[0] == want[0], f"Dynamic row {i} group mismatch: expected {want[0]}, got {got[0]}"
            assert got[1] == want[1], f"Dynamic row {i} timestamp mismatch: expected {want[1]}, got {got[1]}"
            assert abs(got[2] - want[2]) < 1e-9, f"Dynamic row {i} metric mismatch: expected {want[2]}, got {got[2]}"
            assert got[3] == want[3], f"Dynamic row {i} rank mismatch: expected {want[3]}, got {got[3]}"
    finally:
        with open(DB_FILE, "wb") as f:
            f.write(original_db)
        os.chmod(DB_FILE, 0o644)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
trap - ERR

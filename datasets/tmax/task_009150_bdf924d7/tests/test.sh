#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TRACE_EOF' > /tmp/sqlite_trace.c
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <sqlite3.h>

static void log_sql(const char *sql) {
    const char *path = getenv("TRACE_SQL");
    if (!path || !sql) return;
    FILE *f = fopen(path, "a");
    if (!f) return;
    fputs(sql, f);
    fputs("\n--TRACE-END--\n", f);
    fclose(f);
}

int sqlite3_prepare(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare");
    log_sql(sql);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    log_sql(sql);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v3(sqlite3 *db, const char *sql, int n, unsigned int flags, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, unsigned int, sqlite3_stmt **, const char **);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v3");
    log_sql(sql);
    return real_fn(db, sql, n, flags, stmt, tail);
}

int sqlite3_exec(sqlite3 *db, const char *sql, int (*cb)(void *, int, char **, char **), void *arg, char **errmsg) {
    static int (*real_fn)(sqlite3 *, const char *, int (*)(void *, int, char **, char **), void *, char **);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_exec");
    log_sql(sql);
    return real_fn(db, sql, cb, arg, errmsg);
}

int sqlite3_get_table(sqlite3 *db, const char *sql, char ***result, int *rows, int *cols, char **errmsg) {
    static int (*real_fn)(sqlite3 *, const char *, char ***, int *, int *, char **);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_get_table");
    log_sql(sql);
    return real_fn(db, sql, result, rows, cols, errmsg);
}
TRACE_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import sqlite3
import subprocess
import uuid
import pytest

CPP_PATH = "/home/user/audit_processor.cpp"
EXE_PATH = "/home/user/audit_processor"
CYPHER_PATH = "/home/user/flag_queries.cypher"
DB_PATH = "/home/user/audit.db"
TRACE_LIB = "/tmp/libsqlite_trace.so"
TRACE_PATH = "/tmp/sql_trace.log"


def expected_lines_for_db():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    query = """
    SELECT DISTINCT user_id
    FROM (
        SELECT user_id,
               COUNT(*) OVER (
                   PARTITION BY user_id
                   ORDER BY access_time
                   RANGE BETWEEN 600 PRECEDING AND CURRENT ROW
               ) as window_count
        FROM access_logs
    )
    WHERE window_count > 5
    ORDER BY user_id;
    """
    try:
        cursor.execute(query)
        flagged_users = [row[0] for row in cursor.fetchall()]
    except sqlite3.Error as e:
        pytest.fail(f"Failed to execute verification query on database: {e}")
    finally:
        conn.close()
    return [
        f"MATCH (u:User {{id: '{uid}'}}) SET u.compliance_risk = true;"
        for uid in flagged_users
    ]


def assert_window_query_was_executed():
    assert os.path.isfile(TRACE_PATH), "The program did not execute a traced SQLite3 query."
    with open(TRACE_PATH, "r", errors="replace") as f:
        trace = re.sub(r"\s+", " ", f.read().upper())
    assert re.search(r"\bCOUNT\s*\(", trace), "No SQL COUNT window calculation was executed."
    assert re.search(r"\bOVER\s*\(", trace), "No SQL window function was executed."
    assert re.search(r"\bPARTITION\s+BY\b", trace), "The executed window query does not partition users."
    assert re.search(r"\bORDER\s+BY\b", trace), "The executed window query does not order access events."
    frame = (
        re.search(r"\bRANGE\s+BETWEEN\s+600\s+PRECEDING\s+AND\s+CURRENT\s+ROW\b", trace)
        or re.search(r"\bRANGE\s+600\s+PRECEDING\b", trace)
    )
    assert frame, "The executed SQL does not use the required inclusive 600-second RANGE frame."


def run_processor():
    if os.path.exists(TRACE_PATH):
        os.remove(TRACE_PATH)
    env = os.environ.copy()
    env["LD_PRELOAD"] = TRACE_LIB
    env["TRACE_SQL"] = TRACE_PATH
    result = subprocess.run([EXE_PATH], env=env, capture_output=True, text=True, timeout=15)
    assert result.returncode == 0, (
        f"The compiled processor failed with exit code {result.returncode}.\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    assert_window_query_was_executed()


def assert_output_matches_expected():
    assert os.path.exists(CYPHER_PATH), f"The output file {CYPHER_PATH} was not created."
    assert os.path.isfile(CYPHER_PATH), f"{CYPHER_PATH} is not a valid file."
    expected_lines = expected_lines_for_db()
    with open(CYPHER_PATH, "r") as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]
    assert actual_lines == expected_lines, (
        f"The contents of {CYPHER_PATH} do not match the expected output.\n"
        f"Expected: {expected_lines}\nGot: {actual_lines}"
    )


def create_database(rows):
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute("CREATE TABLE access_logs(user_id TEXT, resource_id TEXT, access_time INTEGER)")
        conn.executemany("INSERT INTO access_logs VALUES (?, ?, ?)", rows)
        conn.commit()
    finally:
        conn.close()


def test_cpp_file_exists():
    assert os.path.exists(CPP_PATH), f"The C++ source file {CPP_PATH} is missing."
    assert os.path.isfile(CPP_PATH), f"{CPP_PATH} is not a valid file."


def test_compile_and_run_cpp_processor():
    trace_build = subprocess.run(
        ["gcc", "-shared", "-fPIC", "/tmp/sqlite_trace.c", "-ldl", "-o", TRACE_LIB],
        capture_output=True, text=True
    )
    assert trace_build.returncode == 0, f"Failed to build verifier tracing library: {trace_build.stderr}"

    build = subprocess.run(
        ["g++", "-O2", CPP_PATH, "-lsqlite3", "-o", EXE_PATH],
        capture_output=True, text=True
    )
    assert build.returncode == 0, (
        f"The required C++ source did not compile with the specified command.\n{build.stderr}"
    )
    assert os.path.isfile(EXE_PATH) and os.access(EXE_PATH, os.X_OK)


def test_cypher_queries_output():
    assert os.path.isfile(DB_PATH), f"The database {DB_PATH} is missing."
    run_processor()
    assert_output_matches_expected()


def test_processor_on_fresh_unpredictable_databases():
    backup = "/tmp/audit.db.verifier-backup"
    shutil.copy2(DB_PATH, backup)
    token = uuid.uuid4().hex
    try:
        a = "A_" + token
        b = "B_" + token
        c = "C_" + token
        d = "D_" + token
        rows1 = []
        rows1 += [(a, f"R{i}", t) for i, t in enumerate([1000, 1120, 1240, 1360, 1480, 1600])]
        rows1 += [(b, f"R{i}", t) for i, t in enumerate([2000, 2120, 2240, 2360, 2480, 2601])]
        rows1 += [(c, f"R{i}", 4000) for i in range(6)]
        rows1 += [(d, f"R{i}", t) for i, t in enumerate([5000, 5100, 5200, 5300, 5400])]
        create_database(rows1)
        run_processor()
        assert_output_matches_expected()

        e = "E_" + token
        f = "F_" + token
        g = "G_" + token
        rows2 = []
        rows2 += [(e, f"X{i}", t) for i, t in enumerate([10, 100, 200, 300, 400, 610, 611])]
        rows2 += [(f, f"X{i}", t) for i, t in enumerate([1000, 1300, 1600, 1601, 1900, 2201])]
        rows2 += [(g, f"X{i}", t) for i, t in enumerate([7000, 7100, 7200, 7300, 7400, 7500])]
        create_database(rows2)
        run_processor()
        assert_output_matches_expected()
    finally:
        shutil.copy2(backup, DB_PATH)
        if os.path.isfile(EXE_PATH):
            run_processor()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

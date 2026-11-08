#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import shutil
import sqlite3
import subprocess
import tempfile
import uuid

DB_PATH = "/home/user/audit.db"
CPP_PATH = "/home/user/audit_checker.cpp"
EXE_PATH = "/home/user/audit_checker"
CSV_PATH = "/home/user/unauthorized_report.csv"
HEADER = ["user_name", "server_name", "unauthorized_attempts", "rank_overall"]

EXPECTED_QUERY = """
WITH valid_access AS (
    SELECT source_id AS user_id, target_id AS server_id
    FROM relationships WHERE rel_type = 'HAS_ACCESS'
    UNION
    SELECT r1.source_id, r2.target_id
    FROM relationships r1
    JOIN relationships r2 ON r1.target_id = r2.source_id
    WHERE r1.rel_type = 'MEMBER_OF' AND r2.rel_type = 'HAS_ACCESS'
), unauthorized_events AS (
    SELECT ae.user_id, ae.server_id
    FROM access_events ae
    JOIN entities s ON ae.server_id = s.id
    WHERE s.is_sensitive = 1
      AND NOT EXISTS (
          SELECT 1 FROM valid_access va
          WHERE va.user_id = ae.user_id AND va.server_id = ae.server_id
      )
), user_totals AS (
    SELECT user_id, COUNT(*) AS total_unauth
    FROM unauthorized_events GROUP BY user_id
), ranked_users AS (
    SELECT user_id,
           DENSE_RANK() OVER (ORDER BY total_unauth DESC) AS rank_overall
    FROM user_totals
), grouped_events AS (
    SELECT user_id, server_id, COUNT(*) AS unauthorized_attempts
    FROM unauthorized_events GROUP BY user_id, server_id
)
SELECT u.name AS user_name, s.name AS server_name,
       ge.unauthorized_attempts, ru.rank_overall
FROM grouped_events ge
JOIN entities u ON ge.user_id = u.id
JOIN entities s ON ge.server_id = s.id
JOIN ranked_users ru ON ge.user_id = ru.user_id
"""

HOOK_SOURCE = r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>

static void log_sql(const char *sql) {
    const char *path = getenv("AUDIT_SQL_TRACE");
    if (!path || !sql) return;
    FILE *f = fopen(path, "a");
    if (!f) return;
    fputs(sql, f);
    fputs("\n--END-SQL--\n", f);
    fclose(f);
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt,
                       const char **tail) {
    typedef int (*fn_t)(sqlite3*, const char*, int, sqlite3_stmt**, const char**);
    static fn_t real_fn;
    if (!real_fn) real_fn = (fn_t)dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    log_sql(sql);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v3(sqlite3 *db, const char *sql, int n, unsigned int flags,
                       sqlite3_stmt **stmt, const char **tail) {
    typedef int (*fn_t)(sqlite3*, const char*, int, unsigned int, sqlite3_stmt**, const char**);
    static fn_t real_fn;
    if (!real_fn) real_fn = (fn_t)dlsym(RTLD_NEXT, "sqlite3_prepare_v3");
    log_sql(sql);
    return real_fn(db, sql, n, flags, stmt, tail);
}

int sqlite3_prepare(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt,
                    const char **tail) {
    typedef int (*fn_t)(sqlite3*, const char*, int, sqlite3_stmt**, const char**);
    static fn_t real_fn;
    if (!real_fn) real_fn = (fn_t)dlsym(RTLD_NEXT, "sqlite3_prepare");
    log_sql(sql);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_exec(sqlite3 *db, const char *sql,
                 int (*callback)(void*,int,char**,char**), void *arg, char **errmsg) {
    typedef int (*fn_t)(sqlite3*, const char*, int (*)(void*,int,char**,char**), void*, char**);
    static fn_t real_fn;
    if (!real_fn) real_fn = (fn_t)dlsym(RTLD_NEXT, "sqlite3_exec");
    log_sql(sql);
    return real_fn(db, sql, callback, arg, errmsg);
}

int sqlite3_get_table(sqlite3 *db, const char *sql, char ***result, int *rows,
                      int *cols, char **errmsg) {
    typedef int (*fn_t)(sqlite3*, const char*, char***, int*, int*, char**);
    static fn_t real_fn;
    if (!real_fn) real_fn = (fn_t)dlsym(RTLD_NEXT, "sqlite3_get_table");
    log_sql(sql);
    return real_fn(db, sql, result, rows, cols, errmsg);
}
'''

def expected_results():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        rows = conn.execute(EXPECTED_QUERY).fetchall()
        return sorted([{
            "user_name": row["user_name"],
            "server_name": row["server_name"],
            "unauthorized_attempts": str(row["unauthorized_attempts"]),
            "rank_overall": str(row["rank_overall"]),
        } for row in rows], key=lambda r: (r["user_name"], r["server_name"]))
    finally:
        conn.close()

def read_report():
    assert os.path.exists(CSV_PATH), f"Output CSV missing at {CSV_PATH}"
    with open(CSV_PATH, newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header is not None, "CSV file is empty"
        assert [x.strip() for x in header] == HEADER, \
            f"CSV header {header} does not match expected {HEADER}"
        rows = []
        for row in reader:
            if not row:
                continue
            assert len(row) == 4, f"Row {row} does not have exactly 4 columns"
            rows.append({
                "user_name": row[0].strip(),
                "server_name": row[1].strip(),
                "unauthorized_attempts": row[2].strip(),
                "rank_overall": row[3].strip(),
            })
    return sorted(rows, key=lambda r: (r["user_name"], r["server_name"]))

def assert_report_matches():
    actual = read_report()
    expected = expected_results()
    assert len(actual) == len(expected), \
        f"Expected {len(expected)} rows, found {len(actual)}"
    for got, want in zip(actual, expected):
        assert got == want, f"Row mismatch: expected {want}, got {got}"

def run_program(path, hook, trace):
    if os.path.exists(CSV_PATH):
        os.unlink(CSV_PATH)
    if os.path.exists(trace):
        os.unlink(trace)
    env = os.environ.copy()
    env["LD_PRELOAD"] = hook
    env["AUDIT_SQL_TRACE"] = trace
    result = subprocess.run([path], cwd="/home/user", env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, timeout=20)
    assert result.returncode == 0, \
        f"{path} failed with code {result.returncode}: {result.stderr}"
    assert_report_matches()
    assert os.path.exists(trace), "Program did not execute SQL through the SQLite C API"
    trace_text = open(trace, errors="replace").read()
    statements = trace_text.split("--END-SQL--")
    assert any(re.search(r"dense_rank\s*\(", sql, re.I) and
               all(name in sql.lower() for name in
                   ("access_events", "relationships", "entities"))
               for sql in statements), \
        "No executed SQLite query used DENSE_RANK() with the audit graph tables"

def create_fixture():
    for suffix in ("", "-wal", "-shm"):
        try:
            os.unlink(DB_PATH + suffix)
        except FileNotFoundError:
            pass
    tag = uuid.uuid4().hex[:10]
    names = {
        "a": "Analyst_" + tag, "b": "Builder_" + tag,
        "c": "Clerk_" + tag, "d": "Director_" + tag,
        "e": "Engineer_" + tag, "g1": "GroupOne_" + tag,
        "g2": "GroupTwo_" + tag, "s1": "Vault_" + tag,
        "s2": "Payroll_" + tag, "s3": "Secrets_" + tag,
        "ns": "Public_" + tag,
    }
    conn = sqlite3.connect(DB_PATH)
    conn.executescript("""
        CREATE TABLE entities (id INTEGER PRIMARY KEY, name TEXT, type TEXT, is_sensitive INTEGER);
        CREATE TABLE relationships (source_id INTEGER, target_id INTEGER, rel_type TEXT);
        CREATE TABLE access_events (event_id INTEGER PRIMARY KEY, user_id INTEGER, server_id INTEGER, timestamp DATETIME);
    """)
    conn.executemany("INSERT INTO entities VALUES (?,?,?,?)", [
        (1,names["a"],"USER",0),(2,names["b"],"USER",0),
        (3,names["c"],"USER",0),(4,names["d"],"USER",0),
        (5,names["e"],"USER",0),(10,names["g1"],"GROUP",0),
        (11,names["g2"],"GROUP",0),(20,names["s1"],"SERVER",1),
        (21,names["s2"],"SERVER",1),(22,names["s3"],"SERVER",1),
        (23,names["ns"],"SERVER",0),
    ])
    conn.executemany("INSERT INTO relationships VALUES (?,?,?)", [
        (2,10,"MEMBER_OF"),(10,20,"HAS_ACCESS"),
        (4,21,"HAS_ACCESS"),(1,11,"MEMBER_OF"),(11,23,"HAS_ACCESS"),
    ])
    events = []
    def add(user, server, count):
        for i in range(count):
            events.append((user, server, f"2026-01-{(i % 9)+1:02d} 12:00:00"))
    add(1,20,4); add(1,21,1)
    add(3,21,3)
    add(5,20,1); add(5,22,2)
    add(2,21,2)
    add(2,20,2); add(4,21,2)
    add(3,23,7)
    conn.executemany("INSERT INTO access_events(user_id,server_id,timestamp) VALUES (?,?,?)", events)
    conn.commit()
    conn.close()
    os.chmod(DB_PATH, 0o777)

def test_complete_solution():
    assert os.path.exists(CPP_PATH), f"C++ source file missing at {CPP_PATH}"
    assert os.path.exists(EXE_PATH), f"Compiled executable missing at {EXE_PATH}"
    assert os.access(EXE_PATH, os.X_OK), f"Executable at {EXE_PATH} is not executable"
    assert os.path.exists(CSV_PATH), f"Output CSV missing at {CSV_PATH}"
    with open(EXE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "audit_checker is not a compiled executable"

    source = open(CPP_PATH, errors="replace").read()
    assert re.search(r"#\s*include\s*[<\"]sqlite3\.h[>\"]", source), \
        "Source does not include the SQLite C API header"
    assert re.search(r"DENSE_RANK\s*\(", source, re.I), \
        "Source does not contain the required DENSE_RANK() window function"

    tempdir = tempfile.mkdtemp(prefix="audit_verify_")
    backup_db = os.path.join(tempdir, "audit.db")
    backup_csv = os.path.join(tempdir, "report.csv")
    had_csv = os.path.exists(CSV_PATH)
    shutil.copy2(DB_PATH, backup_db)
    if had_csv:
        shutil.copy2(CSV_PATH, backup_csv)

    hook_c = os.path.join(tempdir, "trace.c")
    hook_so = os.path.join(tempdir, "trace.so")
    verified_exe = os.path.join(tempdir, "audit_checker")
    with open(hook_c, "w") as f:
        f.write(HOOK_SOURCE)
    subprocess.run(["gcc", "-shared", "-fPIC", hook_c, "-ldl", "-o", hook_so],
                   check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    compile_result = subprocess.run(
        ["g++", "-std=c++17", CPP_PATH, "-lsqlite3", "-o", verified_exe],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)
    assert compile_result.returncode == 0, \
        f"C++ source does not compile as required: {compile_result.stderr}"

    try:
        # Execute the submitted artifact against the original database.
        run_program(EXE_PATH, hook_so, os.path.join(tempdir, "original.trace"))

        # Replace the database with an unpredictable fixture, then exercise both
        # the submitted executable and a fresh build of the submitted source.
        create_fixture()
        run_program(EXE_PATH, hook_so, os.path.join(tempdir, "submitted.trace"))
        run_program(verified_exe, hook_so, os.path.join(tempdir, "rebuilt.trace"))
    finally:
        for suffix in ("", "-wal", "-shm"):
            try:
                os.unlink(DB_PATH + suffix)
            except FileNotFoundError:
                pass
        shutil.copy2(backup_db, DB_PATH)
        os.chmod(DB_PATH, 0o777)
        if had_csv:
            shutil.copy2(backup_csv, CSV_PATH)
        else:
            try:
                os.unlink(CSV_PATH)
            except FileNotFoundError:
                pass
        shutil.rmtree(tempdir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

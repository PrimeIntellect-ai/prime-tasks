#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import sqlite3
import subprocess
import tempfile
import pytest

SOURCE = "/home/user/graph_projector.c"
EXE = "/home/user/graph_projector"
DB = "/home/user/corp.db"
CSV = "/home/user/top_connections.csv"
BUILT_EXE = "/tmp/graph_projector_from_source"
TRACE_SO = "/tmp/libsqlite_trace.so"
TRACE_LOG = "/tmp/sql_trace.log"


def run(cmd, **kwargs):
    try:
        return subprocess.run(cmd, timeout=10, **kwargs)
    except subprocess.TimeoutExpired:
        pytest.fail(f"Command timed out: {cmd}")


def test_01_c_source_exists_and_uses_sqlite_api():
    assert os.path.isfile(SOURCE), "C source file /home/user/graph_projector.c not found."
    source = open(SOURCE, "r", encoding="utf-8", errors="replace").read()
    assert re.search(r"#\s*include\s*[<\"]sqlite3\.h[>\"]", source), "Source does not include sqlite3.h."
    assert re.search(r"\bsqlite3_(open|open_v2)\s*\(", source), "Source does not open the database with the SQLite3 C API."
    assert re.search(r"\bsqlite3_(prepare|prepare_v2|prepare_v3|exec|get_table)\s*\(", source), "Source does not execute SQL with the SQLite3 C API."


def test_02_executable_exists_and_runs_on_original_database():
    assert os.path.isfile(EXE), f"Executable {EXE} not found. Did you compile the C program?"
    assert os.access(EXE, os.X_OK), f"File {EXE} is not executable."
    with open(EXE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "graph_projector must be a compiled executable, not a script."

    if os.path.exists(CSV):
        os.remove(CSV)
    result = run([EXE], capture_output=True, text=True)
    assert result.returncode == 0, f"Executable failed with return code {result.returncode}.\nStderr: {result.stderr}\nStdout: {result.stdout}"

    assert os.path.isfile(CSV), f"Output file {CSV} was not created by the executable."
    content = open(CSV, "r", encoding="utf-8").read().strip()
    expected = (
        "Engineering,Marketing,250\n"
        "HR,Engineering,400\n"
        "Marketing,HR,300\n"
        "Sales,Marketing,600"
    )
    content_lines = [line.strip() for line in content.splitlines() if line.strip()]
    expected_lines = [line.strip() for line in expected.splitlines() if line.strip()]
    assert content_lines == expected_lines, f"CSV output did not match expected.\nGot:\n{content}\n\nExpected:\n{expected}"


def build_submitted_source_and_trace_library():
    result = run(["gcc", SOURCE, "-o", BUILT_EXE, "-lsqlite3"], capture_output=True, text=True)
    assert result.returncode == 0, f"Submitted C source did not compile with SQLite3.\n{result.stderr}"

    trace_c = r'''
#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

static void record_sql(const char *sql, int n) {
    if (!sql) return;
    FILE *f = fopen("/tmp/sql_trace.log", "a");
    if (!f) return;
    if (n < 0) n = (int)strlen(sql);
    fwrite(sql, 1, (size_t)n, f);
    fputs("\n--SQL-END--\n", f);
    fclose(f);
}

int sqlite3_prepare(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3*, const char*, int, sqlite3_stmt**, const char**) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare");
    record_sql(sql, n);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3*, const char*, int, sqlite3_stmt**, const char**) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    record_sql(sql, n);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v3(sqlite3 *db, const char *sql, int n, unsigned int flags, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3*, const char*, int, unsigned int, sqlite3_stmt**, const char**) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v3");
    record_sql(sql, n);
    return real_fn(db, sql, n, flags, stmt, tail);
}

int sqlite3_exec(sqlite3 *db, const char *sql, int (*cb)(void*,int,char**,char**), void *arg, char **err) {
    static int (*real_fn)(sqlite3*, const char*, int (*)(void*,int,char**,char**), void*, char**) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_exec");
    record_sql(sql, -1);
    return real_fn(db, sql, cb, arg, err);
}

int sqlite3_get_table(sqlite3 *db, const char *sql, char ***result, int *rows, int *cols, char **err) {
    static int (*real_fn)(sqlite3*, const char*, char***, int*, int*, char**) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_get_table");
    record_sql(sql, -1);
    return real_fn(db, sql, result, rows, cols, err);
}
'''
    with open("/tmp/sqlite_trace.c", "w") as f:
        f.write(trace_c)
    result = run(["gcc", "-shared", "-fPIC", "/tmp/sqlite_trace.c", "-o", TRACE_SO, "-ldl"], capture_output=True, text=True)
    assert result.returncode == 0, f"Could not build SQL tracing helper.\n{result.stderr}"


def install_database(employees, communications):
    if os.path.exists(DB):
        os.remove(DB)
    con = sqlite3.connect(DB)
    try:
        con.execute("CREATE TABLE employees (emp_id INTEGER PRIMARY KEY, name TEXT, department TEXT)")
        con.execute("CREATE TABLE communications (sender_id INTEGER, receiver_id INTEGER, message_count INTEGER)")
        con.executemany("INSERT INTO employees VALUES (?, ?, ?)", employees)
        con.executemany("INSERT INTO communications VALUES (?, ?, ?)", communications)
        con.commit()
    finally:
        con.close()
    os.chmod(DB, 0o777)


def derive_expected(employees, communications):
    departments = {emp_id: department for emp_id, _name, department in employees}
    totals = {}
    for sender, receiver, count in communications:
        if sender not in departments or receiver not in departments:
            continue
        sender_department = departments[sender]
        receiver_department = departments[receiver]
        if sender_department == receiver_department:
            continue
        key = (sender_department, receiver_department)
        totals[key] = totals.get(key, 0) + count

    grouped = {}
    for (sender_department, receiver_department), total in totals.items():
        grouped.setdefault(sender_department, []).append((receiver_department, total))

    lines = []
    for sender_department in sorted(grouped):
        choices = grouped[sender_department]
        highest = max(total for _receiver, total in choices)
        winners = [(receiver, total) for receiver, total in choices if total == highest]
        assert len(winners) == 1, "Verifier fixture unexpectedly contains a tie."
        receiver, total = winners[0]
        lines.append(f"{sender_department},{receiver},{total}")
    return lines


def exercise(executable, expected):
    if os.path.exists(CSV):
        os.remove(CSV)
    if os.path.exists(TRACE_LOG):
        os.remove(TRACE_LOG)
    env = os.environ.copy()
    env["LD_PRELOAD"] = TRACE_SO
    result = run([executable], capture_output=True, text=True, env=env)
    assert result.returncode == 0, f"{executable} failed on a verification database.\nStderr: {result.stderr}\nStdout: {result.stdout}"
    assert os.path.isfile(CSV), f"{executable} did not create {CSV}."
    content = open(CSV, "r", encoding="utf-8").read().strip()
    actual = [line.strip() for line in content.splitlines() if line.strip()]
    assert actual == expected, f"{executable} produced incorrect output for a verification database.\nGot: {actual}\nExpected: {expected}"

    assert os.path.isfile(TRACE_LOG), f"{executable} did not execute SQL through the SQLite3 API."
    sql = open(TRACE_LOG, "r", encoding="utf-8", errors="replace").read().upper()
    assert "EMPLOYEES" in sql and "COMMUNICATIONS" in sql, "Executed SQL does not query both required tables."
    assert re.search(r"\bSUM\s*\(", sql), "Executed SQL does not aggregate message_count with SUM."
    assert re.search(r"\b(ROW_NUMBER|RANK|DENSE_RANK)\s*\(\s*\)\s*OVER\b", sql), "Executed SQL does not use a ranking window function."


def test_03_recompiled_source_and_executable_handle_unseen_databases():
    build_submitted_source_and_trace_library()
    backup = tempfile.mktemp(prefix="corp_backup_", suffix=".db")
    shutil.copy2(DB, backup)
    fixtures = [
        (
            [(1,"a1","Alpha"),(2,"a2","Alpha"),(3,"b","Beta"),(4,"c","Gamma"),(5,"d","Delta")],
            [(1,3,7),(2,3,4),(1,4,10),(1,2,999),(3,1,2),(3,5,20),(4,1,8),(4,3,9),(5,4,3),(999,1,500)]
        ),
        (
            [(11,"u","North"),(12,"v","South"),(13,"w","East"),(14,"x","West"),(15,"y","South"),(16,"z","North")],
            [(11,12,31),(16,15,12),(11,13,70),(12,11,5),(15,16,9),(12,14,60),(13,11,44),(13,14,2),(14,13,80),(14,12,79),(11,16,1000)]
        )
    ]
    try:
        for employees, communications in fixtures:
            install_database(employees, communications)
            expected = derive_expected(employees, communications)
            exercise(EXE, expected)
            exercise(BUILT_EXE, expected)
    finally:
        if os.path.exists(DB):
            os.remove(DB)
        shutil.copy2(backup, DB)
        os.remove(backup)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

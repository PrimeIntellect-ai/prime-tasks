#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import datetime
import os
import random
import re
import secrets
import shutil
import sqlite3
import subprocess


def test_c_file_exists_and_contains_requirements():
    c_file_path = "/home/user/audit_extractor.c"
    assert os.path.exists(c_file_path), f"C source file {c_file_path} does not exist."
    assert os.path.isfile(c_file_path), f"{c_file_path} is not a file."

    with open(c_file_path, "r", encoding="utf-8") as f:
        content = f.read().upper()

    assert "NOT INDEXED" in content, "The SQL query in the C program must use the 'NOT INDEXED' clause."
    assert "OVER" in content, "The SQL query in the C program must use a Window Function (e.g., OVER clause)."


def test_compliance_report_contents():
    csv_path = "/home/user/compliance_report.csv"
    assert os.path.exists(csv_path), f"Compliance report {csv_path} does not exist."
    assert os.path.isfile(csv_path), f"{csv_path} is not a file."

    expected_content = (
        "E001,2023-10-15 08:32:11\n"
        "E002,2023-10-14 19:12:05\n"
        "E004,2023-10-12 12:22:22"
    )

    with open(csv_path, "r", encoding="utf-8") as f:
        actual_content = f.read().strip().replace('\r', '')

    assert actual_content == expected_content, (
        f"Contents of {csv_path} do not match the expected output.\n"
        f"Expected:\n{expected_content}\n\nActual:\n{actual_content}"
    )


def _build_sqlite_trace_library():
    source = r'''
#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void record_text(const char *kind, const char *text) {
    const char *path = getenv("AUDIT_SQL_LOG");
    if (!path) return;
    FILE *f = fopen(path, "ab");
    if (!f) return;
    fprintf(f, "%ld|%s", (long)getpid(), kind);
    if (text) fwrite(text, 1, strlen(text), f);
    fputc('\0', f);
    fclose(f);
}

int sqlite3_open(const char *name, sqlite3 **db) {
    static int (*real_fn)(const char *, sqlite3 **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_open");
    record_text("OPEN:", name);
    return real_fn(name, db);
}

int sqlite3_open_v2(const char *name, sqlite3 **db, int flags, const char *vfs) {
    static int (*real_fn)(const char *, sqlite3 **, int, const char *) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_open_v2");
    record_text("OPEN:", name);
    return real_fn(name, db, flags, vfs);
}

int sqlite3_open16(const void *name, sqlite3 **db) {
    static int (*real_fn)(const void *, sqlite3 **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_open16");
    record_text("OPEN16:", NULL);
    return real_fn(name, db);
}

int sqlite3_prepare(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare");
    record_text("SQL:", sql);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    record_text("SQL:", sql);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v3(sqlite3 *db, const char *sql, int n, unsigned int flags, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, unsigned int, sqlite3_stmt **, const char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v3");
    record_text("SQL:", sql);
    return real_fn(db, sql, n, flags, stmt, tail);
}

int sqlite3_prepare16(sqlite3 *db, const void *sql, int n, sqlite3_stmt **stmt, const void **tail) {
    static int (*real_fn)(sqlite3 *, const void *, int, sqlite3_stmt **, const void **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare16");
    int rc = real_fn(db, sql, n, stmt, tail);
    record_text("SQL:", (stmt && *stmt) ? sqlite3_sql(*stmt) : NULL);
    return rc;
}

int sqlite3_prepare16_v2(sqlite3 *db, const void *sql, int n, sqlite3_stmt **stmt, const void **tail) {
    static int (*real_fn)(sqlite3 *, const void *, int, sqlite3_stmt **, const void **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare16_v2");
    int rc = real_fn(db, sql, n, stmt, tail);
    record_text("SQL:", (stmt && *stmt) ? sqlite3_sql(*stmt) : NULL);
    return rc;
}

int sqlite3_prepare16_v3(sqlite3 *db, const void *sql, int n, unsigned int flags, sqlite3_stmt **stmt, const void **tail) {
    static int (*real_fn)(sqlite3 *, const void *, int, unsigned int, sqlite3_stmt **, const void **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare16_v3");
    int rc = real_fn(db, sql, n, flags, stmt, tail);
    record_text("SQL:", (stmt && *stmt) ? sqlite3_sql(*stmt) : NULL);
    return rc;
}

int sqlite3_exec(sqlite3 *db, const char *sql, int (*cb)(void *, int, char **, char **), void *arg, char **err) {
    static int (*real_fn)(sqlite3 *, const char *, int (*)(void *, int, char **, char **), void *, char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_exec");
    record_text("SQL:", sql);
    return real_fn(db, sql, cb, arg, err);
}

int sqlite3_get_table(sqlite3 *db, const char *sql, char ***result, int *rows, int *cols, char **err) {
    static int (*real_fn)(sqlite3 *, const char *, char ***, int *, int *, char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_get_table");
    record_text("SQL:", sql);
    return real_fn(db, sql, result, rows, cols, err);
}
'''
    wrapper_c = "/tmp/sqlite_trace.c"
    wrapper_so = "/tmp/sqlite_trace.so"
    with open(wrapper_c, "w", encoding="utf-8") as f:
        f.write(source)
    subprocess.run(
        ["gcc", "-shared", "-fPIC", wrapper_c, "-o", wrapper_so, "-ldl", "-lsqlite3"],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    return wrapper_so


def _remove_sql_comments_and_literals(sql):
    sql = re.sub(r"/\*.*?\*/", " ", sql, flags=re.S)
    sql = re.sub(r"--[^\r\n]*", " ", sql)
    sql = re.sub(r"'(?:''|[^'])*'", "''", sql)
    return sql.upper()


def _make_random_database(path):
    conn = sqlite3.connect(path)
    conn.executescript("""
        CREATE TABLE system_access_logs(
            log_id INTEGER PRIMARY KEY,
            employee_id TEXT,
            action TEXT,
            event_time DATETIME
        );
        CREATE INDEX idx_stale_time ON system_access_logs(event_time);
    """)

    rng = random.SystemRandom()
    employee_numbers = rng.sample(range(100, 999), 8)
    employees = [f"E{number}" for number in employee_numbers]
    rows = []
    expected = {}
    base = datetime.datetime(2020, 1, 1)

    for index, employee in enumerate(employees):
        denied_count = 0 if index == len(employees) - 1 else rng.randint(1, 5)
        granted_count = rng.randint(1, 3)
        times = rng.sample(range(0, 180000000), denied_count + granted_count)
        for offset in times[:denied_count]:
            stamp = (base + datetime.timedelta(seconds=offset)).strftime("%Y-%m-%d %H:%M:%S")
            rows.append((employee, "DENIED", stamp))
            if employee not in expected or stamp > expected[employee]:
                expected[employee] = stamp
        for offset in times[denied_count:]:
            stamp = (base + datetime.timedelta(seconds=offset)).strftime("%Y-%m-%d %H:%M:%S")
            rows.append((employee, "GRANTED", stamp))

    rng.shuffle(rows)
    conn.executemany(
        "INSERT INTO system_access_logs(employee_id, action, event_time) VALUES (?, ?, ?)", rows
    )
    conn.commit()
    conn.close()
    return "\n".join(f"{employee},{expected[employee]}" for employee in sorted(expected))


def test_program_compiles_runs_and_uses_required_sqlite_query():
    source = "/home/user/audit_extractor.c"
    binary = "/tmp/audit_extractor_test"
    db_path = "/home/user/audit.db"
    report_path = "/home/user/compliance_report.csv"
    db_backup = "/tmp/audit.db.original"
    report_backup = "/tmp/compliance_report.original"

    subprocess.run(
        ["gcc", "-std=c11", "-O2", source, "-o", binary, "-lsqlite3"],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    wrapper_so = _build_sqlite_trace_library()

    shutil.copy2(db_path, db_backup)
    shutil.copy2(report_path, report_backup)
    try:
        for trial in range(2):
            if os.path.exists(db_path):
                os.remove(db_path)
            expected = _make_random_database(db_path)
            if os.path.exists(report_path):
                os.remove(report_path)

            trace_path = f"/tmp/audit_sql_trace_{trial}_{secrets.token_hex(8)}"
            env = os.environ.copy()
            env["LD_PRELOAD"] = wrapper_so
            env["AUDIT_SQL_LOG"] = trace_path
            proc = subprocess.Popen(
                [binary], cwd="/home/user", env=env,
                stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
            )
            try:
                stdout, stderr = proc.communicate(timeout=10)
            except subprocess.TimeoutExpired:
                proc.kill()
                proc.communicate()
                raise AssertionError("The compiled audit extractor did not finish within 10 seconds.")

            assert proc.returncode == 0, (
                f"The compiled audit extractor exited with status {proc.returncode}.\n"
                f"stdout:\n{stdout}\nstderr:\n{stderr}"
            )
            assert os.path.isfile(report_path), "Running the compiled C program did not create the report."
            with open(report_path, "r", encoding="utf-8") as f:
                actual = f.read().strip().replace("\r", "")
            assert actual == expected, (
                "The compiled C program produced incorrect output on an independently generated database.\n"
                f"Expected:\n{expected}\n\nActual:\n{actual}"
            )

            assert os.path.isfile(trace_path), "No SQLite3 C API calls were observed from the program."
            with open(trace_path, "rb") as f:
                records = [part.decode("utf-8", "replace") for part in f.read().split(b"\0") if part]
            prefix = f"{proc.pid}|"
            own_records = [record[len(prefix):] for record in records if record.startswith(prefix)]
            assert any(record.startswith("OPEN:") or record.startswith("OPEN16:") for record in own_records), (
                "The extractor process did not open the database through the SQLite3 C API."
            )
            sql_statements = [record[4:] for record in own_records if record.startswith("SQL:")]
            assert sql_statements, "The extractor process did not execute SQL through the SQLite3 C API."

            qualifying = []
            for statement in sql_statements:
                normalized = _remove_sql_comments_and_literals(statement)
                if (re.search(r"\bSELECT\b", normalized)
                        and re.search(r"\bSYSTEM_ACCESS_LOGS\b", normalized)
                        and re.search(r"\bNOT\s+INDEXED\b", normalized)
                        and re.search(r"\bOVER\b", normalized)):
                    qualifying.append(statement)
            assert qualifying, (
                "No SQL statement executed by the extractor contained the access-log table, "
                "NOT INDEXED, and a window-function OVER clause."
            )
    finally:
        if os.path.exists(db_path):
            os.remove(db_path)
        shutil.move(db_backup, db_path)
        if os.path.exists(report_path):
            os.remove(report_path)
        shutil.move(report_backup, report_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

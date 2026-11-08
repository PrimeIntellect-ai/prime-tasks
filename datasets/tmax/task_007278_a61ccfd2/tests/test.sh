#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TRACE_EOF' > /tmp/sqltrace.c
#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void log_sql(const char *sql) {
    const char *path = getenv("SQL_TRACE_PATH");
    if (!path || !sql) return;
    FILE *f = fopen(path, "ab");
    if (!f) return;
    size_t n = strlen(sql);
    fprintf(f, "%zu\n", n);
    fwrite(sql, 1, n, f);
    fputc('\n', f);
    fclose(f);
}

int sqlite3_prepare(sqlite3 *db, const char *sql, int n,
                    sqlite3_stmt **stmt, const char **tail) {
    typedef int (*fn_t)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **);
    static fn_t real_fn;
    if (!real_fn) real_fn = (fn_t)dlsym(RTLD_NEXT, "sqlite3_prepare");
    log_sql(sql);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int n,
                       sqlite3_stmt **stmt, const char **tail) {
    typedef int (*fn_t)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **);
    static fn_t real_fn;
    if (!real_fn) real_fn = (fn_t)dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    log_sql(sql);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v3(sqlite3 *db, const char *sql, int n, unsigned int flags,
                       sqlite3_stmt **stmt, const char **tail) {
    typedef int (*fn_t)(sqlite3 *, const char *, int, unsigned int, sqlite3_stmt **, const char **);
    static fn_t real_fn;
    if (!real_fn) real_fn = (fn_t)dlsym(RTLD_NEXT, "sqlite3_prepare_v3");
    log_sql(sql);
    return real_fn(db, sql, n, flags, stmt, tail);
}

int sqlite3_exec(sqlite3 *db, const char *sql,
                 int (*callback)(void *, int, char **, char **),
                 void *arg, char **errmsg) {
    typedef int (*fn_t)(sqlite3 *, const char *, int (*)(void *, int, char **, char **), void *, char **);
    static fn_t real_fn;
    if (!real_fn) real_fn = (fn_t)dlsym(RTLD_NEXT, "sqlite3_exec");
    log_sql(sql);
    return real_fn(db, sql, callback, arg, errmsg);
}

int sqlite3_get_table(sqlite3 *db, const char *sql, char ***result,
                      int *rows, int *cols, char **errmsg) {
    typedef int (*fn_t)(sqlite3 *, const char *, char ***, int *, int *, char **);
    static fn_t real_fn;
    if (!real_fn) real_fn = (fn_t)dlsym(RTLD_NEXT, "sqlite3_get_table");
    log_sql(sql);
    return real_fn(db, sql, result, rows, cols, errmsg);
}
TRACE_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import re
import secrets
import shutil
import sqlite3
import subprocess
import pytest

REPORT_PATH = "/home/user/report.csv"
SOURCE_PATH = "/home/user/process.cpp"
DB_PATH = "/home/user/company.db"
BINARY_PATH = "/tmp/submission_process"
TRACE_LIBRARY = "/tmp/libsqltrace.so"


def read_trace(path):
    statements = []
    with open(path, "rb") as f:
        while True:
            length_line = f.readline()
            if not length_line:
                break
            length = int(length_line.strip())
            sql = f.read(length)
            assert len(sql) == length, "Malformed SQLite trace"
            assert f.read(1) == b"\n", "Malformed SQLite trace separator"
            statements.append(sql.decode("utf-8", errors="replace"))
    return statements


def normalize_sql(sql):
    sql = re.sub(r"/\*.*?\*/", " ", sql, flags=re.S)
    sql = re.sub(r"--[^\r\n]*", " ", sql)
    return re.sub(r"\s+", " ", sql).strip().lower()


def assert_required_query_was_executed(trace_path):
    statements = read_trace(trace_path)
    normalized = [normalize_sql(s) for s in statements]
    read_queries = []
    for query in normalized:
        if re.match(r"^(with\b|select\b)", query) and query not in read_queries:
            read_queries.append(query)

    assert len(read_queries) == 1, \
        f"Expected one data-reading SQL query, observed {len(read_queries)}: {read_queries}"
    query = read_queries[0]
    assert re.match(r"^with\s+recursive\b", query), \
        "The executed query must begin with a recursive CTE"
    assert re.search(r"\bover\s*\(", query), \
        "The executed recursive query must also use a window function"
    assert re.search(r"\bsum\s*\(", query), \
        "The executed query must aggregate daily sales"
    assert re.search(r"rows\s+between\s+2\s+preceding\s+and\s+current\s+row", query), \
        "The window must cover the current row and two preceding rows"


def run_submission(trace_path):
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    if os.path.exists(trace_path):
        os.remove(trace_path)
    env = os.environ.copy()
    env["LD_PRELOAD"] = TRACE_LIBRARY
    env["SQL_TRACE_PATH"] = trace_path
    result = subprocess.run(
        [BINARY_PATH], cwd="/home/user", env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15
    )
    assert result.returncode == 0, \
        f"Compiled program exited with {result.returncode}. stderr: {result.stderr}"
    assert os.path.isfile(trace_path), "Program did not execute SQL through the SQLite3 C API"
    assert_required_query_was_executed(trace_path)


@pytest.fixture(scope="session", autouse=True)
def compile_and_run_program():
    assert os.path.isfile(SOURCE_PATH), f"C++ source file not found at {SOURCE_PATH}"
    with open(SOURCE_PATH, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()
    assert re.search(r"#\s*include\s*[<\"]sqlite3\.h[>\"]", source), \
        "process.cpp must include sqlite3.h"
    assert re.search(r"\bsqlite3_open(?:_v2)?\s*\(", source), \
        "process.cpp must open the database with the SQLite3 C API"

    trace_build = subprocess.run(
        ["gcc", "-shared", "-fPIC", "/tmp/sqltrace.c", "-ldl", "-o", TRACE_LIBRARY],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert trace_build.returncode == 0, f"Failed to build verifier trace library: {trace_build.stderr}"

    build = subprocess.run(
        ["g++", "-std=c++17", SOURCE_PATH, "-lsqlite3", "-o", BINARY_PATH],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert build.returncode == 0, f"process.cpp failed to compile: {build.stderr}"
    run_submission("/tmp/original_sql_trace.bin")


def test_report_exists():
    """Check if the report.csv file exists."""
    assert os.path.isfile(REPORT_PATH), f"Report file not found at {REPORT_PATH}"


def test_report_content():
    """Check if the report contains the correct data and formatting."""
    expected_data = [
        ("2023-10-01", 250.0, "250.00"),
        ("2023-10-02", 200.0, "225.00"),
        ("2023-10-03", 300.0, "250.00"),
        ("2023-10-04", 100.0, "200.00"),
        ("2023-10-05", 50.0, "150.00"),
        ("2023-10-06", 400.0, "183.33"),
        ("2023-10-07", 100.0, "183.33")
    ]

    with open(REPORT_PATH, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail("The report.csv file is empty.")

        assert header == ["date", "daily_total", "rolling_avg"], \
            f"CSV header is incorrect. Expected ['date', 'daily_total', 'rolling_avg'], got {header}"

        rows = list(reader)
        assert len(rows) == len(expected_data), \
            f"Expected {len(expected_data)} rows of data, but got {len(rows)}."

        for i, (row, expected) in enumerate(zip(rows, expected_data)):
            assert len(row) == 3, f"Row {i+1} does not have exactly 3 columns: {row}"

            date, daily_total_str, rolling_avg_str = row
            exp_date, exp_daily_total, exp_rolling_avg_str = expected

            assert date == exp_date, f"Row {i+1}: Expected date {exp_date}, got {date}"

            try:
                daily_total = float(daily_total_str)
            except ValueError:
                pytest.fail(f"Row {i+1}: Cannot parse daily_total '{daily_total_str}' as a float.")

            assert abs(daily_total - exp_daily_total) < 1e-5, \
                f"Row {i+1}: Expected daily_total {exp_daily_total}, got {daily_total}"

            assert rolling_avg_str == exp_rolling_avg_str, \
                f"Row {i+1}: Expected rolling_avg '{exp_rolling_avg_str}', got '{rolling_avg_str}' (must be exactly 2 decimal places)"


def test_program_recomputes_report_from_database():
    backup = "/tmp/company.db.verifier_backup"
    shutil.copy2(DB_PATH, backup)
    try:
        conn = sqlite3.connect(DB_PATH)
        token = secrets.randbelow(900000) + 100000
        employee_id = 1000000 + token
        outsider_id = 2000000 + token
        sale_id = 3000000 + token * 10
        changed_amount = float(111 + secrets.randbelow(700))
        subordinate_amount = float(37 + secrets.randbelow(500))
        later_amount = float(53 + secrets.randbelow(600))
        outsider_amount = float(5000 + secrets.randbelow(5000))

        conn.execute("UPDATE sales SET amount = ? WHERE id = 1", (changed_amount,))
        conn.execute("INSERT INTO employees(id, name, manager_id) VALUES (?, ?, 4)",
                     (employee_id, "VerifierSubordinate"))
        conn.execute("INSERT INTO employees(id, name, manager_id) VALUES (?, ?, NULL)",
                     (outsider_id, "VerifierOutsider"))
        conn.execute("INSERT INTO sales(id, employee_id, sale_date, amount) VALUES (?, ?, ?, ?)",
                     (sale_id, employee_id, "2023-10-02", subordinate_amount))
        conn.execute("INSERT INTO sales(id, employee_id, sale_date, amount) VALUES (?, ?, ?, ?)",
                     (sale_id + 1, employee_id, "2023-10-08", later_amount))
        conn.execute("INSERT INTO sales(id, employee_id, sale_date, amount) VALUES (?, ?, ?, ?)",
                     (sale_id + 2, outsider_id, "2023-10-08", outsider_amount))
        conn.commit()

        employees = conn.execute("SELECT id, manager_id FROM employees").fetchall()
        children = {}
        for employee, manager in employees:
            children.setdefault(manager, []).append(employee)
        hierarchy = set()
        pending = [1]
        while pending:
            employee = pending.pop()
            if employee in hierarchy:
                continue
            hierarchy.add(employee)
            pending.extend(children.get(employee, []))

        totals = {}
        for employee, sale_date, amount in conn.execute(
                "SELECT employee_id, sale_date, amount FROM sales"):
            if employee in hierarchy:
                totals[sale_date] = totals.get(sale_date, 0.0) + float(amount)
        conn.close()

        dates = sorted(totals)
        expected = []
        for index, date in enumerate(dates):
            window_dates = dates[max(0, index - 2):index + 1]
            rolling = sum(totals[d] for d in window_dates) / len(window_dates)
            expected.append((date, totals[date], f"{rolling:.2f}"))

        run_submission("/tmp/mutated_sql_trace.bin")
        with open(REPORT_PATH, "r", encoding="utf-8", newline="") as f:
            rows = list(csv.reader(f))
        assert rows and rows[0] == ["date", "daily_total", "rolling_avg"]
        actual = rows[1:]
        assert len(actual) == len(expected), \
            f"Mutated database should produce {len(expected)} rows, got {len(actual)}"
        for index, (row, expected_row) in enumerate(zip(actual, expected), 1):
            assert len(row) == 3, f"Dynamic row {index} does not have exactly 3 columns"
            exp_date, exp_total, exp_average = expected_row
            assert row[0] == exp_date, f"Dynamic row {index} has the wrong date"
            try:
                actual_total = float(row[1])
            except ValueError:
                pytest.fail(f"Dynamic row {index} daily_total is not numeric: {row[1]}")
            assert abs(actual_total - exp_total) < 1e-5, \
                f"Dynamic row {index} has daily_total {actual_total}, expected {exp_total}"
            assert row[2] == exp_average, \
                f"Dynamic row {index} has rolling_avg {row[2]}, expected {exp_average}"
    finally:
        if os.path.exists(backup):
            os.replace(backup, DB_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import sqlite3
import subprocess
import uuid

import pytest

DB_PATH = "/home/user/data/company.db"
OUTPUT_PATH = "/home/user/output/dept_costs.json"
SOURCE_PATH = "/home/user/etl_graph.c"
EXECUTABLE_PATH = "/home/user/etl_graph"


def get_expected_results(db_path):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    query = """
    WITH RECURSIVE subordinates AS (
        SELECT subordinate_id
        FROM reporting_lines
        JOIN employees ON employees.id = reporting_lines.manager_id
        WHERE employees.name = 'Alice'

        UNION ALL

        SELECT rl.subordinate_id
        FROM reporting_lines rl
        INNER JOIN subordinates s ON s.subordinate_id = rl.manager_id
    )
    SELECT d.name, SUM(e.salary)
    FROM subordinates s
    JOIN employees e ON s.subordinate_id = e.id
    JOIN departments d ON e.department_id = d.id
    GROUP BY d.name
    ORDER BY d.name ASC;
    """
    cursor.execute(query)
    results = cursor.fetchall()
    conn.close()
    return [
        {"department": dept, "total_salary": float(total_salary)}
        for dept, total_salary in results
    ]


def load_and_check_output(expected):
    assert os.path.exists(OUTPUT_PATH), f"Output file is missing at {OUTPUT_PATH}"
    assert os.path.isfile(OUTPUT_PATH), f"Expected a file at {OUTPUT_PATH}, but found a directory or other type"

    with open(OUTPUT_PATH, "r") as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Output file {OUTPUT_PATH} does not contain valid JSON. Error: {e}")

    assert isinstance(actual_data, list), "The JSON output must be an array of objects"
    assert len(actual_data) == len(expected), f"Expected {len(expected)} departments in the output, but found {len(actual_data)}"

    for i, (actual, wanted) in enumerate(zip(actual_data, expected)):
        assert isinstance(actual, dict), f"Item at index {i} is not a JSON object"
        assert "department" in actual, f"Item at index {i} is missing the 'department' key"
        assert "total_salary" in actual, f"Item at index {i} is missing the 'total_salary' key"
        assert set(actual) == {"department", "total_salary"}, f"Item at index {i} must have exactly the required two keys"
        assert actual["department"] == wanted["department"], f"Expected department '{wanted['department']}' at index {i}, got '{actual['department']}'"
        assert isinstance(actual["total_salary"], (int, float)) and not isinstance(actual["total_salary"], bool), f"Total salary for {actual['department']} must be a number"
        assert round(actual["total_salary"], 2) == round(wanted["total_salary"], 2), f"Incorrect total salary for department {actual['department']}. Expected {wanted['total_salary']}, got {actual['total_salary']}"


def test_output_file_exists():
    assert os.path.exists(OUTPUT_PATH), f"Output file is missing at {OUTPUT_PATH}"
    assert os.path.isfile(OUTPUT_PATH), f"Expected a file at {OUTPUT_PATH}, but found a directory or other type"


def test_output_json_format_and_correctness():
    load_and_check_output(get_expected_results(DB_PATH))


def test_c_source_code_exists():
    assert os.path.exists(SOURCE_PATH), "C source code file /home/user/etl_graph.c is missing"
    assert os.path.isfile(SOURCE_PATH), "C source path is not a regular file"


def test_compiled_executable_exists():
    assert os.path.isfile(EXECUTABLE_PATH), "Compiled executable /home/user/etl_graph is missing"
    assert os.access(EXECUTABLE_PATH, os.X_OK), "/home/user/etl_graph is not executable"
    with open(EXECUTABLE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/etl_graph is not a compiled ELF executable"


def build_trace_library():
    shim_source = r'''
#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void log_sql(const char *sql, int n) {
    const char *path = getenv("SQL_TRACE_FILE");
    if (!path || !sql) return;
    FILE *f = fopen(path, "a");
    if (!f) return;
    if (n < 0) n = (int)strlen(sql);
    fprintf(f, "SQLBEGIN\n");
    fwrite(sql, 1, (size_t)n, f);
    fprintf(f, "\nSQLEND\n");
    fclose(f);
}

int sqlite3_exec(sqlite3 *db, const char *sql,
                 int (*callback)(void*,int,char**,char**), void *arg,
                 char **errmsg) {
    static int (*real_fn)(sqlite3*, const char*, int (*)(void*,int,char**,char**), void*, char**) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_exec");
    log_sql(sql, -1);
    return real_fn(db, sql, callback, arg, errmsg);
}

int sqlite3_prepare(sqlite3 *db, const char *sql, int n,
                    sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3*, const char*, int, sqlite3_stmt**, const char**) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare");
    log_sql(sql, n);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int n,
                       sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3*, const char*, int, sqlite3_stmt**, const char**) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    log_sql(sql, n);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v3(sqlite3 *db, const char *sql, int n, unsigned int flags,
                       sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3*, const char*, int, unsigned int, sqlite3_stmt**, const char**) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v3");
    log_sql(sql, n);
    return real_fn(db, sql, n, flags, stmt, tail);
}
'''
    shim_c = "/tmp/sqlite_trace_shim.c"
    shim_so = "/tmp/sqlite_trace_shim.so"
    with open(shim_c, "w") as f:
        f.write(shim_source)
    subprocess.run(
        ["gcc", "-shared", "-fPIC", shim_c, "-o", shim_so, "-ldl"],
        check=True,
        capture_output=True,
        text=True,
    )
    return shim_so


def test_program_compiles_runs_and_queries_dynamic_database():
    compile_result = subprocess.run(
        ["gcc", SOURCE_PATH, "-o", EXECUTABLE_PATH, "-lsqlite3"],
        capture_output=True,
        text=True,
    )
    assert compile_result.returncode == 0, f"C source did not compile with SQLite: {compile_result.stderr}"
    assert os.path.isfile(EXECUTABLE_PATH) and os.access(EXECUTABLE_PATH, os.X_OK)
    with open(EXECUTABLE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "Compilation did not produce an ELF executable"

    symbols = subprocess.run(
        ["nm", "-D", EXECUTABLE_PATH], capture_output=True, text=True, check=True
    ).stdout
    assert re.search(r"\bsqlite3_open(?:_v2)?(?:@\S+)?\b", symbols), "Executable does not use sqlite3_open/sqlite3_open_v2"
    uses_exec = re.search(r"\bsqlite3_exec(?:@\S+)?\b", symbols)
    uses_prepare = re.search(r"\bsqlite3_prepare(?:_v[23])?(?:@\S+)?\b", symbols)
    uses_step = re.search(r"\bsqlite3_step(?:@\S+)?\b", symbols)
    assert uses_exec or (uses_prepare and uses_step), "Executable does not execute SQL through the SQLite C API"

    db_backup = "/tmp/company.db.verifier_backup"
    output_backup = "/tmp/dept_costs.verifier_backup"
    had_output = os.path.isfile(OUTPUT_PATH)
    shutil.copy2(DB_PATH, db_backup)
    if had_output:
        shutil.copy2(OUTPUT_PATH, output_backup)

    trace_path = "/tmp/etl_sql_trace.txt"
    try:
        token = uuid.uuid4().hex[:10]
        dept_a = "AuditA_" + token
        dept_z = "AuditZ_" + token

        conn = sqlite3.connect(DB_PATH)
        cur = conn.cursor()
        next_dept = cur.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM departments").fetchone()[0]
        next_emp = cur.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM employees").fetchone()[0]
        alice_id = cur.execute("SELECT id FROM employees WHERE name = 'Alice'").fetchone()[0]

        cur.execute("UPDATE employees SET salary = ? WHERE name = 'Bob'", (123456.78,))
        cur.executemany("INSERT INTO departments(id, name) VALUES (?, ?)", [
            (next_dept, dept_a),
            (next_dept + 1, dept_z),
        ])
        cur.executemany("INSERT INTO employees(id, name, department_id, salary) VALUES (?, ?, ?, ?)", [
            (next_emp, "DynamicDirect_" + token, next_dept, 43210.98),
            (next_emp + 1, "DynamicIndirect_" + token, next_dept + 1, 87654.32),
            (next_emp + 2, "DynamicDisconnected_" + token, next_dept, 999999.99),
        ])
        cur.executemany("INSERT INTO reporting_lines(manager_id, subordinate_id) VALUES (?, ?)", [
            (alice_id, next_emp),
            (next_emp, next_emp + 1),
        ])
        conn.commit()
        conn.close()

        expected = get_expected_results(DB_PATH)
        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)
        if os.path.exists(trace_path):
            os.remove(trace_path)

        shim_so = build_trace_library()
        env = os.environ.copy()
        env["LD_PRELOAD"] = shim_so
        env["SQL_TRACE_FILE"] = trace_path
        run_result = subprocess.run(
            [EXECUTABLE_PATH],
            cwd="/home/user",
            env=env,
            capture_output=True,
            text=True,
            timeout=15,
        )
        assert run_result.returncode == 0, f"ETL executable failed: {run_result.stderr}"
        load_and_check_output(expected)

        assert os.path.isfile(trace_path), "No SQL was observed through the SQLite C API"
        with open(trace_path, "r", errors="replace") as f:
            trace = f.read()
        statements = re.findall(r"SQLBEGIN\n(.*?)\nSQLEND", trace, flags=re.DOTALL)
        recursive_queries = [s for s in statements if re.search(r"\bWITH\s+RECURSIVE\b", s, re.IGNORECASE)]
        assert recursive_queries, "The program did not execute a recursive CTE through the SQLite C API"
        assert any(
            re.search(r"\breporting_lines\b", s, re.IGNORECASE)
            and re.search(r"\bemployees\b", s, re.IGNORECASE)
            and re.search(r"\bdepartments\b", s, re.IGNORECASE)
            and re.search(r"\b(?:SUM|TOTAL)\s*\(", s, re.IGNORECASE)
            and re.search(r"\bGROUP\s+BY\b", s, re.IGNORECASE)
            for s in recursive_queries
        ), "Recursive query did not traverse reporting_lines and aggregate salaries by department"
    finally:
        shutil.copy2(db_backup, DB_PATH)
        if had_output:
            shutil.copy2(output_backup, OUTPUT_PATH)
        elif os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

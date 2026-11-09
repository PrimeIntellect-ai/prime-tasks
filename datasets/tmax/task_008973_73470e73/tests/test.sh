#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import sqlite3
import subprocess
import tempfile

import pytest

DB_PATH = "/home/user/company.db"
SOURCE_PATH = "/home/user/export_hierarchy.c"
EXE_PATH = "/home/user/export_hierarchy"
REPORT_PATH = "/home/user/reports_1.csv"
SQL_PATH = "/home/user/optimize.sql"

EXPECTED_ROOT_1 = [
    "1,Alice",
    "2,Bob",
    "3,Charlie",
    "4,David",
    "5,Eve",
    "6,Frank",
    "7,Grace",
]


def output_lines(data):
    return [line.strip() for line in data.splitlines() if line.strip()]


def build_trace_library(tmp_path):
    source = tmp_path / "sqlite_trace.c"
    library = tmp_path / "sqlite_trace.so"
    source.write_text(r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <fcntl.h>
#include <sqlite3.h>
#include <stdio.h>
#include <stdlib.h>
#include <unistd.h>

static void log_line(const char *kind, sqlite3_stmt *stmt, const char *sql, int idx, int value) {
    const char *path = getenv("SQLITE_TRACE_FILE");
    if (!path) return;
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd < 0) return;
    if (sql)
        dprintf(fd, "%s|%p|%s\n", kind, (void *)stmt, sql);
    else
        dprintf(fd, "%s|%p|%d|%d\n", kind, (void *)stmt, idx, value);
    close(fd);
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_prepare)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **);
    if (!real_prepare)
        real_prepare = dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    int rc = real_prepare(db, sql, n, stmt, tail);
    if (rc == SQLITE_OK && stmt && *stmt)
        log_line("P", *stmt, sql, 0, 0);
    return rc;
}

int sqlite3_bind_int(sqlite3_stmt *stmt, int idx, int value) {
    static int (*real_bind)(sqlite3_stmt *, int, int);
    if (!real_bind)
        real_bind = dlsym(RTLD_NEXT, "sqlite3_bind_int");
    log_line("B", stmt, NULL, idx, value);
    return real_bind(stmt, idx, value);
}
''')
    subprocess.run(
        ["gcc", "-shared", "-fPIC", str(source), "-o", str(library), "-ldl"],
        check=True,
        capture_output=True,
        text=True,
    )
    return library


def run_and_trace(executable, employee_id, trace_library, tmp_path):
    trace_file = tmp_path / ("trace_" + secrets.token_hex(8) + ".log")
    env = os.environ.copy()
    env["LD_PRELOAD"] = str(trace_library)
    env["SQLITE_TRACE_FILE"] = str(trace_file)
    result = subprocess.run(
        [str(executable), str(employee_id)],
        env=env,
        capture_output=True,
        text=True,
        timeout=8,
    )
    assert result.returncode == 0, result.stderr
    assert trace_file.is_file(), "The executable did not use the SQLite library as required."

    prepared = {}
    bindings = []
    for line in trace_file.read_text(errors="replace").splitlines():
        parts = line.split("|", 2)
        if len(parts) == 3 and parts[0] == "P":
            prepared[parts[1]] = parts[2]
        elif len(parts) == 3 and parts[0] == "B":
            details = parts[2].split("|", 1)
            if len(details) == 2:
                bindings.append((parts[1], int(details[0]), int(details[1])))

    matching_statements = {
        pointer
        for pointer, sql in prepared.items()
        if "with recursive" in sql.lower() and "?" in sql
    }
    assert matching_statements, "The executed recursive query was not parameterized with a placeholder."
    assert any(
        pointer in matching_statements and index == 1 and value == int(employee_id)
        for pointer, index, value in bindings
    ), "sqlite3_bind_int was not executed on the recursive statement with the requested employee ID."
    return output_lines(result.stdout)


def hierarchy_from_database(root_id):
    conn = sqlite3.connect(DB_PATH)
    rows = conn.execute("SELECT id, name, manager_id FROM employees").fetchall()
    conn.close()
    by_id = {row[0]: row for row in rows}
    children = {}
    for employee_id, name, manager_id in rows:
        children.setdefault(manager_id, []).append(employee_id)

    result = []
    pending = [root_id]
    seen = set()
    while pending:
        employee_id = pending.pop()
        if employee_id in seen or employee_id not in by_id:
            continue
        seen.add(employee_id)
        result.append(f"{employee_id},{by_id[employee_id][1]}")
        pending.extend(children.get(employee_id, []))
    return result


def test_optimize_sql_exists():
    assert os.path.isfile(SQL_PATH), f"Optimization script {SQL_PATH} does not exist."


def test_index_created():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} does not exist."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT count(*) FROM sqlite_master WHERE type='index' AND name='idx_manager';")
    count = cursor.fetchone()[0]
    assert count == 1, "Index 'idx_manager' was not created in the database."

    index_columns = [row[2] for row in cursor.execute("PRAGMA index_info('idx_manager')")]
    employee_indexes = [row[1] for row in cursor.execute("PRAGMA index_list('employees')")]
    conn.close()
    assert "idx_manager" in employee_indexes, "Index 'idx_manager' is not on the employees table."
    assert index_columns == ["manager_id"], "Index 'idx_manager' is not exactly on employees(manager_id)."


def test_optimize_script_creates_required_index():
    script = open(SQL_PATH, "r").read()
    conn = sqlite3.connect(":memory:")
    conn.execute("CREATE TABLE employees (id INTEGER PRIMARY KEY, name TEXT, manager_id INTEGER)")
    conn.executescript(script)
    indexes = [row[1] for row in conn.execute("PRAGMA index_list('employees')")]
    columns = [row[2] for row in conn.execute("PRAGMA index_info('idx_manager')")]
    conn.close()
    assert "idx_manager" in indexes, "optimize.sql does not create idx_manager on employees."
    assert columns == ["manager_id"], "optimize.sql does not index employees(manager_id)."


def test_c_file_fixed():
    assert os.path.isfile(SOURCE_PATH), f"C source file {SOURCE_PATH} does not exist."
    with open(SOURCE_PATH, "r") as source_file:
        content = source_file.read()

    assert "sqlite3_bind_int" in content, "The C program does not use 'sqlite3_bind_int' for parameter binding."
    assert "manager_id" in content and "id" in content and "=" in content, \
        "The recursive CTE does not appear to have a join condition (e.g., e.manager_id = s.id)."


def test_executable_exists():
    assert os.path.isfile(EXE_PATH), f"Compiled executable {EXE_PATH} does not exist."
    assert os.access(EXE_PATH, os.X_OK), f"File {EXE_PATH} is not executable."
    with open(EXE_PATH, "rb") as executable:
        assert executable.read(4) == b"\x7fELF", "export_hierarchy is not a compiled executable."


def test_reports_csv_content():
    assert os.path.isfile(REPORT_PATH), f"Output file {REPORT_PATH} does not exist."
    with open(REPORT_PATH, "r") as report:
        lines = [line.strip() for line in report.readlines() if line.strip()]
    assert sorted(lines) == sorted(EXPECTED_ROOT_1), \
        f"The contents of {REPORT_PATH} do not match the expected recursive hierarchy for employee 1."


def test_compiled_program_and_source_on_runtime_data(tmp_path):
    trace_library = build_trace_library(tmp_path)

    rebuilt = tmp_path / "export_hierarchy_rebuilt"
    subprocess.run(
        ["gcc", SOURCE_PATH, "-o", str(rebuilt), "-lsqlite3"],
        check=True,
        capture_output=True,
        text=True,
    )

    actual_root_1 = run_and_trace(EXE_PATH, 1, trace_library, tmp_path)
    assert sorted(actual_root_1) == sorted(EXPECTED_ROOT_1)
    with open(REPORT_PATH, "r") as report:
        report_lines = [line.strip() for line in report if line.strip()]
    assert sorted(actual_root_1) == sorted(report_lines), \
        "reports_1.csv is not the output produced by the submitted executable for employee 1."

    conn = sqlite3.connect(DB_PATH)
    used = {row[0] for row in conn.execute("SELECT id FROM employees")}
    while True:
        base = secrets.randbelow(900000000) + 100000000
        ids = [base + offset for offset in range(5)]
        if all(employee_id not in used for employee_id in ids):
            break

    root, child_a, child_b, grandchild, distractor = ids
    try:
        conn.executemany(
            "INSERT INTO employees(id, name, manager_id) VALUES (?, ?, ?)",
            [
                (root, "RuntimeRoot", None),
                (child_a, "RuntimeChildA", root),
                (child_b, "RuntimeChildB", root),
                (grandchild, "RuntimeGrandchild", child_a),
                (distractor, "RuntimeDistractor", None),
            ],
        )
        conn.commit()
        expected = hierarchy_from_database(root)

        for executable in (EXE_PATH, rebuilt):
            actual = run_and_trace(executable, root, trace_library, tmp_path)
            assert sorted(actual) == sorted(expected), \
                "The executable did not recursively traverse the runtime hierarchy."
            assert f"{distractor},RuntimeDistractor" not in actual, \
                "The recursive query included an unrelated employee."
    finally:
        conn.executemany("DELETE FROM employees WHERE id = ?", [(employee_id,) for employee_id in ids])
        conn.commit()
        conn.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

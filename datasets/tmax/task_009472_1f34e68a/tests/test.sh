#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'C_EOF' > /tmp/sqlite_trace.c
#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

static void log_sql(const char *kind, const char *sql) {
    const char *path = getenv("ORG_QUERY_SQL_TRACE");
    if (!path || !sql) return;
    FILE *f = fopen(path, "a");
    if (!f) return;
    fprintf(f, "%s\n%s\n---SQL-END---\n", kind, sql);
    fclose(f);
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    log_sql("PREPARE", sql);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v3(sqlite3 *db, const char *sql, int n, unsigned int flags, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, unsigned int, sqlite3_stmt **, const char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v3");
    log_sql("PREPARE", sql);
    return real_fn(db, sql, n, flags, stmt, tail);
}

int sqlite3_exec(sqlite3 *db, const char *sql, int (*cb)(void *, int, char **, char **), void *arg, char **errmsg) {
    static int (*real_fn)(sqlite3 *, const char *, int (*)(void *, int, char **, char **), void *, char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_exec");
    log_sql("EXEC", sql);
    return real_fn(db, sql, cb, arg, errmsg);
}
C_EOF

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import shutil
import sqlite3
import subprocess
from pathlib import Path

import pytest

PROJECT = Path("/home/user/org_query")
OUTPUT = Path("/home/user/reports_output.json")
DB = Path("/home/user/company.db")
TRACE_LIB = Path("/tmp/libsqlite_trace.so")
TRACE_FILE = Path("/tmp/org_query_sql_trace.log")


def load_and_validate_output():
    assert OUTPUT.is_file(), f"Output file {OUTPUT} does not exist. Did the program run successfully?"
    try:
        with OUTPUT.open("r", encoding="utf-8") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {OUTPUT} does not contain valid JSON.")

    assert isinstance(data, list), "The JSON output must be a list (array) of objects."
    for i, item in enumerate(data):
        assert isinstance(item, dict), f"Item at index {i} is not a JSON object."
        assert set(item.keys()) == {"emp_id", "emp_name", "depth"}, \
            f"Item at index {i} has incorrect keys: {list(item.keys())}"
        assert type(item["emp_id"]) is int, f"emp_id at index {i} must be an integer."
        assert type(item["emp_name"]) is str, f"emp_name at index {i} must be a string."
        assert type(item["depth"]) is int, f"depth at index {i} must be an integer."
    assert [x["emp_id"] for x in data] == sorted(x["emp_id"] for x in data), \
        "The JSON array is not sorted by emp_id in ascending order."
    return data


def expected_for(start_id):
    with sqlite3.connect(DB) as conn:
        rows = conn.execute(
            """
            WITH RECURSIVE subtree(id, name, depth) AS (
                SELECT id, name, 0 FROM employees WHERE id = ?
                UNION ALL
                SELECT e.id, e.name, subtree.depth + 1
                FROM employees AS e
                JOIN subtree ON e.manager_id = subtree.id
            )
            SELECT id, name, depth FROM subtree ORDER BY id
            """,
            (start_id,),
        ).fetchall()
    return [{"emp_id": row[0], "emp_name": row[1], "depth": row[2]} for row in rows]


def read_trace():
    if not TRACE_FILE.exists():
        return []
    records = []
    for block in TRACE_FILE.read_text(encoding="utf-8", errors="replace").split("---SQL-END---"):
        block = block.strip()
        if not block:
            continue
        lines = block.splitlines()
        if len(lines) >= 2:
            records.append((lines[0], "\n".join(lines[1:])))
    return records


def run_program(start_id):
    if OUTPUT.exists():
        OUTPUT.unlink()
    if TRACE_FILE.exists():
        TRACE_FILE.unlink()

    env = os.environ.copy()
    env["LD_PRELOAD"] = str(TRACE_LIB)
    env["ORG_QUERY_SQL_TRACE"] = str(TRACE_FILE)
    result = subprocess.run(
        ["cargo", "run", "--quiet", "--", str(start_id)],
        cwd=PROJECT,
        env=env,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=180,
    )
    assert result.returncode == 0, \
        f"cargo run -- {start_id} failed.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    actual = load_and_validate_output()
    assert actual == expected_for(start_id), f"Incorrect subtree output for starting employee {start_id}."

    # When the submission dynamically links SQLite, observe the actual statements and
    # require the employee-fetching statement to be one recursive CTE. Static/bundled
    # SQLite cannot be interposed, so the source assertion below remains applicable.
    records = read_trace()
    employee_reads = []
    for kind, sql in records:
        normalized = " ".join(sql.split())
        if re.search(r"\bemployees\b", normalized, re.I) and re.search(r"\b(?:SELECT|WITH)\b", normalized, re.I):
            employee_reads.append((kind, normalized))
    if employee_reads:
        unique_sql = {sql for _, sql in employee_reads}
        assert len(unique_sql) == 1, \
            f"Expected one employee-fetching SQL statement, observed: {sorted(unique_sql)}"
        only_sql = next(iter(unique_sql))
        assert re.search(r"\bWITH\s+RECURSIVE\b", only_sql, re.I), \
            "The executed employee-fetching statement is not a WITH RECURSIVE CTE."


def test_complete_pipeline():
    # Preserve the original project assertions.
    assert PROJECT.is_dir(), f"Rust project directory {PROJECT} does not exist."
    assert (PROJECT / "Cargo.toml").is_file(), \
        f"Cargo.toml not found at {PROJECT / 'Cargo.toml'}. Did you create a Rust project?"

    # Preserve the original assertion on the pre-generated result for ID 2.
    expected_initial = [
        {"depth": 0, "emp_id": 2, "emp_name": "Bob"},
        {"depth": 1, "emp_id": 4, "emp_name": "David"},
        {"depth": 1, "emp_id": 5, "emp_name": "Eve"},
        {"depth": 2, "emp_id": 7, "emp_name": "Grace"},
        {"depth": 2, "emp_id": 8, "emp_name": "Heidi"},
        {"depth": 2, "emp_id": 9, "emp_name": "Ivan"},
    ]
    assert load_and_validate_output() == expected_initial

    rust_files = list(PROJECT.rglob("*.rs"))
    assert rust_files, "The Rust project contains no Rust source files."
    source = "\n".join(p.read_text(encoding="utf-8", errors="replace") for p in rust_files)
    source_without_comments = re.sub(r"/\*.*?\*/|//[^\n]*", "", source, flags=re.S)
    cte_occurrences = re.findall(r"\bWITH\s+RECURSIVE\b", source_without_comments, flags=re.I)
    assert len(cte_occurrences) == 1, \
        "Rust source must contain a single WITH RECURSIVE query for subtree extraction."

    subprocess.run(
        ["gcc", "-shared", "-fPIC", "-o", str(TRACE_LIB), "/tmp/sqlite_trace.c", "-ldl"],
        check=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )
    build = subprocess.run(
        ["cargo", "build", "--quiet"], cwd=PROJECT, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=180,
    )
    assert build.returncode == 0, f"Cargo build failed:\n{build.stderr}"

    # Exactly one command-line argument must be required.
    for bad_args in ([], ["2", "3"]):
        result = subprocess.run(
            ["cargo", "run", "--quiet", "--", *bad_args],
            cwd=PROJECT, text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=180,
        )
        assert result.returncode != 0, f"Program accepted invalid argument list: {bad_args}"

    backup = Path("/tmp/company.db.verifier_backup")
    shutil.copy2(DB, backup)
    try:
        # Add unpredictable records so fixed JSON for the original fixture cannot pass.
        with sqlite3.connect(DB) as conn:
            max_id = conn.execute("SELECT MAX(id) FROM employees").fetchone()[0]
            ids = [max_id + 101, max_id + 202, max_id + 303]
            conn.executemany(
                "INSERT INTO employees(id, name, manager_id) VALUES (?, ?, ?)",
                [
                    (ids[0], "Verifier Δ branch 'one'", 3),
                    (ids[1], "Verifier nested child", ids[0]),
                    (ids[2], "Verifier Bob leaf", 2),
                ],
            )
            conn.commit()

        run_program(2)
        run_program(3)
        run_program(ids[0])
        run_program(1)
    finally:
        shutil.copy2(backup, DB)
        backup.unlink(missing_ok=True)


TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

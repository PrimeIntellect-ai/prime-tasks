#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'SHIM_EOF' > /tmp/sqlite_audit.c
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <sqlite3.h>

static __thread int audit_depth = 0;

static void log_sql(const char *sql) {
    const char *path = getenv("ANALYZE_SQL_LOG");
    if (!path || !sql || audit_depth != 0) return;
    FILE *f = fopen(path, "ab");
    if (!f) return;
    uint64_t n = (uint64_t)strlen(sql);
    fwrite(&n, sizeof(n), 1, f);
    fwrite(sql, 1, (size_t)n, f);
    fclose(f);
}

int sqlite3_prepare(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare");
    log_sql(sql);
    audit_depth++;
    int rc = real_fn(db, sql, n, stmt, tail);
    audit_depth--;
    return rc;
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    log_sql(sql);
    audit_depth++;
    int rc = real_fn(db, sql, n, stmt, tail);
    audit_depth--;
    return rc;
}

int sqlite3_prepare_v3(sqlite3 *db, const char *sql, int n, unsigned int flags, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, unsigned int, sqlite3_stmt **, const char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v3");
    log_sql(sql);
    audit_depth++;
    int rc = real_fn(db, sql, n, flags, stmt, tail);
    audit_depth--;
    return rc;
}

int sqlite3_exec(sqlite3 *db, const char *sql, int (*callback)(void *, int, char **, char **), void *arg, char **errmsg) {
    static int (*real_fn)(sqlite3 *, const char *, int (*)(void *, int, char **, char **), void *, char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_exec");
    log_sql(sql);
    audit_depth++;
    int rc = real_fn(db, sql, callback, arg, errmsg);
    audit_depth--;
    return rc;
}

int sqlite3_get_table(sqlite3 *db, const char *sql, char ***result, int *rows, int *cols, char **errmsg) {
    static int (*real_fn)(sqlite3 *, const char *, char ***, int *, int *, char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_get_table");
    log_sql(sql);
    audit_depth++;
    int rc = real_fn(db, sql, result, rows, cols, errmsg);
    audit_depth--;
    return rc;
}
SHIM_EOF

gcc -shared -fPIC /tmp/sqlite_audit.c -o /tmp/sqlite_audit.so -ldl -lsqlite3

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import sqlite3
import struct
import subprocess
import tempfile

DB_PATH = "/home/user/research.db"
REPORT_PATH = "/home/user/report.txt"
SOURCE_PATH = "/home/user/analyze.c"
EXE_PATH = "/home/user/analyze"
SHIM_PATH = "/tmp/sqlite_audit.so"


def test_analyze_c_exists():
    """Test that the C source code file exists."""
    assert os.path.isfile(SOURCE_PATH), "/home/user/analyze.c is missing."


def test_analyze_executable_exists():
    """Test that the compiled executable exists and is executable."""
    assert os.path.isfile(EXE_PATH), f"{EXE_PATH} is missing."
    assert os.access(EXE_PATH, os.X_OK), f"{EXE_PATH} is not executable."


def test_report_txt_exists():
    """Test that report.txt exists."""
    assert os.path.isfile(REPORT_PATH), "/home/user/report.txt is missing."


def test_report_txt_content():
    """Keep the original fixed-fixture report assertion."""
    expected_content = [
        "1,0,100,100",
        "2,1,50,150",
        "3,1,200,350",
        "4,2,30,380",
        "5,2,20,400",
        "6,2,10,410",
        "8,3,5,415"
    ]
    with open(REPORT_PATH, "r") as f:
        lines = [line.strip() for line in f if line.strip()]
    assert len(lines) == len(expected_content), f"Expected {len(expected_content)} lines in report.txt, but got {len(lines)}."
    for i, (actual, expected) in enumerate(zip(lines, expected_content)):
        assert actual == expected, f"Line {i+1} mismatch. Expected '{expected}', got '{actual}'."


def test_query_logic_in_db():
    """Keep the original independent fixture/query assertion."""
    assert os.path.isfile(DB_PATH), f"{DB_PATH} is missing."
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    query = """
    WITH RECURSIVE tree AS (
        SELECT file_id, file_size, 0 as depth FROM files WHERE file_id = 1
        UNION ALL
        SELECT f.file_id, f.file_size, t.depth + 1
        FROM files f JOIN tree t ON f.parent_id = t.file_id
    )
    SELECT file_id, depth, file_size,
           SUM(file_size) OVER (ORDER BY depth ASC, file_id ASC) as running_total
    FROM tree;
    """
    try:
        cursor.execute(query)
        results = cursor.fetchall()
        expected_results = [
            (1, 0, 100, 100),
            (2, 1, 50, 150),
            (3, 1, 200, 350),
            (4, 2, 30, 380),
            (5, 2, 20, 400),
            (6, 2, 10, 410),
            (8, 3, 5, 415)
        ]
        assert results == expected_results, "Database state or query logic does not match the expected hierarchical data."
    finally:
        conn.close()


def _strip_c_comments(text):
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    return re.sub(r"//[^\n]*", " ", text)


def test_source_uses_sqlite_and_one_query_api_call():
    """Ensure the submitted C implementation contains and executes one SQLite query."""
    with open(SOURCE_PATH, "r", encoding="utf-8", errors="replace") as f:
        source = _strip_c_comments(f.read())
    lower = source.lower()
    assert re.search(r"#\s*include\s*[<\"]sqlite3\.h[>\"]", lower), "analyze.c must include sqlite3.h."
    assert re.search(r"\bsqlite3_open(?:_v2)?\s*\(", lower), "analyze.c must open the SQLite database through the C API."
    query_calls = re.findall(r"\bsqlite3_(?:prepare|prepare_v2|prepare_v3|exec|get_table)\s*\(", lower)
    assert len(query_calls) == 1, f"Expected exactly one SQLite query API call in analyze.c, found {len(query_calls)}."
    assert re.search(r"\bwith\s+recursive\b", lower), "The SQL must use WITH RECURSIVE."
    assert re.search(r"\bsum\s*\(", lower) and re.search(r"\bover\s*\(", lower), "The SQL must use a SUM window function."


def _expected_from_database():
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute("SELECT file_id, parent_id, file_size FROM files").fetchall()
    finally:
        conn.close()
    by_parent = {}
    sizes = {}
    for file_id, parent_id, file_size in rows:
        sizes[file_id] = file_size
        by_parent.setdefault(parent_id, []).append(file_id)
    found = []
    stack = [(1, 0)]
    seen = set()
    while stack:
        file_id, depth = stack.pop()
        if file_id in seen or file_id not in sizes:
            continue
        seen.add(file_id)
        found.append((file_id, depth, sizes[file_id]))
        for child in by_parent.get(file_id, []):
            stack.append((child, depth + 1))
    found.sort(key=lambda row: (row[1], row[0]))
    total = 0
    expected = []
    for file_id, depth, size in found:
        total += size
        expected.append(f"{file_id},{depth},{size},{total}")
    return expected


def _read_audited_queries(path):
    data = open(path, "rb").read()
    queries = []
    pos = 0
    while pos < len(data):
        assert pos + 8 <= len(data), "Malformed SQLite audit log."
        length = struct.unpack_from("=Q", data, pos)[0]
        pos += 8
        assert pos + length <= len(data), "Malformed SQLite audit log."
        queries.append(data[pos:pos + length].decode("utf-8", errors="replace"))
        pos += length
    return queries


def _assert_required_query(sql):
    normalized = re.sub(r"\s+", " ", sql.lower())
    assert re.search(r"\bwith\s+recursive\b", normalized), "Executed SQL did not use a recursive CTE."
    assert re.search(r"\bsum\s*\([^)]*\)\s*over\s*\(", normalized), "Executed SQL did not use the required SUM window function."
    assert re.search(r"order\s+by\s+(?:\w+\.)?depth(?:\s+asc)?\s*,\s*(?:\w+\.)?file_id(?:\s+asc)?", normalized), \
        "Window running total must order by depth ASC and then file_id ASC."
    assert re.search(r"file_id\s*=\s*1\b", normalized), "Recursive tree must be rooted at file_id = 1."


def _run_and_check(executable, expected, tag):
    if os.path.exists(REPORT_PATH):
        os.unlink(REPORT_PATH)
    log_path = f"/tmp/sqlite-query-{tag}-{secrets.token_hex(8)}.bin"
    env = os.environ.copy()
    env["LD_PRELOAD"] = SHIM_PATH
    env["ANALYZE_SQL_LOG"] = log_path
    try:
        result = subprocess.run([executable], cwd="/home/user", env=env, stdout=subprocess.PIPE,
                                stderr=subprocess.PIPE, text=True, timeout=10)
        assert result.returncode == 0, f"{executable} failed: {result.stderr}"
        assert os.path.isfile(REPORT_PATH), f"{executable} did not create report.txt."
        with open(REPORT_PATH, "r", encoding="utf-8") as f:
            actual = f.read().splitlines()
        assert actual == expected, f"{executable} produced an incorrect report for a changed database."
        queries = _read_audited_queries(log_path) if os.path.exists(log_path) else []
        assert len(queries) == 1, f"{executable} must execute exactly one SQLite query; observed {len(queries)}."
        _assert_required_query(queries[0])
    finally:
        if os.path.exists(log_path):
            os.unlink(log_path)


def test_execute_submitted_program_on_changed_database():
    """Run both the submitted executable and a fresh build on unpredictable data."""
    with tempfile.TemporaryDirectory() as td:
        db_backup = os.path.join(td, "research.db")
        shutil.copy2(DB_PATH, db_backup)
        report_backup = None
        if os.path.exists(REPORT_PATH):
            with open(REPORT_PATH, "rb") as f:
                report_backup = f.read()
        try:
            conn = sqlite3.connect(DB_PATH)
            rng = secrets.SystemRandom()
            for file_id in (1, 2, 3, 4, 5, 6, 8):
                conn.execute("UPDATE files SET file_size=? WHERE file_id=?", (rng.randrange(11, 900), file_id))
            base = 10000 + rng.randrange(10000)
            additions = [
                (base, "dynamic_child", 1, rng.randrange(11, 900)),
                (base + 1, "dynamic_grandchild", base, rng.randrange(11, 900)),
                (base + 2, "dynamic_deep_child", base + 1, rng.randrange(11, 900)),
                (base + 3, "unrelated", 7, rng.randrange(11, 900)),
            ]
            conn.executemany("INSERT INTO files(file_id,file_name,parent_id,file_size) VALUES(?,?,?,?)", additions)
            conn.commit()
            conn.close()

            expected = _expected_from_database()
            _run_and_check(EXE_PATH, expected, "submitted")

            rebuilt = os.path.join(td, "analyze-rebuilt")
            build = subprocess.run(["gcc", SOURCE_PATH, "-o", rebuilt, "-lsqlite3"],
                                   stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20)
            assert build.returncode == 0, f"analyze.c does not compile: {build.stderr}"
            _run_and_check(rebuilt, expected, "rebuilt")
        finally:
            shutil.copy2(db_backup, DB_PATH)
            if report_backup is None:
                if os.path.exists(REPORT_PATH):
                    os.unlink(REPORT_PATH)
            else:
                with open(REPORT_PATH, "wb") as f:
                    f.write(report_backup)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

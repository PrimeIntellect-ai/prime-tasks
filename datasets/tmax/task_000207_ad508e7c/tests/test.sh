#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import sqlite3
import subprocess
import secrets
import pytest

SOURCE = "/home/user/process_backups.cpp"
DB = "/home/user/backups.db"
OUTPUT = "/home/user/orphaned_size.txt"
BINARY = "/tmp/process_backups_submission"
TRACE = "/tmp/process_backups_sql.log"
ORIGINAL_DB = "/tmp/original_backups.db"
SHIM = "/tmp/sqlite_trace.so"


def build_trace_shim():
    source = r'''
#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <stdio.h>

static void log_sql(const char *sql) {
    if (!sql) return;
    FILE *f = fopen("/tmp/process_backups_sql.log", "a");
    if (f) {
        fprintf(f, "%s\n--END-SQL--\n", sql);
        fclose(f);
    }
}

int sqlite3_exec(sqlite3 *db, const char *sql,
                 int (*callback)(void*,int,char**,char**), void *arg,
                 char **errmsg) {
    static int (*real_fn)(sqlite3*,const char*,int(*)(void*,int,char**,char**),void*,char**) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_exec");
    log_sql(sql);
    return real_fn(db, sql, callback, arg, errmsg);
}

int sqlite3_prepare(sqlite3 *db, const char *sql, int n,
                    sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3*,const char*,int,sqlite3_stmt**,const char**) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare");
    log_sql(sql);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int n,
                       sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3*,const char*,int,sqlite3_stmt**,const char**) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    log_sql(sql);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v3(sqlite3 *db, const char *sql, int n,
                       unsigned int flags, sqlite3_stmt **stmt,
                       const char **tail) {
    static int (*real_fn)(sqlite3*,const char*,int,unsigned int,sqlite3_stmt**,const char**) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v3");
    log_sql(sql);
    return real_fn(db, sql, n, flags, stmt, tail);
}
'''
    with open("/tmp/sqlite_trace.c", "w") as f:
        f.write(source)
    subprocess.run(
        ["gcc", "-shared", "-fPIC", "/tmp/sqlite_trace.c", "-o", SHIM, "-ldl", "-lsqlite3"],
        check=True, capture_output=True, text=True
    )


def run_program(clear_trace=False):
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    if clear_trace and os.path.exists(TRACE):
        os.remove(TRACE)
    env = os.environ.copy()
    env["LD_PRELOAD"] = SHIM
    subprocess.run(
        [BINARY], cwd="/home/user", env=env, timeout=12,
        check=True, capture_output=True, text=True
    )


def drop_index():
    conn = sqlite3.connect(DB)
    conn.execute("DROP INDEX IF EXISTS idx_parent_id")
    conn.commit()
    conn.close()


@pytest.fixture(scope="session", autouse=True)
def compiled_and_executed_program():
    assert os.path.isfile(SOURCE), f"C++ source file {SOURCE} does not exist."
    assert os.path.exists(DB), f"Database {DB} does not exist."

    drop_index()
    shutil.copy2(DB, ORIGINAL_DB)
    build_trace_shim()
    subprocess.run(
        ["g++", "-std=c++17", SOURCE, "-o", BINARY, "-lsqlite3"],
        check=True, timeout=30, capture_output=True, text=True
    )
    run_program(clear_trace=True)
    yield

    # Leave the original database and requested final output in place.
    shutil.copy2(ORIGINAL_DB, DB)
    try:
        run_program(clear_trace=False)
    except Exception:
        pass


def test_cpp_file_exists():
    """Check if the C++ source file was created."""
    assert os.path.exists(SOURCE), f"C++ source file {SOURCE} does not exist."


def test_index_created():
    """Check if the query optimization index was created in the database."""
    assert os.path.exists(DB), f"Database {DB} does not exist."
    conn = sqlite3.connect(DB)
    result = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_parent_id'"
    ).fetchone()
    columns = [row[2] for row in conn.execute("PRAGMA index_info('idx_parent_id')")]
    conn.close()
    assert result is not None, "Index 'idx_parent_id' was not created in the database."
    assert columns == ["parent_id"], "Index 'idx_parent_id' must index the parent_id column."


def test_orphaned_size_file():
    """Check if the output file exists and contains the correct sum."""
    assert os.path.exists(OUTPUT), f"Output file {OUTPUT} does not exist."
    with open(OUTPUT, "r") as f:
        content = f.read().strip()
    assert content == "2150", f"Expected sum '2150' in {OUTPUT}, but got '{content}'."


def test_program_executed_required_sql():
    assert os.path.exists(TRACE), "No SQLite statements were observed while running the program."
    trace = open(TRACE, "r").read().lower()
    statements = trace.split("--end-sql--")

    create_positions = [
        i for i, sql in enumerate(statements)
        if re.search(r"\bcreate\s+(?:unique\s+)?index\b", sql)
        and "idx_parent_id" in sql and "parent_id" in sql
    ]
    recursive_positions = [
        i for i, sql in enumerate(statements)
        if re.search(r"\bwith\s+recursive\b", sql)
        and re.search(r"\bsum\s*\(", sql)
        and "backups" in sql
    ]
    assert create_positions, "The program did not execute SQL creating idx_parent_id on parent_id."
    assert recursive_positions, "The program did not execute a recursive CTE aggregation over backups."
    assert min(create_positions) < min(recursive_positions), "The index must be created before the recursive query."


def expected_orphan_sum(rows):
    by_id = {row[0]: row for row in rows}
    total = 0
    for backup_id, parent_id, size, status in rows:
        if status != "active":
            continue
        current = backup_id
        seen = set()
        valid = False
        while True:
            if current in seen:
                break
            seen.add(current)
            row = by_id.get(current)
            if row is None:
                break
            parent = row[1]
            if parent is None:
                valid = row[3] == "active"
                break
            current = parent
        if not valid:
            total += size
    return total


def install_fixture(rows):
    if os.path.exists(DB):
        os.remove(DB)
    conn = sqlite3.connect(DB)
    conn.execute("CREATE TABLE backups(id INTEGER PRIMARY KEY, parent_id INTEGER, size_bytes INTEGER, status TEXT)")
    conn.executemany("INSERT INTO backups VALUES (?, ?, ?, ?)", rows)
    conn.commit()
    conn.close()


def make_random_fixture():
    rng = secrets.SystemRandom()
    ids = rng.sample(range(10000, 90000), 12)
    sizes = [rng.randrange(17, 5000) for _ in range(12)]
    missing = rng.randrange(100000, 200000)
    return [
        (ids[0], None, sizes[0], "active"),
        (ids[1], ids[0], sizes[1], "active"),
        (ids[2], ids[1], sizes[2], "active"),
        (ids[3], None, sizes[3], "deleted"),
        (ids[4], ids[3], sizes[4], "active"),
        (ids[5], ids[4], sizes[5], "active"),
        (ids[6], missing, sizes[6], "active"),
        (ids[7], ids[6], sizes[7], "active"),
        (ids[8], ids[9], sizes[8], "active"),
        (ids[9], ids[8], sizes[9], "active"),
        (ids[10], ids[0], sizes[10], "deleted"),
        (ids[11], None, sizes[11], "active"),
    ]


def test_program_handles_unseen_database_contents():
    # Runtime-randomized IDs and sizes prevent a fixed answer from passing.
    for _ in range(2):
        rows = make_random_fixture()
        expected = expected_orphan_sum(rows)
        install_fixture(rows)
        run_program(clear_trace=False)

        assert os.path.exists(OUTPUT), "Program did not create orphaned_size.txt."
        with open(OUTPUT, "r") as f:
            content = f.read().strip()
        assert content == str(expected), f"Expected runtime-derived sum {expected}, got {content!r}."

        conn = sqlite3.connect(DB)
        index = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_parent_id'"
        ).fetchone()
        columns = [row[2] for row in conn.execute("PRAGMA index_info('idx_parent_id')")]
        conn.close()
        assert index is not None, "Program did not create idx_parent_id on a fresh database."
        assert columns == ["parent_id"], "idx_parent_id does not index parent_id."

    shutil.copy2(ORIGINAL_DB, DB)
    run_program(clear_trace=False)
    with open(OUTPUT, "r") as f:
        assert f.read().strip() == "2150"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

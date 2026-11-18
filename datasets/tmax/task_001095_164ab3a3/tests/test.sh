#!/bin/bash
set -u
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_task.py
import os
import random
import shutil
import sqlite3
import struct
import subprocess
import tempfile
import traceback

HOME = "/home/user"
SOURCE = os.path.join(HOME, "fetch_team.cpp")
BINARY = os.path.join(HOME, "fetch_team")
DATABASE = os.path.join(HOME, "org_chart.db")
OUTPUT = os.path.join(HOME, "team_output.txt")
PLAN = os.path.join(HOME, "query_plan.txt")
TRACE = "/tmp/fetch_team_sql.trace"
PRELOAD_SRC = "/tmp/sqlite_trace.cpp"
PRELOAD_SO = "/tmp/sqlite_trace.so"

ORIGINAL_LINES = [
    "2,Bob,VP",
    "3,Charlie,VP",
    "4,Dave,Manager",
    "5,Eve,Manager",
    "6,Frank,Engineer",
]

PRELOAD_CODE = r'''
#include <sqlite3.h>
#include <dlfcn.h>
#include <stdint.h>
#include <stdio.h>
#include <string.h>

static void log_sql(const char *sql, int n) {
    if (!sql) return;
    uint64_t len = n < 0 ? (uint64_t)strlen(sql) : (uint64_t)n;
    FILE *f = fopen("/tmp/fetch_team_sql.trace", "ab");
    if (!f) return;
    fwrite(&len, sizeof(len), 1, f);
    fwrite(sql, 1, (size_t)len, f);
    fclose(f);
}

extern "C" int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int n,
                                  sqlite3_stmt **stmt, const char **tail) {
    typedef int (*fn_t)(sqlite3*, const char*, int, sqlite3_stmt**, const char**);
    static fn_t real_fn = (fn_t)dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    log_sql(sql, n);
    return real_fn(db, sql, n, stmt, tail);
}

extern "C" int sqlite3_prepare_v3(sqlite3 *db, const char *sql, int n,
                                  unsigned int flags, sqlite3_stmt **stmt,
                                  const char **tail) {
    typedef int (*fn_t)(sqlite3*, const char*, int, unsigned int,
                        sqlite3_stmt**, const char**);
    static fn_t real_fn = (fn_t)dlsym(RTLD_NEXT, "sqlite3_prepare_v3");
    log_sql(sql, n);
    return real_fn(db, sql, n, flags, stmt, tail);
}

extern "C" int sqlite3_prepare(sqlite3 *db, const char *sql, int n,
                               sqlite3_stmt **stmt, const char **tail) {
    typedef int (*fn_t)(sqlite3*, const char*, int, sqlite3_stmt**, const char**);
    static fn_t real_fn = (fn_t)dlsym(RTLD_NEXT, "sqlite3_prepare");
    log_sql(sql, n);
    return real_fn(db, sql, n, stmt, tail);
}

extern "C" int sqlite3_exec(sqlite3 *db, const char *sql,
                            int (*callback)(void*,int,char**,char**),
                            void *arg, char **errmsg) {
    typedef int (*fn_t)(sqlite3*, const char*,
                        int (*)(void*,int,char**,char**), void*, char**);
    static fn_t real_fn = (fn_t)dlsym(RTLD_NEXT, "sqlite3_exec");
    log_sql(sql, -1);
    return real_fn(db, sql, callback, arg, errmsg);
}
'''

def run_checked(args, **kwargs):
    result = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, **kwargs)
    assert result.returncode == 0, (
        f"Command failed ({result.returncode}): {args}\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    return result


def read_output_lines():
    assert os.path.isfile(OUTPUT), (
        f"File {OUTPUT} does not exist. Did you run the compiled C++ program?"
    )
    with open(OUTPUT, "r", encoding="utf-8") as f:
        return f.read().strip().splitlines()


def parse_trace():
    assert os.path.isfile(TRACE), "The program did not submit any SQL to SQLite."
    data = open(TRACE, "rb").read()
    statements = []
    pos = 0
    while pos < len(data):
        assert pos + 8 <= len(data), "Malformed SQL trace."
        length = struct.unpack_from("=Q", data, pos)[0]
        pos += 8
        assert pos + length <= len(data), "Malformed SQL trace."
        statements.append(data[pos:pos + length].decode("utf-8"))
        pos += length
    return statements


def query_rows(db_path, sql):
    con = sqlite3.connect(db_path)
    try:
        cur = con.execute(sql)
        rows = cur.fetchall()
        assert len(cur.description or ()) == 3, (
            "The recursive query must return exactly id, name, and role."
        )
        return [(str(row[0]), str(row[1]), str(row[2])) for row in rows]
    finally:
        con.close()


def make_dynamic_database(path):
    base = random.SystemRandom().randrange(10000, 900000)
    alice = base + 71
    rows = [
        (alice, None, "Alice", "Chief"),
        (base + 901, alice, "Quinn", "Director"),
        (base + 113, alice, "Riley", "Lead"),
        (base + 777, base + 901, "Sasha", "Manager"),
        (base + 205, base + 113, "Taylor", "Manager"),
        (base + 609, base + 205, "Uma", "Engineer"),
        (base + 5, None, "Outside", "CEO"),
        (base + 6, base + 5, "NotInTeam", "Engineer"),
    ]
    random.SystemRandom().shuffle(rows)
    con = sqlite3.connect(path)
    try:
        con.execute("CREATE TABLE nodes(id INTEGER PRIMARY KEY, parent_id INTEGER, name TEXT, role TEXT)")
        con.executemany("INSERT INTO nodes VALUES(?,?,?,?)", rows)
        con.commit()
    finally:
        con.close()

    descendants = [row for row in rows if row[2] in {
        "Quinn", "Riley", "Sasha", "Taylor", "Uma"
    }]
    descendants.sort(key=lambda row: row[0])
    expected_lines = [f"{row[0]},{row[2]},{row[3]}" for row in descendants]
    expected_rows = [(str(row[0]), row[2], row[3]) for row in descendants]
    return expected_lines, expected_rows


def main():
    assert os.path.isfile(SOURCE), f"Missing source file: {SOURCE}"
    assert os.path.isfile(DATABASE), f"Missing database: {DATABASE}"

    with open(PRELOAD_SRC, "w", encoding="utf-8") as f:
        f.write(PRELOAD_CODE)
    run_checked(["g++", "-shared", "-fPIC", PRELOAD_SRC, "-ldl", "-o", PRELOAD_SO])

    if os.path.exists(BINARY):
        os.remove(BINARY)
    # Compile the submitted source using the command required by the task.
    run_checked(["g++", SOURCE, "-lsqlite3", "-o", BINARY])
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), (
        "Compilation did not produce an executable /home/user/fetch_team."
    )

    if os.path.exists(TRACE):
        os.remove(TRACE)
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    env = os.environ.copy()
    env["LD_PRELOAD"] = PRELOAD_SO
    run_checked([BINARY], env=env)

    # Preserve the original exact output assertion, now against freshly executed code.
    original_content = read_output_lines()
    assert original_content == ORIGINAL_LINES, (
        f"Content of {OUTPUT} does not match expected output. "
        f"Expected: {ORIGINAL_LINES}, but got: {original_content}"
    )

    statements = parse_trace()
    recursive_candidates = [
        sql for sql in statements
        if "WITH" in sql.upper() and "RECURSIVE" in sql.upper()
    ]
    assert recursive_candidates, (
        "The executed program did not submit a WITH RECURSIVE query to SQLite."
    )

    expected_original_rows = [tuple(line.split(",", 2)) for line in ORIGINAL_LINES]
    valid_candidates = []
    for sql in recursive_candidates:
        try:
            rows = query_rows(DATABASE, sql)
            explain_rows = sqlite3.connect(DATABASE).execute(
                "EXPLAIN QUERY PLAN " + sql
            ).fetchall()
            details = "\n".join(str(row[3]) for row in explain_rows).upper()
            if rows == expected_original_rows and "RECURSIVE STEP" in details:
                valid_candidates.append(sql)
        except sqlite3.Error:
            pass
    assert valid_candidates, (
        "No executed WITH RECURSIVE query both produced the required rows and "
        "contained an actual recursive step."
    )
    query = valid_candidates[0]

    # Preserve the original query-plan assertions.
    assert os.path.isfile(PLAN), (
        f"File {PLAN} does not exist. Did you save the EXPLAIN QUERY PLAN output?"
    )
    with open(PLAN, "r", encoding="utf-8") as f:
        submitted_plan = f.read()
    upper_plan = submitted_plan.upper()
    assert "SCAN" in upper_plan or "SEARCH" in upper_plan, (
        f"{PLAN} does not seem to contain a valid EXPLAIN QUERY PLAN output "
        "(missing SCAN or SEARCH)."
    )
    assert "NODES" in upper_plan, (
        f"{PLAN} does not seem to contain a valid EXPLAIN QUERY PLAN output "
        "(missing reference to 'nodes' table)."
    )

    actual_plan = run_checked([
        "sqlite3", DATABASE, "EXPLAIN QUERY PLAN " + query
    ]).stdout
    assert submitted_plan.strip() == actual_plan.strip(), (
        "query_plan.txt is not the verbatim sqlite3 CLI EXPLAIN QUERY PLAN "
        "output for the recursive query executed by fetch_team.cpp."
    )

    backup = tempfile.mktemp(prefix="org_chart_backup_", suffix=".db")
    dynamic = tempfile.mktemp(prefix="org_chart_dynamic_", suffix=".db")
    shutil.copy2(DATABASE, backup)
    try:
        expected_lines, expected_rows = make_dynamic_database(dynamic)
        os.replace(dynamic, DATABASE)
        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)
        run_checked([BINARY], env=env)
        dynamic_content = read_output_lines()
        assert dynamic_content == expected_lines, (
            "The compiled program did not compute Alice's descendants on an "
            f"independent hierarchy. Expected {expected_lines}, got {dynamic_content}."
        )
        assert query_rows(DATABASE, query) == expected_rows, (
            "The executed recursive SQL itself does not return all and only "
            "Alice's descendants ordered by id."
        )
    finally:
        if os.path.exists(backup):
            os.replace(backup, DATABASE)

    # Leave the required output corresponding to the restored task database.
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    run_checked([BINARY])
    assert read_output_lines() == ORIGINAL_LINES


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

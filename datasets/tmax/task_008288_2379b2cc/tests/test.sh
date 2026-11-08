#!/bin/bash
mkdir -p /logs/verifier

cat > /tmp/sqlite_trace.c <<'TRACE_EOF'
#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void log_sql(const char *sql) {
    const char *path = getenv("SQL_TRACE_FILE");
    if (!path || !sql) return;
    int fd = open(path, O_CREAT | O_WRONLY | O_APPEND, 0666);
    if (fd < 0) return;
    write(fd, sql, strlen(sql));
    write(fd, "\n", 1);
    close(fd);
}

int sqlite3_exec(sqlite3 *db, const char *sql,
                 int (*callback)(void*,int,char**,char**),
                 void *arg, char **errmsg) {
    static int (*real_fn)(sqlite3*,const char*,int(*)(void*,int,char**,char**),void*,char**);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_exec");
    log_sql(sql);
    return real_fn(db, sql, callback, arg, errmsg);
}

int sqlite3_prepare(sqlite3 *db, const char *sql, int n,
                    sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3*,const char*,int,sqlite3_stmt**,const char**);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare");
    log_sql(sql);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int n,
                       sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3*,const char*,int,sqlite3_stmt**,const char**);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    log_sql(sql);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v3(sqlite3 *db, const char *sql, int n,
                       unsigned int flags, sqlite3_stmt **stmt,
                       const char **tail) {
    static int (*real_fn)(sqlite3*,const char*,int,unsigned int,sqlite3_stmt**,const char**);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v3");
    log_sql(sql);
    return real_fn(db, sql, n, flags, stmt, tail);
}
TRACE_EOF

if ! gcc -shared -fPIC /tmp/sqlite_trace.c -o /tmp/sqlite_trace.so -ldl; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat > /tmp/test_final_state.py <<'TEST_EOF'
import json
import os
import random
import re
import secrets
import sqlite3
import subprocess

SOURCE = "/home/user/process_datasets.c"
INPUT = "/home/user/datasets.jsonl"
DB = "/home/user/research.db"
RESULT = "/home/user/result.txt"
BINARY = "/tmp/process_datasets_submission"
TRACE = "/tmp/process_datasets_sql.trace"
PRELOAD = "/tmp/sqlite_trace.so"

ORIGINAL = [
    {"id": 1, "parent_id": None, "name": "Science", "size": 0},
    {"id": 2, "parent_id": 1, "name": "Physics", "size": 100},
    {"id": 3, "parent_id": 1, "name": "Biology", "size": 200},
    {"id": 4, "parent_id": 2, "name": "Astrophysics", "size": 50},
    {"id": 5, "parent_id": 4, "name": "Stellar Dynamics", "size": 500},
    {"id": 6, "parent_id": 4, "name": "Cosmology", "size": 300},
    {"id": 7, "parent_id": 6, "name": "Dark Matter", "size": 150},
    {"id": 8, "parent_id": 3, "name": "Genetics", "size": 400},
]


def write_input(records):
    with open(INPUT, "w", encoding="utf-8") as f:
        for record in records:
            f.write(json.dumps(record, separators=(",", ":")) + "\n")


def expected_total(records):
    roots = [r["id"] for r in records if r["name"] == "Astrophysics"]
    assert len(roots) == 1
    wanted = set(roots)
    changed = True
    while changed:
        changed = False
        for record in records:
            if record["parent_id"] in wanted and record["id"] not in wanted:
                wanted.add(record["id"])
                changed = True
    return sum(r["size"] for r in records if r["id"] in wanted)


def make_case():
    ids = set()
    while len(ids) < 11:
        ids.add(secrets.randbelow(900000) + 10000)
    ids = list(ids)
    records = [
        {"id": ids[0], "parent_id": None, "name": "Root_" + secrets.token_hex(3), "size": secrets.randbelow(300) + 1},
        {"id": ids[1], "parent_id": ids[0], "name": "Astrophysics", "size": secrets.randbelow(7000) + 1},
        {"id": ids[2], "parent_id": ids[1], "name": "Child_A_" + secrets.token_hex(2), "size": secrets.randbelow(7000) + 1},
        {"id": ids[3], "parent_id": ids[1], "name": "Child_B_" + secrets.token_hex(2), "size": secrets.randbelow(7000) + 1},
        {"id": ids[4], "parent_id": ids[2], "name": "Grandchild_" + secrets.token_hex(2), "size": secrets.randbelow(7000) + 1},
        {"id": ids[5], "parent_id": ids[4], "name": "Deep_" + secrets.token_hex(2), "size": secrets.randbelow(7000) + 1},
        {"id": ids[6], "parent_id": ids[0], "name": "Unrelated_" + secrets.token_hex(2), "size": secrets.randbelow(7000) + 1},
        {"id": ids[7], "parent_id": ids[6], "name": "Outside_" + secrets.token_hex(2), "size": secrets.randbelow(7000) + 1},
        {"id": ids[8], "parent_id": None, "name": "OtherRoot_" + secrets.token_hex(2), "size": secrets.randbelow(7000) + 1},
        {"id": ids[9], "parent_id": ids[8], "name": "Astrophysics Archive", "size": secrets.randbelow(7000) + 1},
        {"id": ids[10], "parent_id": ids[3], "name": "Leaf_" + secrets.token_hex(2), "size": secrets.randbelow(7000) + 1},
    ]
    random.SystemRandom().shuffle(records)
    return records


def assert_database(records):
    assert os.path.isfile(DB), f"Database file {DB} does not exist."
    conn = sqlite3.connect(DB)
    try:
        cur = conn.cursor()
        cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='datasets';")
        assert cur.fetchone() is not None, "Table 'datasets' does not exist in the database."

        cur.execute("PRAGMA table_info(datasets)")
        columns = {row[1] for row in cur.fetchall()}
        assert {"id", "parent_id", "name", "size"}.issubset(columns), "The datasets table is missing required columns."

        cur.execute("SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='datasets';")
        indexes = cur.fetchall()
        assert len(indexes) >= 1, "No index created on 'datasets' table."

        cur.execute("SELECT count(*) FROM datasets;")
        count = cur.fetchone()[0]
        assert count > 0, "No data inserted into 'datasets' table."
        assert count == len(records), f"Expected all {len(records)} input records, found {count}."

        index_on_parent_id = False
        for (idx_name,) in indexes:
            safe_name = idx_name.replace("'", "''")
            cur.execute(f"PRAGMA index_info('{safe_name}');")
            if any(col[2] == "parent_id" for col in cur.fetchall()):
                index_on_parent_id = True
                break
        assert index_on_parent_id, "No index found specifically on the 'parent_id' column."

        cur.execute("SELECT id, parent_id, name, size FROM datasets ORDER BY id")
        actual = cur.fetchall()
        expected = sorted(
            [(r["id"], r["parent_id"], r["name"], r["size"]) for r in records],
            key=lambda row: row[0],
        )
        assert actual == expected, "The database does not contain exactly all JSONL records."
    finally:
        conn.close()


def run_case(records, original=False):
    write_input(records)
    for path in (DB, RESULT, TRACE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env["LD_PRELOAD"] = PRELOAD
    env["SQL_TRACE_FILE"] = TRACE
    completed = subprocess.run(
        [BINARY], cwd="/home/user", env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert completed.returncode == 0, (
        f"C program exited with {completed.returncode}. stderr: {completed.stderr}"
    )

    assert os.path.isfile(RESULT), f"File {RESULT} does not exist."
    with open(RESULT, "r", encoding="utf-8") as f:
        content = f.read().strip()
    assert re.fullmatch(r"[+-]?\d+", content), "result.txt must contain a single integer."
    expected = expected_total(records)
    assert int(content) == expected, f"Incorrect sum: expected {expected}, got {content}."
    if original:
        assert content == "1000", f"Incorrect sum in {RESULT}. Expected '1000', got '{content}'."

    assert_database(records)
    assert os.path.isfile(TRACE), "No SQLite statements were executed by the program."
    with open(TRACE, "r", encoding="utf-8", errors="replace") as f:
        sql = f.read()
    assert re.search(r"\bWITH\s+RECURSIVE\b", sql, re.IGNORECASE), (
        "The executed SQLite statements did not include a recursive CTE."
    )


def test_complete_program():
    assert os.path.isfile(SOURCE), f"C source file {SOURCE} does not exist."
    assert os.path.getsize(SOURCE) > 0, "C source file is empty."

    build = subprocess.run(
        ["gcc", SOURCE, "-o", BINARY, "-lsqlite3", "-ljson-c"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert build.returncode == 0, f"C source did not compile: {build.stderr}"

    saved_input = None
    if os.path.exists(INPUT):
        with open(INPUT, "rb") as f:
            saved_input = f.read()
    try:
        run_case(make_case())
        run_case(make_case())
        # Run the supplied dataset last, preserving the original expected final state.
        run_case(ORIGINAL, original=True)
    finally:
        if saved_input is not None:
            with open(INPUT, "wb") as f:
                f.write(saved_input)
        else:
            write_input(ORIGINAL)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

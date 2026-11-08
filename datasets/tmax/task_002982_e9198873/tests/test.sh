#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TRACE_EOF' > /tmp/sqlite_trace.c
#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void log_text(const char *kind, const char *text, int n) {
    const char *path = getenv("SQLITE_TRACE_FILE");
    if (!path) return;
    FILE *f = fopen(path, "a");
    if (!f) return;
    fprintf(f, "@@%s@@\n", kind);
    if (text) {
        if (n >= 0) fwrite(text, 1, (size_t)n, f);
        else fputs(text, f);
    }
    fputs("\n@@END@@\n", f);
    fclose(f);
}

int sqlite3_open(const char *filename, sqlite3 **db) {
    static int (*real_fn)(const char *, sqlite3 **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_open");
    log_text("OPEN", filename, -1);
    return real_fn(filename, db);
}

int sqlite3_open_v2(const char *filename, sqlite3 **db, int flags, const char *vfs) {
    static int (*real_fn)(const char *, sqlite3 **, int, const char *) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_open_v2");
    log_text("OPEN", filename, -1);
    return real_fn(filename, db, flags, vfs);
}

int sqlite3_exec(sqlite3 *db, const char *sql, int (*callback)(void *, int, char **, char **), void *arg, char **errmsg) {
    static int (*real_fn)(sqlite3 *, const char *, int (*)(void *, int, char **, char **), void *, char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_exec");
    log_text("SQL", sql, -1);
    return real_fn(db, sql, callback, arg, errmsg);
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    log_text("SQL", sql, n);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v3(sqlite3 *db, const char *sql, int n, unsigned int flags, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, unsigned int, sqlite3_stmt **, const char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v3");
    log_text("SQL", sql, n);
    return real_fn(db, sql, n, flags, stmt, tail);
}
TRACE_EOF

build_ok=1
gcc -shared -fPIC /tmp/sqlite_trace.c -o /tmp/sqlite_trace.so -ldl -lsqlite3 >/tmp/trace_build.log 2>&1 || build_ok=0
g++ -std=c++17 /home/user/process_data.cpp -o /home/user/process_data -lsqlite3 >/tmp/program_build.log 2>&1 || build_ok=0

if [ "$build_ok" -ne 1 ]; then
    cat /tmp/trace_build.log /tmp/program_build.log 2>/dev/null || true
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import random
import re
import secrets
import subprocess

CSV_PATH = "/home/user/transactions.csv"
JSON_PATH = "/home/user/summary.json"
EXE_PATH = "/home/user/process_data"
TRACE_PATH = "/tmp/process_sqlite.trace"

ORIGINAL_ROWS = [
    (1, "U2", 1620000001, "Clothing", 50.00),
    (2, "U1", 1620000002, "Electronics", 200.00),
    (3, "U1", 1620000003, "Books", 25.50),
    (4, "U2", 1620000004, "Clothing", 75.00),
    (5, "U1", 1620000005, "Electronics", 150.00),
    (6, "U3", 1620000006, "Home", 300.00),
    (7, "U1", 1620000007, "Books", 40.00),
    (8, "U2", 1620000008, "Home", 120.00),
]


def write_csv(rows):
    with open(CSV_PATH, "w", encoding="utf-8") as f:
        for transaction_id, user_id, timestamp, category, amount in rows:
            f.write(f"{transaction_id},{user_id},{timestamp},{category},{amount:.2f}\n")


def verify_sqlite_trace():
    assert os.path.isfile(TRACE_PATH), "The program did not invoke the traced SQLite API."
    trace = open(TRACE_PATH, encoding="utf-8", errors="replace").read()
    upper = trace.upper()
    assert re.search(r"@@OPEN@@\s*:MEMORY:\s*@@END@@", upper), \
        "The program must open an in-memory SQLite database using :memory:."

    chunks = [chunk.upper() for chunk in trace.split("@@END@@") if "@@SQL@@" in chunk]
    assert any(re.search(r"CREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?TRANSACTIONS\b", q) for q in chunks), \
        "No executed SQL created the transactions table."
    assert any(re.search(r"INSERT\s+INTO\s+TRANSACTIONS\b", q) for q in chunks), \
        "No executed SQL inserted rows into the transactions table."

    window_queries = [q for q in chunks if re.search(r"\bSELECT\b", q)]
    assert any(
        re.search(r"SUM\s*\([^)]*AMOUNT[^)]*\)\s*OVER\s*\(", q, re.S)
        and re.search(r"ROW_NUMBER\s*\(\s*\)\s*OVER\s*\(", q, re.S)
        and re.search(r"PARTITION\s+BY", q)
        and re.search(r"ORDER\s+BY", q)
        and "USER_ID" in q
        and "CATEGORY" in q
        and "TIMESTAMP" in q
        for q in window_queries
    ), "No executed SELECT used the required SUM and ROW_NUMBER SQLite window functions."


def run_program(rows):
    write_csv(rows)
    for path in (JSON_PATH, TRACE_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env["LD_PRELOAD"] = "/tmp/sqlite_trace.so"
    env["SQLITE_TRACE_FILE"] = TRACE_PATH
    result = subprocess.run(
        [EXE_PATH], cwd="/home/user", env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert result.returncode == 0, \
        f"process_data exited with {result.returncode}. stderr: {result.stderr}"
    verify_sqlite_trace()
    assert os.path.isfile(JSON_PATH), f"File {JSON_PATH} is missing. Did you generate the output?"
    try:
        with open(JSON_PATH, "r", encoding="utf-8") as f:
            return json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f"{JSON_PATH} is not a valid JSON file: {exc}")


def expected_for(rows):
    grouped = {}
    for _, user_id, timestamp, category, amount in rows:
        grouped.setdefault(user_id, []).append((timestamp, category, amount))

    expected = []
    for user_id in sorted(grouped):
        running = 0.0
        maximum = None
        categories = set()
        for timestamp, category, amount in sorted(grouped[user_id], key=lambda row: row[0]):
            running += amount
            maximum = running if maximum is None else max(maximum, running)
            categories.add(category)
        expected.append({
            "user_id": user_id,
            "total_spent": maximum,
            "top_categories": sorted(categories),
        })
    return expected


def assert_matches(data, expected):
    assert isinstance(data, list), f"Expected the JSON root to be a list, got {type(data).__name__}."
    assert len(data) == len(expected), f"Expected {len(expected)} user objects, got {len(data)}."
    assert [obj.get("user_id") for obj in data] == [obj["user_id"] for obj in expected], \
        "JSON users are missing or not sorted alphabetically by user_id."
    for actual, wanted in zip(data, expected):
        assert isinstance(actual, dict), "Each JSON array element must be an object."
        assert set(actual) == {"user_id", "total_spent", "top_categories"}, \
            f"Unexpected object structure for {wanted['user_id']}: {actual}"
        total = actual["total_spent"]
        assert isinstance(total, (int, float)) and not isinstance(total, bool), \
            f"total_spent for {wanted['user_id']} must be numeric."
        assert math.isclose(total, wanted["total_spent"], rel_tol=1e-7, abs_tol=1e-7), \
            f"Wrong total_spent for {wanted['user_id']}: {total}"
        assert actual["top_categories"] == wanted["top_categories"], \
            f"Wrong top_categories for {wanted['user_id']}: {actual['top_categories']}"


def test_cpp_files_exist():
    cpp_path = "/home/user/process_data.cpp"
    exe_path = "/home/user/process_data"

    assert os.path.isfile(cpp_path), f"C++ source file {cpp_path} is missing."
    assert os.path.isfile(exe_path), f"Compiled executable {exe_path} is missing."
    assert os.access(exe_path, os.X_OK), f"File {exe_path} is not executable."
    source = open(cpp_path, encoding="utf-8", errors="replace").read()
    assert re.search(r"#\s*include\s*[<\"]sqlite3\.h[>\"]", source), \
        "process_data.cpp must use the SQLite3 C API."


def test_summary_json_exists_and_correct():
    data = run_program(ORIGINAL_ROWS)

    assert isinstance(data, list), f"Expected the JSON root to be a list, got {type(data).__name__}."
    assert len(data) == 3, f"Expected 3 user objects in the JSON array, got {len(data)}."

    user_ids = [obj.get("user_id") for obj in data]
    assert user_ids == ["U1", "U2", "U3"], f"Expected user_ids to be sorted ['U1', 'U2', 'U3'], got {user_ids}."

    expected_data = {
        "U1": {"total_spent": 415.5, "top_categories": ["Books", "Electronics"]},
        "U2": {"total_spent": 245.0, "top_categories": ["Clothing", "Home"]},
        "U3": {"total_spent": 300.0, "top_categories": ["Home"]},
    }

    for obj in data:
        user_id = obj.get("user_id")
        assert user_id in expected_data, f"Unexpected user_id: {user_id}"
        expected = expected_data[user_id]
        total_spent = obj.get("total_spent")
        assert total_spent is not None, f"Missing 'total_spent' for user {user_id}"
        assert isinstance(total_spent, (int, float)), f"'total_spent' for user {user_id} should be a number."
        assert math.isclose(total_spent, expected["total_spent"], rel_tol=1e-5), \
            f"Expected total_spent for {user_id} to be {expected['total_spent']}, got {total_spent}."
        top_categories = obj.get("top_categories")
        assert top_categories is not None, f"Missing 'top_categories' for user {user_id}"
        assert isinstance(top_categories, list), f"'top_categories' for user {user_id} should be a list."
        assert top_categories == expected["top_categories"], \
            f"Expected top_categories for {user_id} to be {expected['top_categories']}, got {top_categories}."


def test_program_on_unseen_csv():
    rng = random.Random(secrets.randbits(64))
    token = secrets.token_hex(3).upper()
    users = [f"A_{token}", f"M_{token}", f"Z_{token}"]
    categories = [f"Books_{token}", f"Garden_{token}", f"Tech_{token}", f"Toys_{token}"]
    rows = []
    transaction_id = 9000 + rng.randrange(1000)
    timestamp = 1800000000 + rng.randrange(100000)

    for user_index, user_id in enumerate(users):
        count = 4 + user_index
        for i in range(count):
            category = categories[(i * 2 + user_index) % len(categories)]
            amount = rng.randint(-2500, 15000) / 100.0
            rows.append((transaction_id, user_id, timestamp, category, amount))
            transaction_id += 1
            timestamp += rng.randint(2, 19)

    rng.shuffle(rows)
    data = run_program(rows)
    assert_matches(data, expected_for(rows))
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

#!/bin/bash
mkdir -p /logs/verifier

cat > /tmp/sqlite_trace.c <<'TRACE_EOF'
#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <pthread.h>

static pthread_mutex_t log_lock = PTHREAD_MUTEX_INITIALIZER;

static void log_hex(FILE *f, const unsigned char *s, size_t n) {
    size_t i;
    for (i = 0; i < n; i++) fprintf(f, "%02x", s[i]);
}

static void log_prepare(sqlite3_stmt *stmt, const char *sql, int nByte) {
    const char *path = getenv("SQLITE_TRACE_FILE");
    if (!path || !sql) return;
    size_t n = (nByte < 0) ? strlen(sql) : strnlen(sql, (size_t)nByte);
    pthread_mutex_lock(&log_lock);
    FILE *f = fopen(path, "a");
    if (f) {
        fprintf(f, "P|%p|", (void *)stmt);
        log_hex(f, (const unsigned char *)sql, n);
        fputc('\n', f);
        fclose(f);
    }
    pthread_mutex_unlock(&log_lock);
}

static void log_bind(sqlite3_stmt *stmt, int index, const char *value, int n) {
    const char *path = getenv("SQLITE_TRACE_FILE");
    if (!path || !value) return;
    size_t len = (n < 0) ? strlen(value) : (size_t)n;
    pthread_mutex_lock(&log_lock);
    FILE *f = fopen(path, "a");
    if (f) {
        fprintf(f, "B|%p|%d|", (void *)stmt, index);
        log_hex(f, (const unsigned char *)value, len);
        fputc('\n', f);
        fclose(f);
    }
    pthread_mutex_unlock(&log_lock);
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int nByte,
                       sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    int rc = real_fn(db, sql, nByte, stmt, tail);
    log_prepare(stmt ? *stmt : NULL, sql, nByte);
    return rc;
}

int sqlite3_bind_text(sqlite3_stmt *stmt, int index, const char *value,
                      int n, void (*destroy)(void *)) {
    static int (*real_fn)(sqlite3_stmt *, int, const char *, int, void (*)(void *)) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_bind_text");
    log_bind(stmt, index, value, n);
    return real_fn(stmt, index, value, n, destroy);
}
TRACE_EOF

gcc -shared -fPIC /tmp/sqlite_trace.c -o /tmp/sqlite_trace.so -ldl -lpthread -lsqlite3 >/tmp/interposer_build.log 2>&1
INTERPOSER_STATUS=$?

cat > /tmp/test_final_state.py <<'TEST_EOF'
import os
import random
import re
import sqlite3
import subprocess

DB_PATH = "/home/user/ecommerce.db"
CPP_PATH = "/home/user/process.cpp"
EXE_PATH = "/home/user/process"
QUERY_PLAN_PATH = "/home/user/query_plan.txt"
CSV_PATH = "/home/user/top_clients.csv"
TRACE_PATH = "/tmp/sqlite_calls.log"
PRELOAD_PATH = "/tmp/sqlite_trace.so"


def run_process(start_date, end_date):
    open(TRACE_PATH, "w").close()
    env = os.environ.copy()
    env["SQLITE_TRACE_FILE"] = TRACE_PATH
    env["LD_PRELOAD"] = PRELOAD_PATH + ((":" + env["LD_PRELOAD"]) if env.get("LD_PRELOAD") else "")
    result = subprocess.run(
        [EXE_PATH, start_date, end_date], cwd="/home/user", env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert result.returncode == 0, (
        f"process exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def parse_trace():
    records = []
    latest = {}
    with open(TRACE_PATH, "r") as f:
        for raw in f:
            parts = raw.rstrip("\n").split("|")
            if parts[0] == "P" and len(parts) == 3:
                record = {
                    "ptr": parts[1],
                    "sql": bytes.fromhex(parts[2]).decode("utf-8", "strict"),
                    "binds": {},
                }
                records.append(record)
                latest[parts[1]] = record
            elif parts[0] == "B" and len(parts) == 4 and parts[1] in latest:
                latest[parts[1]]["binds"][int(parts[2])] = bytes.fromhex(parts[3]).decode("utf-8", "strict")
    return records


def is_analytics_sql(sql):
    normalized = " ".join(sql.lower().split())
    required = ["cart", "cart_item", "product", "sum", "quantity", "price", "checkout_date", "limit"]
    return all(token in normalized for token in required)


def bound_parameters(record):
    assert record["binds"], f"Parameterized statement had no sqlite3_bind_text calls: {record['sql']}"
    highest = max(record["binds"])
    return tuple(record["binds"].get(i) for i in range(1, highest + 1))


def validate_runtime_sql_and_plan(start_date, end_date):
    records = parse_trace()
    assert records, "The executable did not call sqlite3_prepare_v2 at runtime."

    explain_records = [
        r for r in records
        if r["sql"].lstrip().lower().startswith("explain query plan") and is_analytics_sql(r["sql"])
    ]
    query_records = [
        r for r in records
        if not r["sql"].lstrip().lower().startswith("explain") and is_analytics_sql(r["sql"])
    ]
    assert explain_records, "No parameterized EXPLAIN QUERY PLAN for the analytical query was prepared."
    assert query_records, "No parameterized analytical result query was prepared."

    for record in explain_records + query_records:
        values = list(record["binds"].values())
        assert start_date in values and end_date in values, (
            "Both command-line dates must be bound with sqlite3_bind_text to the analytical statements."
        )

    assert os.path.isfile(QUERY_PLAN_PATH), f"Query plan file {QUERY_PLAN_PATH} does not exist."
    with open(QUERY_PLAN_PATH, "r") as f:
        actual_plan = [line.rstrip("\n") for line in f]
    assert actual_plan and all(actual_plan), "query_plan.txt must contain one non-empty detail value per line."

    matched = False
    conn = sqlite3.connect(DB_PATH)
    try:
        for record in explain_records:
            try:
                rows = conn.execute(record["sql"], bound_parameters(record)).fetchall()
            except sqlite3.Error:
                continue
            expected_plan = [str(row[3]) for row in rows]
            if actual_plan == expected_plan:
                matched = True
                break
    finally:
        conn.close()
    assert matched, "query_plan.txt is not the exact detail-column output of the prepared EXPLAIN QUERY PLAN."


def read_csv():
    assert os.path.isfile(CSV_PATH), f"CSV output file {CSV_PATH} does not exist."
    actual_results = []
    with open(CSV_PATH, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(",")
            assert len(parts) == 2, f"Invalid CSV format in line: '{line}'. Expected 'client_id,total_spend'."
            client_id_str, total_spend_str = parts
            assert "." in total_spend_str and len(total_spend_str.split(".")[1]) == 2, (
                f"Total spend '{total_spend_str}' is not formatted to exactly 2 decimal places."
            )
            assert re.fullmatch(r"-?\d+\.\d{2}", total_spend_str), (
                f"Total spend '{total_spend_str}' is not a numeric value with exactly 2 decimal places."
            )
            actual_results.append((int(client_id_str), float(total_spend_str)))
    return actual_results


def expected_for_range(start_date, end_date):
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute("""
            SELECT c.client_id, SUM(ci.quantity * p.price) AS total_spend
            FROM cart AS c
            JOIN cart_item AS ci ON ci.cart_id = c.id
            JOIN product AS p ON p.id = ci.product_id
            WHERE c.checkout_date >= ? AND c.checkout_date <= ?
            GROUP BY c.client_id
            ORDER BY total_spend DESC, c.client_id ASC
            LIMIT 5
        """, (start_date, end_date)).fetchall()
        return [(int(client_id), float(f"{total:.2f}")) for client_id, total in rows]
    finally:
        conn.close()


def assert_csv_matches(expected):
    actual_results = read_csv()
    assert len(actual_results) == len(expected), (
        f"Expected {len(expected)} top clients, but found {len(actual_results)}."
    )
    expected_sorted = sorted(expected, key=lambda x: (-x[1], x[0]))
    actual_sorted = sorted(actual_results, key=lambda x: (-x[1], x[0]))
    assert actual_sorted == expected_sorted, (
        f"CSV results do not match expected values.\nExpected (sorted): {expected_sorted}\n"
        f"Actual (sorted): {actual_sorted}"
    )


def add_unpredictable_range():
    rng = random.SystemRandom()
    year = rng.randint(2050, 2090)
    start_date = f"{year}-03-10"
    end_date = f"{year}-08-20"
    inside_dates = [
        start_date, f"{year}-04-01", f"{year}-05-07", f"{year}-06-11",
        f"{year}-07-03", f"{year}-08-01", end_date,
    ]
    spends = rng.sample(range(11000, 99000, 137), 7)

    conn = sqlite3.connect(DB_PATH)
    try:
        client_base = conn.execute("SELECT COALESCE(MAX(id), 0) + 100 FROM client").fetchone()[0]
        product_base = conn.execute("SELECT COALESCE(MAX(id), 0) + 100 FROM product").fetchone()[0]
        cart_base = conn.execute("SELECT COALESCE(MAX(id), 0) + 100 FROM cart").fetchone()[0]
        item_base = conn.execute("SELECT COALESCE(MAX(id), 0) + 100 FROM cart_item").fetchone()[0]

        all_dates = inside_dates + [f"{year}-03-09", f"{year}-08-21"]
        all_spends = spends + [250000, 260000]
        for i, (date, cents) in enumerate(zip(all_dates, all_spends)):
            client_id = client_base + i
            product_id = product_base + i
            cart_id = cart_base + i
            item_id = item_base + i
            conn.execute("INSERT INTO client(id, name, join_date) VALUES (?, ?, ?)",
                         (client_id, f"verification-client-{client_id}", f"{year-1}-01-01"))
            conn.execute("INSERT INTO product(id, name, price) VALUES (?, ?, ?)",
                         (product_id, f"verification-product-{product_id}", cents / 100.0))
            conn.execute("INSERT INTO cart(id, client_id, checkout_date) VALUES (?, ?, ?)",
                         (cart_id, client_id, date))
            conn.execute("INSERT INTO cart_item(id, cart_id, product_id, quantity) VALUES (?, ?, ?, 1)",
                         (item_id, cart_id, product_id))
        conn.commit()
    finally:
        conn.close()
    return start_date, end_date


def test_complete_solution():
    # Preserve the original source/executable assertions.
    assert os.path.isfile(CPP_PATH), f"C++ source file {CPP_PATH} does not exist."
    assert os.path.isfile(EXE_PATH), f"Executable file {EXE_PATH} does not exist."
    assert os.access(EXE_PATH, os.X_OK), f"File {EXE_PATH} is not executable."
    assert os.path.isfile(PRELOAD_PATH), "Failed to build the SQLite API runtime tracer."

    source = open(CPP_PATH, "r", errors="replace").read()
    assert re.search(r"#\s*include\s*[<\"]sqlite3\.h[>\"]", source), "process.cpp does not include sqlite3.h."
    assert re.search(r"\bsqlite3_prepare_v2\s*\(", source), "process.cpp does not call sqlite3_prepare_v2."
    assert re.search(r"\bsqlite3_bind_text\s*\(", source), "process.cpp does not call sqlite3_bind_text."

    build = subprocess.run(
        ["g++", CPP_PATH, "-lsqlite3", "-o", "/tmp/process_from_source"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=30
    )
    assert build.returncode == 0, f"process.cpp does not compile with the required command:\n{build.stderr}"

    # Execute the demanded artifact for the required range.
    run_process("2023-01-01", "2023-12-31")

    # Preserve the original index assertion.
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} does not exist."
    conn = sqlite3.connect(DB_PATH)
    try:
        indexes = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_autoindex%'"
        ).fetchall()
    finally:
        conn.close()
    assert len(indexes) > 0, "No custom indexes were created in the database."

    # Preserve the original query-plan shape assertion, then verify its exact origin.
    assert os.path.isfile(QUERY_PLAN_PATH), f"Query plan file {QUERY_PLAN_PATH} does not exist."
    with open(QUERY_PLAN_PATH, "r") as f:
        content = f.read().upper()
    assert "SCAN" in content or "SEARCH" in content, (
        f"File {QUERY_PLAN_PATH} does not appear to contain valid EXPLAIN QUERY PLAN output. "
        "Expected to find 'SCAN' or 'SEARCH' operations."
    )
    validate_runtime_sql_and_plan("2023-01-01", "2023-12-31")

    # Preserve the original fixed-result assertion.
    expected_results = [
        (1, 112.50),
        (3, 105.00),
        (5, 105.00),
        (4, 60.00),
        (2, 52.50),
    ]
    assert_csv_matches(expected_results)

    # Exercise an unpredictable alternate range with boundary and out-of-range rows.
    start_date, end_date = add_unpredictable_range()
    expected_dynamic = expected_for_range(start_date, end_date)
    assert len(expected_dynamic) == 5
    run_process(start_date, end_date)
    validate_runtime_sql_and_plan(start_date, end_date)
    assert_csv_matches(expected_dynamic)
TEST_EOF

if [ "$INTERPOSER_STATUS" -eq 0 ] && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

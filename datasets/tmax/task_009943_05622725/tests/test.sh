#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'MONITOR_EOF' > /tmp/sqlite_monitor.c
#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void log_value(const char *kind, const char *value) {
    const char *path = getenv("SQLITE_MONITOR_LOG");
    if (!path) return;
    FILE *f = fopen(path, "a");
    if (!f) return;
    fprintf(f, "%s|", kind);
    if (value) {
        for (const unsigned char *p = (const unsigned char *)value; *p; ++p)
            fputc((*p == '\n' || *p == '\r' || *p == '\t') ? ' ' : *p, f);
    }
    fputc('\n', f);
    fclose(f);
}

int sqlite3_open(const char *filename, sqlite3 **db) {
    static int (*real_fn)(const char *, sqlite3 **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_open");
    int rc = real_fn(filename, db);
    if (rc == SQLITE_OK) log_value("OPEN", filename);
    return rc;
}

int sqlite3_open_v2(const char *filename, sqlite3 **db, int flags, const char *vfs) {
    static int (*real_fn)(const char *, sqlite3 **, int, const char *) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_open_v2");
    int rc = real_fn(filename, db, flags, vfs);
    if (rc == SQLITE_OK) log_value("OPEN", filename);
    return rc;
}

int sqlite3_exec(sqlite3 *db, const char *sql,
                 int (*callback)(void *, int, char **, char **),
                 void *arg, char **errmsg) {
    static int (*real_fn)(sqlite3 *, const char *, int (*)(void *, int, char **, char **), void *, char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_exec");
    int rc = real_fn(db, sql, callback, arg, errmsg);
    if (rc == SQLITE_OK) log_value("EXEC", sql);
    return rc;
}

int sqlite3_step(sqlite3_stmt *stmt) {
    static int (*real_step)(sqlite3_stmt *) = NULL;
    static const char *(*real_sql)(sqlite3_stmt *) = NULL;
    if (!real_step) real_step = dlsym(RTLD_NEXT, "sqlite3_step");
    if (!real_sql) real_sql = dlsym(RTLD_NEXT, "sqlite3_sql");
    int rc = real_step(stmt);
    if (rc == SQLITE_ROW || rc == SQLITE_DONE)
        log_value("STEP", real_sql ? real_sql(stmt) : NULL);
    return rc;
}
MONITOR_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import string
import subprocess
from collections import defaultdict


def test_report_csv_exists_and_content():
    report_path = "/home/user/report.csv"
    assert os.path.isfile(report_path), f"File {report_path} was not generated."

    expected_content = """account_id,name,max_balance
1,Root,5000
2,Branch_A,2000
3,Branch_B,2000
6,Deep_Leaf,1700
4,Leaf_A1,1500"""

    with open(report_path, "r") as f:
        content = f.read().strip()

    # Split into lines to compare robustly, ignoring trailing/leading whitespace per line
    expected_lines = [line.strip() for line in expected_content.splitlines() if line.strip()]
    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]

    assert actual_lines == expected_lines, (
        f"Content of {report_path} does not match the expected output.\n"
        f"Expected:\n{expected_content}\n"
        f"Actual:\n{content}"
    )


def test_analyze_cpp_exists():
    cpp_path = "/home/user/analyze.cpp"
    assert os.path.isfile(cpp_path), f"C++ source file {cpp_path} is missing."


def descendants(accounts):
    result = {1}
    changed = True
    while changed:
        changed = False
        for account_id, parent_id, _ in accounts:
            if parent_id in result and account_id not in result:
                result.add(account_id)
                changed = True
    return result


def expected_report(accounts, transactions):
    wanted = descendants(accounts)
    names = {account_id: name for account_id, _, name in accounts}
    balances = defaultdict(int)
    peaks = {account_id: 0 for account_id in wanted}

    for tx_id, from_id, to_id, amount, ts in sorted(transactions, key=lambda row: (row[4], row[0])):
        if from_id in wanted:
            balances[from_id] -= amount
            peaks[from_id] = max(peaks[from_id], balances[from_id])
        if to_id in wanted:
            balances[to_id] += amount
            peaks[to_id] = max(peaks[to_id], balances[to_id])

    rows = [(account_id, names[account_id], peak)
            for account_id, peak in peaks.items() if peak > 1000]
    rows.sort(key=lambda row: (-row[2], row[0]))
    lines = ["account_id,name,max_balance"]
    lines.extend(f"{account_id},{name},{peak}" for account_id, name, peak in rows)
    return "\n".join(lines)


def write_fixture(accounts, transactions):
    account_lines = ["id,parent_id,name"]
    for account_id, parent_id, name in accounts:
        parent = "" if parent_id is None else str(parent_id)
        account_lines.append(f"{account_id},{parent},{name}")
    transaction_lines = ["id,from_id,to_id,amount,ts"]
    for tx_id, from_id, to_id, amount, ts in transactions:
        transaction_lines.append(f"{tx_id},{from_id},{to_id},{amount},{ts}")
    with open("/home/user/accounts.csv", "w", newline="") as f:
        f.write("\n".join(account_lines) + "\n")
    with open("/home/user/transactions.csv", "w", newline="") as f:
        f.write("\n".join(transaction_lines) + "\n")


def assert_sqlite_pipeline(log_path):
    assert os.path.isfile(log_path), "No SQLite activity was observed while running the program."
    with open(log_path, "r", errors="replace") as f:
        lines = f.read().splitlines()

    assert any(line.strip().lower() == "open|:memory:" for line in lines), (
        "The program did not initialize an in-memory SQLite database."
    )

    executed = [line.split("|", 1)[1] for line in lines
                if (line.startswith("STEP|") or line.startswith("EXEC|")) and "|" in line]
    complex_queries = []
    for sql in executed:
        normalized = re.sub(r"/\\*.*?\\*/|--[^\n]*", " ", sql, flags=re.S).lower()
        if (re.search(r"\bwith\s+recursive\b", normalized) and
                re.search(r"\bover\b", normalized) and
                re.search(r"\bjoin\b", normalized) and
                re.search(r"\bmax\s*\(", normalized) and
                re.search(r"\baccounts\b", normalized) and
                re.search(r"\btransactions\b", normalized)):
            complex_queries.append(sql)
    assert complex_queries, (
        "No executed single SQL query was observed that combines a recursive CTE, "
        "a window function, MAX aggregation, joins, Accounts, and Transactions."
    )


def test_compiled_program_processes_unseen_inputs_with_sqlite():
    source = "/home/user/analyze.cpp"
    binary = "/home/user/analyze_verified"
    subprocess.run(
        ["g++", "-std=c++17", source, "-lsqlite3", "-o", binary],
        check=True, timeout=30, capture_output=True, text=True
    )

    rng = random.SystemRandom()
    suffix = "".join(rng.choice(string.ascii_letters) for _ in range(8))

    a = rng.randint(2200, 3900)
    b = rng.randint(1100, 1700)
    c = rng.randint(350, 850)
    d = rng.randint(1050, 1450)
    e = rng.randint(1001, 1650)
    case_one_accounts = [
        (1, None, "Root" + suffix),
        (10, 1, "Alpha" + suffix),
        (20, 1, "Beta" + suffix),
        (30, 10, "Gamma" + suffix),
        (55, 30, "Quiet" + suffix),
        (99, None, "Outside" + suffix),
    ]
    case_one_transactions = [
        (1, 99, 1, a, "2024-02-01 09:00:00"),
        (2, 1, 10, b, "2024-02-02 09:00:00"),
        (3, 99, 10, c, "2024-02-03 09:00:00"),
        (4, 10, 30, d, "2024-02-04 09:00:00"),
        (5, 99, 20, e, "2024-02-05 09:00:00"),
    ]

    f = rng.randint(2400, 3600)
    g = rng.randint(1200, 1800)
    h = rng.randint(1500, 2200)
    case_two_accounts = [
        (1, None, "HQ" + suffix),
        (4, 1, "East" + suffix),
        (7, 1, "West" + suffix),
        (11, 4, "Sub" + suffix),
        (80, None, "External" + suffix),
    ]
    # Deliberately not in chronological file order.
    case_two_transactions = [
        (30, 80, 4, h, "2025-03-03 12:00:00"),
        (10, 80, 1, f, "2025-03-01 12:00:00"),
        (40, 4, 11, rng.randint(200, 700), "2025-03-04 12:00:00"),
        (20, 1, 7, g, "2025-03-02 12:00:00"),
        (50, 7, 11, rng.randint(100, 400), "2025-03-05 12:00:00"),
    ]

    for index, (accounts, transactions) in enumerate([
        (case_one_accounts, case_one_transactions),
        (case_two_accounts, case_two_transactions),
    ]):
        write_fixture(accounts, transactions)
        report = "/home/user/report.csv"
        if os.path.exists(report):
            os.remove(report)
        log_path = f"/tmp/sqlite_monitor_{index}.log"
        if os.path.exists(log_path):
            os.remove(log_path)
        env = os.environ.copy()
        env["LD_PRELOAD"] = "/tmp/sqlite_monitor.so"
        env["SQLITE_MONITOR_LOG"] = log_path
        result = subprocess.run(
            [binary], cwd="/home/user", env=env, timeout=20,
            capture_output=True, text=True
        )
        assert result.returncode == 0, (
            f"Compiled program failed on an unseen fixture.\nstdout:\n{result.stdout}\n"
            f"stderr:\n{result.stderr}"
        )
        assert os.path.isfile(report), "Running the compiled program did not generate report.csv."
        with open(report, "r") as fobj:
            actual = fobj.read().strip()
        expected = expected_report(accounts, transactions)
        assert actual == expected, (
            f"Incorrect report for an unseen fixture.\nExpected:\n{expected}\nActual:\n{actual}"
        )
        assert_sqlite_pipeline(log_path)
TEST_EOF

if gcc -shared -fPIC /tmp/sqlite_monitor.c -o /tmp/sqlite_monitor.so -ldl -lsqlite3 2>&1 && \
   python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

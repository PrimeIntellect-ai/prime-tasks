#!/bin/bash
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/verify_audit.py
import csv
import json
import os
import re
import shutil
import stat
import subprocess
from collections import defaultdict

HOME = "/home/user"
SOURCE = HOME + "/audit_analyzer.cpp"
BINARY = HOME + "/audit_analyzer"
CSV_PATH = HOME + "/transactions.csv"
REPORT = HOME + "/audit_report.json"
TRACE = "/tmp/audit_sql_trace.log"
PRELOAD = "/tmp/libaudit_sqltrace.so"


def check_source_and_compile():
    st = os.lstat(SOURCE)
    assert stat.S_ISREG(st.st_mode), f"{SOURCE} must be a regular file"
    assert st.st_size > 0, f"{SOURCE} is empty"

    with open(SOURCE, "r", encoding="utf-8", errors="replace") as f:
        source = f.read()
    assert re.search(r"#\s*include\s*[<\"]sqlite3\.h[>\"]", source), "The program must include sqlite3.h"

    if os.path.lexists(BINARY):
        os.remove(BINARY)
    result = subprocess.run(
        ["g++", "-std=c++17", SOURCE, "-lsqlite3", "-o", BINARY],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=60
    )
    assert result.returncode == 0, "Compilation failed:\n" + result.stdout
    assert os.path.isfile(BINARY) and os.access(BINARY, os.X_OK), "Compiled analyzer is not executable"
    ldd = subprocess.run(["ldd", BINARY], text=True, stdout=subprocess.PIPE,
                         stderr=subprocess.STDOUT, timeout=10)
    assert "libsqlite3" in ldd.stdout, "Compiled analyzer is not linked to SQLite3"


def build_sql_tracer():
    tracer = r'''#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

static void record_sql(const char *sql) {
    const char *path = getenv("AUDIT_SQL_TRACE");
    if (!path || !sql) return;
    FILE *f = fopen(path, "a");
    if (!f) return;
    for (const char *p = sql; *p; ++p) {
        char c = (*p == '\n' || *p == '\r') ? ' ' : *p;
        fputc(c, f);
    }
    fputc('\n', f);
    fclose(f);
}

int sqlite3_exec(sqlite3 *db, const char *sql,
                 int (*cb)(void*,int,char**,char**), void *arg, char **err) {
    static int (*real_fn)(sqlite3*,const char*,int(*)(void*,int,char**,char**),void*,char**);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_exec");
    record_sql(sql);
    return real_fn(db, sql, cb, arg, err);
}

int sqlite3_prepare(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3*,const char*,int,sqlite3_stmt**,const char**);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare");
    record_sql(sql);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3*,const char*,int,sqlite3_stmt**,const char**);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    record_sql(sql);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v3(sqlite3 *db, const char *sql, int n, unsigned int flags,
                       sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3*,const char*,int,unsigned int,sqlite3_stmt**,const char**);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v3");
    record_sql(sql);
    return real_fn(db, sql, n, flags, stmt, tail);
}
'''
    with open("/tmp/audit_sqltrace.c", "w") as f:
        f.write(tracer)
    result = subprocess.run(
        ["gcc", "-shared", "-fPIC", "/tmp/audit_sqltrace.c", "-ldl", "-o", PRELOAD],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
    )
    assert result.returncode == 0, "Could not build SQL execution tracer:\n" + result.stdout


def write_rows(rows):
    with open(CSV_PATH, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["tx_id", "timestamp", "source_account", "target_account", "amount"])
        writer.writerows(rows)
    os.chown(CSV_PATH, 1000, 1000)
    os.chmod(CSV_PATH, 0o666)


def run_analyzer(trace=False):
    if os.path.lexists(REPORT):
        os.remove(REPORT)
    if trace and os.path.lexists(TRACE):
        os.remove(TRACE)

    env_args = ["env"]
    if trace:
        env_args += ["LD_PRELOAD=" + PRELOAD, "AUDIT_SQL_TRACE=" + TRACE]
    cmd = ["runuser", "-u", "user", "--"] + env_args + [BINARY]
    result = subprocess.run(cmd, cwd=HOME, text=True, stdout=subprocess.PIPE,
                            stderr=subprocess.STDOUT, timeout=30)
    assert result.returncode == 0, "Analyzer execution failed:\n" + result.stdout
    assert os.path.exists(REPORT), f"File {REPORT} does not exist. The C++ program may not have run successfully or failed to write the output."
    assert os.path.isfile(REPORT), f"Path {REPORT} is not a file."
    with open(REPORT, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            raise AssertionError(f"Failed to parse {REPORT} as JSON: {e}")
    return data


def assert_report_shape(data):
    assert "suspicious_accounts" in data, "The JSON output is missing the 'suspicious_accounts' key."
    assert "cycles" in data, "The JSON output is missing the 'cycles' key."
    assert isinstance(data["suspicious_accounts"], list), "'suspicious_accounts' must be a list."
    assert isinstance(data["cycles"], list), "'cycles' must be a list."


def assert_original(data):
    assert_report_shape(data)
    suspicious_accounts = data["suspicious_accounts"]
    cycles = data["cycles"]
    expected_suspicious_accounts = ["ACC123", "ACC456"]
    assert sorted(suspicious_accounts) == expected_suspicious_accounts, \
        f"Expected suspicious_accounts to be {expected_suspicious_accounts}, but got {suspicious_accounts}."
    expected_cycles = [
        ["ACC123", "ACC999", "ACC888"],
        ["ACC456", "ACC777", "ACC666"]
    ]
    sorted_actual_cycles = sorted(cycles)
    sorted_expected_cycles = sorted(expected_cycles)
    assert sorted_actual_cycles == sorted_expected_cycles, \
        f"Expected cycles to be {sorted_expected_cycles}, but got {sorted_actual_cycles}."


def expected_for(rows):
    outgoing = defaultdict(list)
    edges = set()
    for _txid, timestamp, source, target, amount in rows:
        outgoing[source].append((int(timestamp), float(amount)))
        edges.add((source, target))

    suspicious = []
    for account, values in outgoing.items():
        values.sort()
        qualifies = False
        for end, _ in values:
            total = sum(amount for timestamp, amount in values
                        if end - 86400 <= timestamp <= end)
            if total >= 50000.0:
                qualifies = True
                break
        if qualifies:
            suspicious.append(account)
    suspicious.sort()

    cycles = set()
    for a in suspicious:
        for source, b in edges:
            if source != a:
                continue
            for source2, c in edges:
                if source2 == b and (c, a) in edges:
                    cycles.add((a, b, c))
    return {"suspicious_accounts": suspicious,
            "cycles": [list(c) for c in sorted(cycles)]}


def assert_derived(data, rows):
    assert_report_shape(data)
    expected = expected_for(rows)
    assert data["suspicious_accounts"] == expected["suspicious_accounts"], \
        f"Expected suspicious_accounts {expected['suspicious_accounts']}, got {data['suspicious_accounts']}"
    assert data["cycles"] == expected["cycles"], \
        f"Expected cycles {expected['cycles']}, got {data['cycles']}"


def assert_executed_sql():
    assert os.path.isfile(TRACE), "No executed SQLite statements were observed"
    with open(TRACE, "r", errors="replace") as f:
        statements = [re.sub(r"\s+", " ", line).upper() for line in f if line.strip()]
    all_sql = "\n".join(statements)
    assert re.search(r"\bCREATE\s+(?:UNIQUE\s+)?INDEX\b", all_sql), \
        "The analyzer did not execute a CREATE INDEX statement"
    required = ["OVER", "PARTITION BY", "ORDER BY", "RANGE", "BETWEEN"]
    assert all(token in all_sql for token in required), \
        "The analyzer did not execute the required SQLite window-function query"
    graph_queries = [s for s in statements if "SELECT" in s and
                     "SOURCE_ACCOUNT" in s and "TARGET_ACCOUNT" in s and
                     ("TRANSACTIONS" in s or " JOIN " in s or "WITH RECURSIVE" in s)]
    assert graph_queries, "The analyzer did not execute a transaction graph query"


def main():
    with open(CSV_PATH, "rb") as f:
        original_csv = f.read()
    original_report = None
    try:
        check_source_and_compile()
        build_sql_tracer()

        original_data = run_analyzer(trace=True)
        assert_original(original_data)
        assert_executed_sql()
        with open(REPORT, "rb") as f:
            original_report = f.read()

        rows1 = [
            [101, 1000, "DYN_A", "P1", 30000.0],
            [102, 87400, "DYN_A", "P2", 20000.0],
            [103, 0, "DYN_B", "Q1", 30000.0],
            [104, 86401, "DYN_B", "Q2", 30000.0],
            [105, 5000, "DYN_C", "R1", 50000.0],
            [106, 200000, "DYN_A", "NODE_X", 10.0],
            [107, 200001, "NODE_X", "NODE_Y", 10.0],
            [108, 200002, "NODE_Y", "DYN_A", 10.0],
            [109, 300000, "DYN_C", "NODE_M", 10.0],
            [110, 300001, "NODE_M", "NODE_N", 10.0],
            [111, 300002, "NODE_N", "DYN_C", 10.0],
            [112, 400000, "PLAIN_1", "PLAIN_2", 10.0],
            [113, 400001, "PLAIN_2", "PLAIN_3", 10.0],
            [114, 400002, "PLAIN_3", "PLAIN_1", 10.0],
        ]
        write_rows(rows1)
        assert_derived(run_analyzer(), rows1)

        rows2 = [
            [201, 10, "LOW_A", "LOW_B", 100.0],
            [202, 20, "LOW_B", "LOW_C", 100.0],
            [203, 30, "LOW_C", "LOW_A", 100.0],
            [204, 100000, "LOW_D", "LOW_E", 49999.99],
        ]
        write_rows(rows2)
        assert_derived(run_analyzer(), rows2)
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
        os.chown(CSV_PATH, 1000, 1000)
        os.chmod(CSV_PATH, 0o666)
        if original_report is not None:
            with open(REPORT, "wb") as f:
                f.write(original_report)
            os.chown(REPORT, 1000, 1000)


if __name__ == "__main__":
    main()
PY_EOF

if python3 /tmp/verify_audit.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

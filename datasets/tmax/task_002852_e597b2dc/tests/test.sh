#!/bin/bash
mkdir -p /logs/verifier

run_verifier() {
cat > /tmp/sqlite_trace.c <<'TRACE_EOF'
#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void log_sql(const char *event, const char *value, const char *sql) {
    const char *path = getenv("SQLITE_TRACE_FILE");
    if (!path) return;
    FILE *f = fopen(path, "a");
    if (!f) return;
    fprintf(f, "%s\t%s\t", event, value ? value : "");
    if (sql) {
        for (const char *p = sql; *p; ++p)
            fputc((*p == '\n' || *p == '\r') ? ' ' : *p, f);
    }
    fputc('\n', f);
    fclose(f);
}

int sqlite3_prepare(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3*,const char*,int,sqlite3_stmt**,const char**) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare");
    log_sql("P", "prepare", sql);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3*,const char*,int,sqlite3_stmt**,const char**) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    log_sql("P", "prepare_v2", sql);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v3(sqlite3 *db, const char *sql, int n, unsigned int flags, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3*,const char*,int,unsigned int,sqlite3_stmt**,const char**) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v3");
    log_sql("P", "prepare_v3", sql);
    return real_fn(db, sql, n, flags, stmt, tail);
}

int sqlite3_exec(sqlite3 *db, const char *sql, int (*cb)(void*,int,char**,char**), void *arg, char **err) {
    static int (*real_fn)(sqlite3*,const char*,int(*)(void*,int,char**,char**),void*,char**) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_exec");
    log_sql("E", "exec", sql);
    return real_fn(db, sql, cb, arg, err);
}

int sqlite3_get_table(sqlite3 *db, const char *sql, char ***out, int *rows, int *cols, char **err) {
    static int (*real_fn)(sqlite3*,const char*,char***,int*,int*,char**) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_get_table");
    log_sql("E", "get_table", sql);
    return real_fn(db, sql, out, rows, cols, err);
}

int sqlite3_bind_int(sqlite3_stmt *stmt, int i, int value) {
    static int (*real_fn)(sqlite3_stmt*,int,int) = NULL;
    char buf[64];
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_bind_int");
    snprintf(buf, sizeof(buf), "%d", value);
    log_sql("B", buf, sqlite3_sql(stmt));
    return real_fn(stmt, i, value);
}

int sqlite3_bind_int64(sqlite3_stmt *stmt, int i, sqlite3_int64 value) {
    static int (*real_fn)(sqlite3_stmt*,int,sqlite3_int64) = NULL;
    char buf[64];
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_bind_int64");
    snprintf(buf, sizeof(buf), "%lld", (long long)value);
    log_sql("B", buf, sqlite3_sql(stmt));
    return real_fn(stmt, i, value);
}

int sqlite3_bind_double(sqlite3_stmt *stmt, int i, double value) {
    static int (*real_fn)(sqlite3_stmt*,int,double) = NULL;
    char buf[64];
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_bind_double");
    snprintf(buf, sizeof(buf), "%.17g", value);
    log_sql("B", buf, sqlite3_sql(stmt));
    return real_fn(stmt, i, value);
}

int sqlite3_bind_text(sqlite3_stmt *stmt, int i, const char *value, int n, void (*destroy)(void*)) {
    static int (*real_fn)(sqlite3_stmt*,int,const char*,int,void(*)(void*)) = NULL;
    char buf[128];
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_bind_text");
    if (!value) snprintf(buf, sizeof(buf), "NULL");
    else {
        int len = n < 0 ? (int)strlen(value) : n;
        if (len > 120) len = 120;
        snprintf(buf, sizeof(buf), "%.*s", len, value);
    }
    log_sql("B", buf, sqlite3_sql(stmt));
    return real_fn(stmt, i, value, n, destroy);
}
TRACE_EOF

    gcc -shared -fPIC -O2 /tmp/sqlite_trace.c -o /tmp/sqlite_trace.so -ldl -lsqlite3 || return 1

cat > /tmp/test_final_state.py <<'PY_EOF'
import json
import os
import random
import re
import shutil
import sqlite3
import subprocess
import tempfile

CPP = "/home/user/query_tool.cpp"
DB = "/home/user/system.db"
RESULTS = "/home/user/results.txt"
BIN = "/home/user/query_tool"
TRACE_LIB = "/tmp/sqlite_trace.so"
EXPECTED_ORIGINAL = [
    "15,3.1,32.0",
    "13,2.1,25.0",
    "12,2.0,15.0",
    "14,3.0,10.0",
]

def read_lines():
    assert os.path.exists(RESULTS), f"{RESULTS} does not exist."
    with open(RESULTS) as f:
        return [line.strip() for line in f if line.strip()]

def run_tool(trace_path):
    if os.path.exists(RESULTS):
        os.remove(RESULTS)
    if os.path.exists(trace_path):
        os.remove(trace_path)
    env = os.environ.copy()
    env["LD_PRELOAD"] = TRACE_LIB
    env["SQLITE_TRACE_FILE"] = trace_path
    subprocess.run([BIN], cwd="/home/user", env=env, timeout=15, check=True)
    assert os.path.exists(RESULTS), "The executed program did not create results.txt"

def validate_trace(trace_path):
    assert os.path.exists(trace_path), "No SQLite activity was observed from the program"
    records = []
    with open(trace_path) as f:
        for line in f:
            records.append(line.rstrip("\n").split("\t", 2))

    prepares = [r for r in records if r[0] == "P"]
    bypasses = [r for r in records if r[0] == "E"]
    binds = [r for r in records if r[0] == "B"]
    assert len(prepares) == 1, f"Expected exactly one prepared SQL query, observed {len(prepares)}"
    assert not bypasses, "sqlite3_exec/sqlite3_get_table was used in addition to the prepared query"

    sql = prepares[0][2] if len(prepares[0]) > 2 else ""
    assert re.search(r"\bSELECT\b", sql, re.I), "The single prepared statement is not a SELECT query"
    assert re.search(r"\?|[:@$][A-Za-z_]", sql), "The executed SQL has no parameter placeholder"
    assert not re.search(r"(?<![A-Za-z0-9_.])10(?![A-Za-z0-9_.])", sql), \
        "The starting node ID was hardcoded directly in the executed SQL"

    bound_ten = False
    for record in binds:
        value = record[1].strip() if len(record) > 1 else ""
        bound_sql = record[2] if len(record) > 2 else ""
        try:
            is_ten = float(value) == 10.0
        except ValueError:
            is_ten = False
        if is_ten and bound_sql == sql:
            bound_ten = True
    assert bound_ten, "The value 10 was not bound to the executed query with sqlite3_bind_*"

def create_random_fixture(path):
    rng = random.SystemRandom()
    conn = sqlite3.connect(path)
    conn.executescript("""
        CREATE TABLE entity (id INTEGER PRIMARY KEY, kind TEXT, metadata TEXT);
        CREATE TABLE link (src INTEGER, dst INTEGER, cost REAL);
    """)
    conn.execute("INSERT INTO entity VALUES (10, 'root', ?)", (json.dumps({"version": "root"}),))

    ids = rng.sample(range(1000, 9000), 12)
    proxies = ids[:3]
    endpoints = ids[3:9]
    nonendpoint, bridge, three_hop_endpoint = ids[9:12]

    for p in proxies:
        conn.execute("INSERT INTO entity VALUES (?, 'proxy', ?)", (p, json.dumps({"version": "proxy"})))

    versions = [f"v{rng.randrange(10000,99999)}" for _ in endpoints]
    for eid, version in zip(endpoints, versions):
        conn.execute("INSERT INTO entity VALUES (?, 'endpoint', ?)", (eid, json.dumps({"version": version, "nonce": rng.randrange(1 << 30)})))

    conn.execute("INSERT INTO entity VALUES (?, 'worker', ?)", (nonendpoint, json.dumps({"version": "not-an-endpoint"})))
    conn.execute("INSERT INTO entity VALUES (?, 'worker', ?)", (bridge, json.dumps({"version": "bridge"})))
    conn.execute("INSERT INTO entity VALUES (?, 'endpoint', ?)", (three_hop_endpoint, json.dumps({"version": "three-hop"})))

    first_costs = [rng.randrange(11, 80) for _ in proxies]
    for p, tenths in zip(proxies, first_costs):
        conn.execute("INSERT INTO link VALUES (10, ?, ?)", (p, tenths / 10.0))

    rows = []
    for index, (eid, version) in enumerate(zip(endpoints, versions)):
        proxy_index = index % len(proxies)
        second_tenths = rng.randrange(90, 700) + index * 80
        conn.execute("INSERT INTO link VALUES (?, ?, ?)", (proxies[proxy_index], eid, second_tenths / 10.0))
        total_tenths = first_costs[proxy_index] + second_tenths
        rows.append((eid, version, total_tenths))

    conn.execute("INSERT INTO link VALUES (?, ?, 999.0)", (proxies[0], nonendpoint))
    conn.execute("INSERT INTO link VALUES (10, ?, 500.0)", (endpoints[0],))
    conn.execute("INSERT INTO link VALUES (?, ?, 4.0)", (proxies[1], bridge))
    conn.execute("INSERT INTO link VALUES (?, ?, 900.0)", (bridge, three_hop_endpoint))
    conn.execute("INSERT INTO link VALUES (99999, ?, 800.0)", (endpoints[1],))
    conn.commit()
    conn.close()

    rows.sort(key=lambda row: row[2], reverse=True)
    return [f"{eid},{version},{tenths / 10.0:.1f}" for eid, version, tenths in rows[:5]]

assert os.path.exists(CPP), f"{CPP} does not exist."
assert os.path.exists(RESULTS), f"{RESULTS} does not exist."
assert read_lines() == EXPECTED_ORIGINAL, \
    f"Contents of {RESULTS} do not match expected output. Got: {read_lines()} Expected: {EXPECTED_ORIGINAL}"
with open(CPP) as f:
    source = f.read()
assert "sqlite3_bind_" in source, "No parameter binding (sqlite3_bind_*) detected in source code."

backup = tempfile.mktemp(prefix="system.db.backup.")
shutil.copy2(DB, backup)
original_good_results = None
try:
    if os.path.exists(BIN):
        os.remove(BIN)
    subprocess.run(["g++", "-O3", CPP, "-lsqlite3", "-o", BIN], timeout=30, check=True)
    assert os.path.isfile(BIN) and os.access(BIN, os.X_OK), "Compilation did not produce an executable query_tool"

    run_tool("/tmp/sqlite_trace_original.log")
    validate_trace("/tmp/sqlite_trace_original.log")
    actual = read_lines()
    assert actual == EXPECTED_ORIGINAL, f"Executed program produced {actual}; expected {EXPECTED_ORIGINAL}"
    with open(RESULTS, "rb") as f:
        original_good_results = f.read()

    fixture = tempfile.mktemp(prefix="system.random.", suffix=".db", dir="/home/user")
    expected_random = create_random_fixture(fixture)
    os.replace(fixture, DB)
    run_tool("/tmp/sqlite_trace_random.log")
    validate_trace("/tmp/sqlite_trace_random.log")
    actual_random = read_lines()
    assert actual_random == expected_random, \
        f"Program failed the independently generated database test. Got {actual_random}; expected {expected_random}"
finally:
    shutil.copy2(backup, DB)
    os.remove(backup)
    if original_good_results is not None:
        with open(RESULTS, "wb") as f:
            f.write(original_good_results)
PY_EOF

    python3 /tmp/test_final_state.py
}

if run_verifier 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

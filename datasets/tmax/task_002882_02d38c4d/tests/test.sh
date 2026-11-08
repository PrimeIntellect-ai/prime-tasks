#!/bin/bash
set -u
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re

def test_query_plan():
    query_plan_path = "/home/user/query_plan.txt"
    assert os.path.isfile(query_plan_path), f"File {query_plan_path} is missing."

    with open(query_plan_path, 'r') as f:
        content = f.read().upper()

    assert "INDEX" in content, "The query plan does not indicate the use of an INDEX."
    assert "USE TEMP B-TREE FOR ORDER BY" not in content, "The query plan indicates an explicit sort (USE TEMP B-TREE FOR ORDER BY), which means the index was not used properly for the window function."

def test_import_cypher():
    cypher_path = "/home/user/import.cypher"
    assert os.path.isfile(cypher_path), f"File {cypher_path} is missing."

    with open(cypher_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    def normalize_numbers(text):
        def repl(match):
            val = float(match.group(0))
            if val.is_integer():
                return str(int(val))
            return str(val)
        return re.sub(r'\b\d+(?:\.\d+)?\b', repl, text)

    normalized_lines = set(normalize_numbers(line) for line in lines)

    expected_lines = [
        "MERGE (s:User {id: 'Alice'}) MERGE (r:User {id: 'Bob'}) CREATE (s)-[:TRANSFERRED {tx_id: 1, amount: 100, running_total: 100, rank: 1}]->(r);",
        "MERGE (s:User {id: 'Alice'}) MERGE (r:User {id: 'Dave'}) CREATE (s)-[:TRANSFERRED {tx_id: 3, amount: 25.5, running_total: 125.5, rank: 2}]->(r);",
        "MERGE (s:User {id: 'Alice'}) MERGE (r:User {id: 'Bob'}) CREATE (s)-[:TRANSFERRED {tx_id: 4, amount: 10, running_total: 135.5, rank: 3}]->(r);",
        "MERGE (s:User {id: 'Bob'}) MERGE (r:User {id: 'Charlie'}) CREATE (s)-[:TRANSFERRED {tx_id: 2, amount: 50, running_total: 50, rank: 1}]->(r);",
        "MERGE (s:User {id: 'Bob'}) MERGE (r:User {id: 'Dave'}) CREATE (s)-[:TRANSFERRED {tx_id: 6, amount: 75, running_total: 125, rank: 2}]->(r);",
        "MERGE (s:User {id: 'Charlie'}) MERGE (r:User {id: 'Alice'}) CREATE (s)-[:TRANSFERRED {tx_id: 5, amount: 200, running_total: 200, rank: 1}]->(r);"
    ]

    normalized_expected = set(normalize_numbers(line) for line in expected_lines)

    missing = normalized_expected - normalized_lines
    extra = normalized_lines - normalized_expected

    assert not missing, f"Missing expected Cypher commands: {missing}"
    assert not extra, f"Found unexpected Cypher commands: {extra}"
    assert len(normalized_lines) == len(expected_lines), "The number of unique Cypher commands does not match the expected count."
TEST_EOF

cat << 'AUDIT_EOF' > /tmp/sqlite_audit.c
#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void log_item(const char *kind, const char *text) {
    const char *path = getenv("SQL_AUDIT_LOG");
    if (!path || !text) return;
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (fd < 0) return;
    write(fd, kind, strlen(kind));
    write(fd, text, strlen(text));
    write(fd, "\036\n", 2);
    close(fd);
}

int sqlite3_open(const char *name, sqlite3 **db) {
    static int (*real_fn)(const char *, sqlite3 **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_open");
    log_item("OPEN:", name);
    return real_fn(name, db);
}

int sqlite3_open_v2(const char *name, sqlite3 **db, int flags, const char *vfs) {
    static int (*real_fn)(const char *, sqlite3 **, int, const char *) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_open_v2");
    log_item("OPEN:", name);
    return real_fn(name, db, flags, vfs);
}

int sqlite3_exec(sqlite3 *db, const char *sql, int (*cb)(void *, int, char **, char **), void *arg, char **err) {
    static int (*real_fn)(sqlite3 *, const char *, int (*)(void *, int, char **, char **), void *, char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_exec");
    log_item("SQL:", sql);
    return real_fn(db, sql, cb, arg, err);
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    log_item("SQL:", sql);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v3(sqlite3 *db, const char *sql, int n, unsigned int flags, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, unsigned int, sqlite3_stmt **, const char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v3");
    log_item("SQL:", sql);
    return real_fn(db, sql, n, flags, stmt, tail);
}
AUDIT_EOF

cat << 'SQL_CHECK_EOF' > /tmp/check_sql.py
import re
import sys

raw = open(sys.argv[1], "rb").read().decode("utf-8", "replace")
items = [x.strip() for x in raw.split("\x1e") if x.strip()]
opens = [x[5:].strip() for x in items if x.startswith("OPEN:")]
sqls = [x[4:].strip() for x in items if x.startswith("SQL:")]
assert ":memory:" in opens, "The program did not open an in-memory SQLite database."

def norm(s):
    return re.sub(r"\s+", " ", s.strip().rstrip(";")).upper()

nsql = [norm(x) for x in sqls]
assert any(re.search(r"\bCREATE\s+TABLE\s+(?:IF\s+NOT\s+EXISTS\s+)?TRANSACTIONS\b", x) for x in nsql), "No transactions table was created through SQLite."
assert any(re.search(r"\bINSERT\s+INTO\s+TRANSACTIONS\b", x) for x in nsql), "Rows were not inserted into transactions through SQLite."
assert any(re.search(r"\bCREATE\s+(?:UNIQUE\s+)?INDEX\b.*\bON\s+TRANSACTIONS\s*\(\s*SENDER(?:\s+ASC|\s+DESC)?\s*,\s*TIMESTAMP", x) for x in nsql), "The required sender/timestamp index was not created through SQLite."

def is_window_query(x):
    return (re.search(r"SUM\s*\(\s*AMOUNT\s*\)\s*OVER\s*\(\s*PARTITION\s+BY\s+SENDER\s+ORDER\s+BY\s+TIMESTAMP", x)
            and re.search(r"ROW_NUMBER\s*\(\s*\)\s*OVER\s*\(\s*PARTITION\s+BY\s+SENDER\s+ORDER\s+BY\s+TIMESTAMP", x)
            and re.search(r"\bFROM\s+TRANSACTIONS\b", x))

actual = [x for x in nsql if not x.startswith("EXPLAIN QUERY PLAN ") and is_window_query(x)]
explained = [x[len("EXPLAIN QUERY PLAN "):].strip() for x in nsql if x.startswith("EXPLAIN QUERY PLAN ") and is_window_query(x)]
assert actual, "The analytical window query was not executed through SQLite."
assert explained, "EXPLAIN QUERY PLAN was not executed for the analytical window query."
assert any(e == a for e in explained for a in actual), "The explained query differs from the executed window query."
SQL_CHECK_EOF

cat << 'DYNAMIC_EOF' > /tmp/dynamic_test.py
import csv
import math
import os
import random
import re
import subprocess

csv_path = "/home/user/transactions.csv"
seed = int.from_bytes(os.urandom(8), "big")
rng = random.Random(seed)
tag = "%08x" % rng.getrandbits(32)
senders = ["SenderA_" + tag, "SenderB_" + tag, "SenderC_" + tag]
receivers = ["RecvA_" + tag, "RecvB_" + tag, "RecvC_" + tag, "RecvD_" + tag]
rows = []
tx = rng.randint(1000, 9000)
for si, sender in enumerate(senders):
    count = 2 + (si % 2)
    base = rng.randint(1700000000, 1800000000)
    for j in range(count):
        amount = round(rng.randint(1, 5000) / 10.0, 1)
        rows.append((tx, sender, receivers[(si + j) % len(receivers)], amount, base + j * 13 + 1))
        tx += rng.randint(2, 9)
rng.shuffle(rows)
with open(csv_path, "w", newline="") as f:
    w = csv.writer(f)
    w.writerow(["tx_id", "sender", "receiver", "amount", "timestamp"])
    w.writerows(rows)

for p in ("/home/user/import.cypher", "/home/user/query_plan.txt", "/tmp/sql_audit_dynamic.log"):
    try:
        os.remove(p)
    except FileNotFoundError:
        pass
env = os.environ.copy()
env["LD_PRELOAD"] = "/tmp/libsqlite_audit.so"
env["SQL_AUDIT_LOG"] = "/tmp/sql_audit_dynamic.log"
subprocess.run(["/home/user/graph_builder"], check=True, timeout=15, env=env)

plan = open("/home/user/query_plan.txt").read().upper()
assert "INDEX" in plan, "The dynamic run's query plan does not indicate index use."
assert "USE TEMP B-TREE FOR ORDER BY" not in plan, "The dynamic run used an explicit ORDER BY sort."

num = r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][-+]?\d+)?"
pat = re.compile(r"^MERGE \(s:User \{id: '([^']+)'\}\) MERGE \(r:User \{id: '([^']+)'\}\) CREATE \(s\)-\[:TRANSFERRED \{tx_id: (\d+), amount: (" + num + r"), running_total: (" + num + r"), rank: (\d+)\}\]->\(r\);$")
lines = [x.strip() for x in open("/home/user/import.cypher") if x.strip()]
assert len(lines) == len(rows), "The dynamic CSV did not produce exactly one Cypher command per row."
actual = {}
for line in lines:
    m = pat.fullmatch(line)
    assert m, "A generated Cypher command does not have the required exact format: " + line
    key = int(m.group(3))
    assert key not in actual, "Duplicate transaction in generated Cypher."
    actual[key] = (m.group(1), m.group(2), float(m.group(4)), float(m.group(5)), int(m.group(6)))

expected = {}
for sender in senders:
    total = 0.0
    part = sorted((r for r in rows if r[1] == sender), key=lambda r: r[4])
    for rank, (tid, snd, recv, amount, timestamp) in enumerate(part, 1):
        total += amount
        expected[tid] = (snd, recv, amount, total, rank)
assert set(actual) == set(expected), "Generated transaction IDs do not match the dynamic CSV."
for tid, exp in expected.items():
    got = actual[tid]
    assert got[0:2] == exp[0:2] and got[4] == exp[4], f"Wrong sender, receiver, or rank for transaction {tid}."
    assert math.isclose(got[2], exp[2], rel_tol=1e-9, abs_tol=1e-7), f"Wrong amount for transaction {tid}."
    assert math.isclose(got[3], exp[3], rel_tol=1e-9, abs_tol=1e-7), f"Wrong running total for transaction {tid}."
DYNAMIC_EOF

run_program() {
    local logfile="$1"
    rm -f /home/user/import.cypher /home/user/query_plan.txt "$logfile"
    timeout 15s env LD_PRELOAD=/tmp/libsqlite_audit.so SQL_AUDIT_LOG="$logfile" /home/user/graph_builder
}

run_checks() {
    test -f /home/user/graph_builder.cpp || return 1
    g++ -std=c++17 /home/user/graph_builder.cpp -lsqlite3 -o /home/user/graph_builder || return 1
    test -x /home/user/graph_builder || return 1
    gcc -shared -fPIC /tmp/sqlite_audit.c -o /tmp/libsqlite_audit.so -ldl || return 1

    cp /home/user/transactions.csv /tmp/transactions.original.csv || return 1

    run_program /tmp/sql_audit_original.log || return 1
    python3 /tmp/check_sql.py /tmp/sql_audit_original.log || return 1
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1

    python3 /tmp/dynamic_test.py || return 1
    python3 /tmp/check_sql.py /tmp/sql_audit_dynamic.log || return 1

    cp /tmp/transactions.original.csv /home/user/transactions.csv || return 1
    run_program /tmp/sql_audit_final.log || return 1
    python3 /tmp/check_sql.py /tmp/sql_audit_final.log || return 1
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1
}

if run_checks; then
    echo "1" > /logs/verifier/reward.txt
else
    if [ -f /tmp/transactions.original.csv ]; then
        cp /tmp/transactions.original.csv /home/user/transactions.csv 2>/dev/null || true
    fi
    echo "0" > /logs/verifier/reward.txt
fi

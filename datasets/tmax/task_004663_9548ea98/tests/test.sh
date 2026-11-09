#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import sqlite3
import subprocess
from datetime import datetime

DB_PATH = '/home/user/compliance.db'
INDEX_SQL_PATH = '/home/user/index.sql'
CPP_PATH = '/home/user/audit.cpp'
RUNNER_PATH = '/home/user/audit_runner'
RESULTS_PATH = '/home/user/audit_results.json'
TRACE_SO = '/tmp/sqlite_trace.so'
TRACE_LOG = '/tmp/audit_sql_trace.bin'


def matching_indexes(conn):
    found = []
    for row in conn.execute("PRAGMA index_list('access_logs')"):
        name = row[1]
        cols = [r[2] for r in conn.execute("PRAGMA index_info(" + json.dumps(name) + ")")]
        if len(cols) >= 2 and cols[0].lower() == 'user_id' and cols[1].lower() == 'log_timestamp':
            found.append(name)
    return found


def test_index_sql_exists_and_valid():
    assert os.path.exists(INDEX_SQL_PATH), f"Missing index script at {INDEX_SQL_PATH}"
    with open(INDEX_SQL_PATH, 'r') as f:
        content = f.read().lower()
    assert "create index" in content, "index.sql must contain a CREATE INDEX statement."
    assert "access_logs" in content, "index.sql must target the access_logs table."
    assert "user_id" in content, "index.sql must index the user_id column."

    # The requested script must already have been applied by the agent.
    conn = sqlite3.connect(DB_PATH)
    try:
        assert matching_indexes(conn), \
            "No applied access_logs index begins with (user_id, log_timestamp)."
    finally:
        conn.close()


def test_cpp_file_exists():
    assert os.path.exists(CPP_PATH), f"Missing C++ source file at {CPP_PATH}"


def test_runner_executable_exists():
    assert os.path.exists(RUNNER_PATH), f"Missing compiled executable at {RUNNER_PATH}"
    assert os.access(RUNNER_PATH, os.X_OK), f"{RUNNER_PATH} is not executable."


def get_expected_results():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("""
    SELECT t.tx_id, t.user_id, t.amount, a.ip_address as flagged_ip
    FROM transactions t
    JOIN users u ON t.user_id = u.user_id
    JOIN access_logs a ON t.user_id = a.user_id
    WHERE t.amount > 10000
      AND a.ip_country != u.country_code
      AND abs(julianday(a.log_timestamp) - julianday(t.tx_timestamp)) <= 1.0
    ORDER BY a.log_timestamp DESC
    """)
    rows = cursor.fetchall()
    conn.close()
    results_map = {}
    for tx_id, user_id, amount, flagged_ip in rows:
        if tx_id not in results_map:
            results_map[tx_id] = {
                "tx_id": tx_id,
                "user_id": user_id,
                "amount": float(amount),
                "flagged_ip": flagged_ip,
            }
    return list(results_map.values())


def load_and_compare(expected):
    assert os.path.exists(RESULTS_PATH), f"Missing results file at {RESULTS_PATH}"
    with open(RESULTS_PATH, 'r') as f:
        actual_results = json.load(f)
    assert isinstance(actual_results, list), "JSON output must be a list of objects."
    actual_sorted = sorted(actual_results, key=lambda x: x.get("tx_id", ""))
    expected_sorted = sorted(expected, key=lambda x: x["tx_id"])
    assert len(actual_sorted) == len(expected_sorted), \
        f"Expected {len(expected_sorted)} results, got {len(actual_sorted)}."
    for actual, wanted in zip(actual_sorted, expected_sorted):
        assert isinstance(actual, dict), "Every array element must be an object."
        assert set(actual) == {"tx_id", "user_id", "amount", "flagged_ip"}, \
            "Each object must contain exactly the required schema fields."
        assert actual.get("tx_id") == wanted["tx_id"], "Mismatch in tx_id."
        assert actual.get("user_id") == wanted["user_id"], "Mismatch in user_id."
        assert isinstance(actual.get("amount"), (int, float)) and not isinstance(actual.get("amount"), bool)
        assert abs(actual.get("amount", 0) - wanted["amount"]) < 0.01, "Mismatch in amount."
        assert actual.get("flagged_ip") == wanted["flagged_ip"], "Mismatch in flagged_ip."


def test_existing_audit_results_json():
    # Preserve the original verifier's comparison against the database state left by the agent.
    load_and_compare(get_expected_results())


def build_trace_library():
    src = r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sqlite3.h>

static void record_sql(const char *sql) {
    const char *path = getenv("AUDIT_SQL_TRACE");
    if (!path || !sql) return;
    FILE *f = fopen(path, "ab");
    if (!f) return;
    fwrite(sql, 1, strlen(sql), f);
    fputc(0, f);
    fclose(f);
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int n, sqlite3_stmt **st, const char **tail) {
    static int (*real_fn)(sqlite3*,const char*,int,sqlite3_stmt**,const char**) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    record_sql(sql);
    return real_fn(db, sql, n, st, tail);
}
int sqlite3_prepare_v3(sqlite3 *db, const char *sql, int n, unsigned int flags, sqlite3_stmt **st, const char **tail) {
    static int (*real_fn)(sqlite3*,const char*,int,unsigned int,sqlite3_stmt**,const char**) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v3");
    record_sql(sql);
    return real_fn(db, sql, n, flags, st, tail);
}
int sqlite3_prepare(sqlite3 *db, const char *sql, int n, sqlite3_stmt **st, const char **tail) {
    static int (*real_fn)(sqlite3*,const char*,int,sqlite3_stmt**,const char**) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare");
    record_sql(sql);
    return real_fn(db, sql, n, st, tail);
}
int sqlite3_exec(sqlite3 *db, const char *sql, int (*cb)(void*,int,char**,char**), void *arg, char **err) {
    static int (*real_fn)(sqlite3*,const char*,int(*)(void*,int,char**,char**),void*,char**) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_exec");
    record_sql(sql);
    return real_fn(db, sql, cb, arg, err);
}
'''
    with open('/tmp/sqlite_trace.c', 'w') as f:
        f.write(src)
    subprocess.run(
        ['gcc', '-shared', '-fPIC', '/tmp/sqlite_trace.c', '-o', TRACE_SO, '-ldl', '-lsqlite3'],
        check=True, timeout=30,
    )


def create_case(case_no):
    for suffix in ('', '-wal', '-shm'):
        try:
            os.remove(DB_PATH + suffix)
        except FileNotFoundError:
            pass

    token = secrets.token_hex(4)
    day = 3 + case_no * 7 + secrets.randbelow(2)
    base = f'2024-02-{day:02d}'
    users = [(i, c) for i, c in enumerate(['US', 'UK', 'CA', 'DE', 'JP', 'AU'], 101)]
    transactions = [
        (f'{token}-A', 101, 15001.25 + case_no, f'{base} 12:00:00'),
        (f'{token}-B', 102, 22000.50 + case_no, f'{base} 12:00:00'),
        (f'{token}-C', 103, 9999.99, f'{base} 12:00:00'),
        (f'{token}-D', 104, 31000.75, f'{base} 12:00:00'),
        (f'{token}-E', 105, 41000.00 + case_no, f'{base} 12:00:00'),
    ]
    logs = [
        (1, 101, f'198.51.100.{10+case_no}', 'RU', f'{base} 10:00:00'),
        (2, 101, f'203.0.113.{20+case_no}', 'FR', f'{base} 17:00:00'),
        (3, 101, f'192.0.2.{30+case_no}', 'US', f'{base} 20:00:00'),
        (4, 102, f'192.0.2.{40+case_no}', 'UK', f'{base} 13:00:00'),
        (5, 103, f'203.0.113.{50+case_no}', 'CN', f'{base} 13:00:00'),
        (6, 104, f'198.51.100.{60+case_no}', 'BR', f'2024-02-{day+2:02d} 12:00:00'),
        (7, 105, f'203.0.113.{70+case_no}', 'NZ', f'2024-02-{day-1:02d} 13:00:00'),
    ]

    conn = sqlite3.connect(DB_PATH)
    conn.executescript('''
        CREATE TABLE users (user_id INTEGER PRIMARY KEY, country_code TEXT);
        CREATE TABLE transactions (tx_id TEXT PRIMARY KEY, user_id INTEGER, amount REAL, tx_timestamp DATETIME);
        CREATE TABLE access_logs (log_id INTEGER PRIMARY KEY, user_id INTEGER, ip_address TEXT, ip_country TEXT, log_timestamp DATETIME);
    ''')
    conn.executemany('INSERT INTO users VALUES (?,?)', users)
    conn.executemany('INSERT INTO transactions VALUES (?,?,?,?)', transactions)
    conn.executemany('INSERT INTO access_logs VALUES (?,?,?,?,?)', logs)
    conn.commit()
    conn.close()

    # Derive the oracle independently from the submitted SQL and database query engine.
    countries = dict(users)
    best = {}
    for tx_id, uid, amount, tx_time in transactions:
        if amount <= 10000:
            continue
        tt = datetime.fromisoformat(tx_time)
        candidates = []
        for _, luid, ip, ip_country, log_time in logs:
            lt = datetime.fromisoformat(log_time)
            if luid == uid and ip_country != countries[uid] and abs((lt - tt).total_seconds()) <= 86400:
                candidates.append((lt, ip))
        if candidates:
            _, ip = max(candidates)
            best[tx_id] = {"tx_id": tx_id, "user_id": uid, "amount": float(amount), "flagged_ip": ip}
    return list(best.values()), (users, transactions, logs)


def snapshot_tables(conn):
    return {
        'users': conn.execute('SELECT * FROM users ORDER BY user_id').fetchall(),
        'transactions': conn.execute('SELECT * FROM transactions ORDER BY tx_id').fetchall(),
        'access_logs': conn.execute('SELECT * FROM access_logs ORDER BY log_id').fetchall(),
    }


def apply_and_validate_index(expected_data):
    with open(INDEX_SQL_PATH, 'r') as f:
        script = f.read()
    subprocess.run(['sqlite3', DB_PATH], input=script, text=True, check=True, timeout=20)
    conn = sqlite3.connect(DB_PATH)
    try:
        assert snapshot_tables(conn) == {
            'users': expected_data[0],
            'transactions': expected_data[1],
            'access_logs': expected_data[2],
        }, "index.sql must not alter the compliance data."
        indexes = matching_indexes(conn)
        assert indexes, "index.sql did not create a composite (user_id, log_timestamp) access_logs index."
        escaped = indexes[0].replace('"', '""')
        plan = conn.execute(
            f'EXPLAIN QUERY PLAN SELECT * FROM access_logs INDEXED BY "{escaped}" '
            'WHERE user_id=? AND log_timestamp BETWEEN ? AND ?',
            (101, '2024-01-01', '2025-01-01'),
        ).fetchall()
        assert any(indexes[0].lower() in str(row).lower() and 'search' in str(row).lower() for row in plan), \
            "The created index cannot support the required user/time-bound search."
        return snapshot_tables(conn)
    finally:
        conn.close()


def executed_complex_json_query():
    with open(TRACE_LOG, 'rb') as f:
        statements = [s.decode('utf-8', 'replace').lower() for s in f.read().split(b'\0') if s]
    for sql in statements:
        if ('json_group_array' in sql and 'json_object' in sql and
                re.search(r'\bjoin\b', sql) and len(re.findall(r'\bselect\b', sql)) >= 2):
            return True
    return False


def test_compiled_program_on_unseen_databases():
    # Rebuild the demanded artifact from audit.cpp, so a dummy prebuilt executable cannot pass.
    subprocess.run(
        ['g++', '-O2', CPP_PATH, '-o', RUNNER_PATH, '-lsqlite3'],
        check=True, timeout=60,
    )
    assert os.access(RUNNER_PATH, os.X_OK)
    build_trace_library()

    for case_no in (1, 2):
        expected, data = create_case(case_no)
        before = apply_and_validate_index(data)
        try:
            os.remove(RESULTS_PATH)
        except FileNotFoundError:
            pass
        try:
            os.remove(TRACE_LOG)
        except FileNotFoundError:
            pass

        env = os.environ.copy()
        env['LD_PRELOAD'] = TRACE_SO
        env['AUDIT_SQL_TRACE'] = TRACE_LOG
        subprocess.run([RUNNER_PATH], cwd='/home/user', env=env, check=True, timeout=30)

        assert os.path.exists(TRACE_LOG), "audit_runner did not execute SQL through SQLite."
        assert executed_complex_json_query(), \
            "audit_runner must execute a joined subquery using json_group_array and json_object."
        load_and_compare(expected)

        conn = sqlite3.connect(DB_PATH)
        try:
            assert snapshot_tables(conn) == before, "audit_runner must not alter the compliance data."
            assert matching_indexes(conn), "The access_logs optimization index was removed."
        finally:
            conn.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

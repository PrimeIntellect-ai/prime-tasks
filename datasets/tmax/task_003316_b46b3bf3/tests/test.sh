#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'SHIM_EOF' > /tmp/noindex.c
#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>

static __thread int inspecting = 0;

typedef int (*prepare_v2_fn)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **);
typedef int (*prepare_v3_fn)(sqlite3 *, const char *, int, unsigned int, sqlite3_stmt **, const char **);
typedef int (*prepare_fn)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **);
typedef int (*exec_fn)(sqlite3 *, const char *, int (*)(void *, int, char **, char **), void *, char **);

static void inspect_plan(sqlite3 *db, const char *sql) {
    if (inspecting || !db || !sql || !strcasestr(sql, "signals") || !strcasestr(sql, "select"))
        return;

    prepare_v2_fn real_prepare = (prepare_v2_fn)dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    if (!real_prepare)
        return;

    size_t n = strlen(sql) + 32;
    char *explain = malloc(n);
    if (!explain)
        return;
    snprintf(explain, n, "EXPLAIN QUERY PLAN %s", sql);

    inspecting = 1;
    sqlite3_stmt *stmt = NULL;
    if (real_prepare(db, explain, -1, &stmt, NULL) == SQLITE_OK && stmt) {
        while (sqlite3_step(stmt) == SQLITE_ROW) {
            const unsigned char *detail_text = sqlite3_column_text(stmt, 3);
            if (!detail_text)
                continue;
            const char *detail = (const char *)detail_text;
            if (strcasestr(detail, "INDEX") || strcasestr(detail, "SEARCH ")) {
                fprintf(stderr, "Verifier rejected indexed/non-scan query plan: %s\n", detail);
                sqlite3_finalize(stmt);
                free(explain);
                _exit(86);
            }
        }
        sqlite3_finalize(stmt);
    }
    inspecting = 0;
    free(explain);
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    prepare_v2_fn real_fn = (prepare_v2_fn)dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    int rc = real_fn(db, sql, n, stmt, tail);
    if (!inspecting && rc == SQLITE_OK)
        inspect_plan(db, sql);
    return rc;
}

int sqlite3_prepare_v3(sqlite3 *db, const char *sql, int n, unsigned int flags, sqlite3_stmt **stmt, const char **tail) {
    prepare_v3_fn real_fn = (prepare_v3_fn)dlsym(RTLD_NEXT, "sqlite3_prepare_v3");
    int rc = real_fn(db, sql, n, flags, stmt, tail);
    if (!inspecting && rc == SQLITE_OK)
        inspect_plan(db, sql);
    return rc;
}

int sqlite3_prepare(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    prepare_fn real_fn = (prepare_fn)dlsym(RTLD_NEXT, "sqlite3_prepare");
    int rc = real_fn(db, sql, n, stmt, tail);
    if (!inspecting && rc == SQLITE_OK)
        inspect_plan(db, sql);
    return rc;
}

int sqlite3_exec(sqlite3 *db, const char *sql,
                 int (*callback)(void *, int, char **, char **),
                 void *arg, char **errmsg) {
    exec_fn real_fn = (exec_fn)dlsym(RTLD_NEXT, "sqlite3_exec");
    if (!inspecting)
        inspect_plan(db, sql);
    return real_fn(db, sql, callback, arg, errmsg);
}
SHIM_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sqlite3
import subprocess

C_FILE_PATH = '/home/user/extractor.c'
EXEC_FILE_PATH = '/home/user/extractor'
CSV_FILE_PATH = '/home/user/valid_relays.csv'
DB_FILE_PATH = '/home/user/telemetry.db'
SHIM_PATH = '/tmp/noindex.so'

INITIAL_EXPECTED = """start,relay,end,path_power
NodeP,NodeQ,NodeR,75.0
NodeB,NodeC,NodeD,70.0
NodeA,NodeB,NodeC,60.5"""


def read_csv():
    assert os.path.isfile(CSV_FILE_PATH), f"CSV output file missing at {CSV_FILE_PATH}"
    with open(CSV_FILE_PATH, 'r', encoding='utf-8') as f:
        return f.read().strip()


def expected_from_rows(rows):
    matches = []
    for first in rows:
        for second in rows:
            if (first[2] == second[1] and first[3] > 50.0 and second[3] > 50.0
                    and 0 < second[4] - first[4] <= 100):
                matches.append((first[1], first[2], second[2], min(first[3], second[3])))
    matches.sort(key=lambda r: (-r[3], r[0]))
    lines = ['start,relay,end,path_power']
    lines.extend(f'{start},{relay},{end},{power:.1f}' for start, relay, end, power in matches)
    return '\n'.join(lines)


def run_extractor():
    if os.path.exists(CSV_FILE_PATH):
        os.remove(CSV_FILE_PATH)
    env = os.environ.copy()
    env['LD_PRELOAD'] = SHIM_PATH
    result = subprocess.run(
        [EXEC_FILE_PATH], cwd='/home/user', env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15
    )
    assert result.returncode == 0, (
        f'extractor exited with {result.returncode}\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert os.path.isfile(CSV_FILE_PATH), 'extractor did not generate valid_relays.csv'


def install_dynamic_database(rows):
    if os.path.exists(DB_FILE_PATH):
        os.remove(DB_FILE_PATH)
    conn = sqlite3.connect(DB_FILE_PATH)
    conn.execute('''CREATE TABLE signals (
        id INTEGER PRIMARY KEY,
        source TEXT,
        destination TEXT,
        power REAL,
        timestamp INTEGER
    )''')
    conn.executemany('INSERT INTO signals VALUES (?, ?, ?, ?, ?)', rows)

    # Build an index containing only decoy rows, then alter its schema declaration
    # so SQLite's planner believes it is a complete timestamp index. A query that
    # uses this corrupted index will silently omit the real rows.
    conn.execute("CREATE INDEX idx_ts ON signals(timestamp) WHERE source LIKE 'IndexedOnly%'")
    conn.execute('PRAGMA writable_schema=ON')
    conn.execute("UPDATE sqlite_schema SET sql='CREATE INDEX idx_ts ON signals(timestamp)' WHERE name='idx_ts'")
    version = conn.execute('PRAGMA schema_version').fetchone()[0]
    conn.execute(f'PRAGMA schema_version={version + 1}')
    conn.commit()
    conn.close()


def test_complete_solution():
    # Preserve all original final-state assertions.
    assert os.path.isfile(C_FILE_PATH), f'C source file missing at {C_FILE_PATH}'
    assert os.path.isfile(EXEC_FILE_PATH), f'Executable missing at {EXEC_FILE_PATH}'
    assert os.access(EXEC_FILE_PATH, os.X_OK), f'File at {EXEC_FILE_PATH} is not executable'
    assert read_csv() == INITIAL_EXPECTED, (
        f'CSV content does not match expected output.\nExpected:\n{INITIAL_EXPECTED}\n\nGot:\n{read_csv()}'
    )

    shim_build = subprocess.run(
        ['gcc', '-shared', '-fPIC', '/tmp/noindex.c', '-o', SHIM_PATH, '-ldl', '-lsqlite3'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15
    )
    assert shim_build.returncode == 0, f'failed to build verifier shim: {shim_build.stderr}'

    # Rebuild the submitted source using the command required by the instruction,
    # then execute that resulting artifact rather than trusting a prewritten CSV.
    build = subprocess.run(
        ['gcc', C_FILE_PATH, '-o', EXEC_FILE_PATH, '-lsqlite3'],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert build.returncode == 0, f'extractor.c failed to compile: {build.stderr}'
    assert os.access(EXEC_FILE_PATH, os.X_OK)

    run_extractor()
    assert read_csv() == INITIAL_EXPECTED

    rows = [
        (1, 'Alpha', 'RelayOne', 91.3, 1000),
        (2, 'RelayOne', 'Omega', 88.8, 1055),
        (3, 'Beta', 'RelayTwo', 60.4, 2000),
        (4, 'RelayTwo', 'Finish', 60.2, 2100),
        (5, 'TooLate', 'DelayRelay', 99.0, 3000),
        (6, 'DelayRelay', 'Missed', 98.0, 3101),
        (7, 'Weak', 'WeakRelay', 50.0, 4000),
        (8, 'WeakRelay', 'Nope', 95.0, 4010),
        (9, 'Gamma', 'RelayThree', 72.7, 5000),
        (10, 'RelayThree', 'Delta', 81.1, 5001),
        (11, 'IndexedOnlyDecoy', 'Nobody', 10.0, 9999),
    ]
    install_dynamic_database(rows)
    run_extractor()
    assert read_csv() == expected_from_rows(rows)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

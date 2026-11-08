#!/bin/bash
set -u
mkdir -p /logs/verifier

DB=/home/user/telemetry.db
CSV=/home/user/top_signals.csv
SRC=/home/user/process_signals.cpp
BIN=/home/user/process_signals
DB_BAK=/tmp/telemetry.db.verifier.$$
CSV_BAK=/tmp/top_signals.csv.verifier.$$
VERIFIED_BIN=/tmp/process_signals_verified.$$
TRACE_SO=/tmp/sqlite_trace.$$.so
had_db=0
had_csv=0

if [ -f "$DB" ]; then
    cp -p "$DB" "$DB_BAK" && had_db=1
fi
if [ -f "$CSV" ]; then
    cp -p "$CSV" "$CSV_BAK" && had_csv=1
fi

cleanup() {
    if [ "$had_db" -eq 1 ] && [ -f "$DB_BAK" ]; then
        cp -p "$DB_BAK" "$DB" || true
    fi
    if [ "$had_csv" -eq 1 ] && [ -f "$CSV_BAK" ]; then
        cp -p "$CSV_BAK" "$CSV" || true
    elif [ "$had_csv" -eq 0 ]; then
        rm -f "$CSV"
    fi
    rm -f "$DB_BAK" "$CSV_BAK" "$VERIFIED_BIN" "$TRACE_SO" /tmp/sqlite_trace.c /tmp/process_trace.original /tmp/process_trace.rebuilt
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sqlite3
import csv

def test_index_exists():
    db_path = '/home/user/telemetry.db'
    assert os.path.exists(db_path), f"Database file {db_path} is missing."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("PRAGMA index_list('logs')")
    indexes = cursor.fetchall()

    has_valid_index = False
    for idx in indexes:
        idx_name = idx[1].replace("'", "''")
        cursor.execute(f"PRAGMA index_info('{idx_name}')")
        cols = [row[2] for row in cursor.fetchall()]
        # Partitioning column must lead the index; signal_strength is the sort key.
        if len(cols) >= 2 and cols[:2] == ['device_id', 'signal_strength']:
            has_valid_index = True
            break

    conn.close()
    assert has_valid_index, "Missing index beginning with (`device_id`, `signal_strength`) on `logs` table."

def test_csv_exists_and_content():
    csv_path = '/home/user/top_signals.csv'
    assert os.path.exists(csv_path), f"{csv_path} does not exist. Did you run the C++ program?"

    db_path = '/home/user/telemetry.db'
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Compute expected results using Python and SQLite
    cursor.execute("""
        SELECT device_id, epoch_sec, signal_strength,
               RANK() OVER(PARTITION BY device_id ORDER BY signal_strength DESC) as rank
        FROM logs
        WHERE signal_strength IS NOT NULL
          AND signal_strength >= -100.0
          AND signal_strength <= 0.0
    """)
    rows = cursor.fetchall()
    conn.close()

    expected_rows = []
    for r in rows:
        if r[3] <= 3:
            expected_rows.append(r)

    # Sort expected: device_id asc, rank asc
    expected_rows.sort(key=lambda x: (x[0], x[3]))

    # Read actual CSV
    actual_rows = []
    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        for row in reader:
            if not row:
                continue
            try:
                actual_rows.append((row[0], int(row[1]), float(row[2]), int(row[3])))
            except (ValueError, IndexError) as e:
                assert False, f"Invalid format in CSV row: {row}. Error: {e}"

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows in CSV, got {len(actual_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Row {i+1} mismatch: expected {expected}, got {actual}."

def test_csv_no_out_of_bounds():
    csv_path = '/home/user/top_signals.csv'
    if not os.path.exists(csv_path):
        return

    with open(csv_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        for row in reader:
            if not row:
                continue
            signal_strength = float(row[2])
            assert -100.0 <= signal_strength <= 0.0, f"Found out-of-bounds signal_strength {signal_strength} in CSV."
TEST_EOF

cat << 'TRACE_EOF' > /tmp/sqlite_trace.c
#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <ctype.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void inspect_sql(const char *sql) {
    if (!sql) return;
    size_t n = strlen(sql);
    char *s = malloc(n + 1);
    if (!s) return;
    size_t j = 0;
    int space = 0;
    for (size_t i = 0; i < n; ++i) {
        unsigned char c = (unsigned char)sql[i];
        if (isspace(c)) {
            if (j && !space) s[j++] = ' ';
            space = 1;
        } else {
            s[j++] = (char)tolower(c);
            space = 0;
        }
    }
    s[j] = 0;
    if (strstr(s, "rank") && strstr(s, "over") &&
        strstr(s, "partition by") && strstr(s, "device_id") &&
        strstr(s, "order by") && strstr(s, "signal_strength") &&
        strstr(s, "desc")) {
        const char *path = getenv("TRACE_FILE");
        if (path) {
            FILE *f = fopen(path, "a");
            if (f) { fputs("window-query-observed\n", f); fclose(f); }
        }
    }
    free(s);
}

int sqlite3_prepare(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3*,const char*,int,sqlite3_stmt**,const char**) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare");
    inspect_sql(sql);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3*,const char*,int,sqlite3_stmt**,const char**) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    inspect_sql(sql);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v3(sqlite3 *db, const char *sql, int n, unsigned int flags, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3*,const char*,int,unsigned int,sqlite3_stmt**,const char**) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v3");
    inspect_sql(sql);
    return real_fn(db, sql, n, flags, stmt, tail);
}

int sqlite3_exec(sqlite3 *db, const char *sql, int (*cb)(void*,int,char**,char**), void *arg, char **err) {
    static int (*real_fn)(sqlite3*,const char*,int(*)(void*,int,char**,char**),void*,char**) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_exec");
    inspect_sql(sql);
    return real_fn(db, sql, cb, arg, err);
}
TRACE_EOF

verify_all() {
    [ -f "$DB" ] || { echo "Database is missing"; return 1; }
    [ -f "$CSV" ] || { echo "CSV was not generated before verification"; return 1; }
    [ -f "$SRC" ] || { echo "C++ source is missing"; return 1; }
    [ -f "$BIN" ] && [ -x "$BIN" ] || { echo "Compiled executable is missing or not executable"; return 1; }

    python3 - << 'PY' || return 1
from pathlib import Path
import re
p = Path('/home/user/process_signals.cpp')
s = p.read_text(encoding='utf-8', errors='strict')
assert re.search(r'#\s*include\s*[<"]sqlite3\.h[>"]', s), 'Source must include sqlite3.h'
assert re.search(r'\bsqlite3_open(?:_v2)?\s*\(', s), 'Source must open SQLite through the C API'
assert re.search(r'\bsqlite3_close(?:_v2)?\s*\(', s), 'Source must close the SQLite connection'
uses_exec = re.search(r'\bsqlite3_exec\s*\(', s)
uses_prepared = re.search(r'\bsqlite3_prepare(?:_v2|_v3)?\s*\(', s) and re.search(r'\bsqlite3_step\s*\(', s)
assert uses_exec or uses_prepared, 'Source must execute SQL through the SQLite C API'
assert re.search(r'\bsqlite3_column_', s), 'Source must fetch query result columns through the SQLite C API'
PY

    python3 - "$BIN" << 'PY' || return 1
import sys
p = sys.argv[1]
with open(p, 'rb') as f:
    assert f.read(4) == b'\x7fELF', 'process_signals must be a compiled ELF executable'
PY

    g++ -O2 "$SRC" -o "$VERIFIED_BIN" -lsqlite3 || return 1
    nm -D "$BIN" 2>/dev/null | grep -q 'sqlite3_' || { echo "Executable does not reference the SQLite C API"; return 1; }
    nm -D "$VERIFIED_BIN" 2>/dev/null | grep -q 'sqlite3_' || { echo "Rebuilt source does not reference the SQLite C API"; return 1; }
    gcc -shared -fPIC /tmp/sqlite_trace.c -o "$TRACE_SO" -ldl || return 1

    # Add verifier-only rows, including a tie and invalid values, so a precomputed CSV cannot pass.
    python3 - << 'PY' || return 1
import sqlite3, uuid
path = '/home/user/telemetry.db'
dev = 'VERIFY-' + uuid.uuid4().hex
rows = [
    (dev, 1900000001, -0.125),
    (dev, 1900000002, -0.125),
    (dev, 1900000003, -0.25),
    (dev, 1900000004, -0.5),
    (dev, 1900000005, None),
    (dev, 1900000006, 1.0),
    (dev, 1900000007, -101.0),
]
with sqlite3.connect(path) as conn:
    conn.executemany('INSERT INTO logs(device_id, epoch_sec, signal_strength) VALUES (?, ?, ?)', rows)
PY

    rm -f "$CSV" /tmp/process_trace.original
    (cd /home/user && TRACE_FILE=/tmp/process_trace.original LD_PRELOAD="$TRACE_SO" timeout 30 "$BIN") || return 1
    [ -s /tmp/process_trace.original ] || { echo "The submitted executable did not execute the required window-function query"; return 1; }
    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1

    rm -f "$CSV" /tmp/process_trace.rebuilt
    (cd /home/user && TRACE_FILE=/tmp/process_trace.rebuilt LD_PRELOAD="$TRACE_SO" timeout 30 "$VERIFIED_BIN") || return 1
    [ -s /tmp/process_trace.rebuilt ] || { echo "The submitted source did not execute the required window-function query"; return 1; }
    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1
}

if verify_all 2>&1; then
    result=1
else
    result=0
fi
cleanup
trap - EXIT
echo "$result" > /logs/verifier/reward.txt

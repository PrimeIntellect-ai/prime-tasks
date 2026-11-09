#!/bin/bash
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import re
import shutil
import sqlite3
import subprocess

import pytest

CSV_PATH = '/home/user/output.csv'
C_SOURCE_PATH = '/home/user/analyze.c'
C_BIN_PATH = '/home/user/analyze'
DB_PATH = '/home/user/sensor_data.db'
AUDIT_SO = '/tmp/sqlite_audit.so'
AUDIT_LOG = '/tmp/sqlite_audit.log'

EXPECTED_ROWS = [
    ['device_name', 'timestamp', 'temperature', 'moving_avg'],
    ['Alpha_Sensor', '2023-10-01 10:00:00', '20.0', '20.00'],
    ['Alpha_Sensor', '2023-10-01 10:05:00', '22.0', '21.00'],
    ['Alpha_Sensor', '2023-10-01 10:10:00', '24.0', '22.00'],
    ['Alpha_Sensor', '2023-10-01 10:15:00', '26.0', '24.00'],
    ['Beta_Sensor', '2023-10-01 10:00:00', '15.0', '15.00'],
    ['Beta_Sensor', '2023-10-01 10:05:00', '16.0', '15.50'],
    ['Beta_Sensor', '2023-10-01 10:10:00', '18.0', '16.33']
]

AUDIT_C = r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <sqlite3.h>

static void record_sql(const char *kind, int rc, const char *sql) {
    const char *path = getenv("SQLITE_AUDIT_LOG");
    if (!path || !sql) return;
    FILE *f = fopen(path, "a");
    if (!f) return;
    fprintf(f, "%s %d|", kind, rc);
    for (; *sql; ++sql) fputc((*sql == '\n' || *sql == '\r') ? ' ' : *sql, f);
    fputc('\n', f);
    fclose(f);
}

int sqlite3_exec(sqlite3 *db, const char *sql,
                 int (*cb)(void*,int,char**,char**), void *arg, char **errmsg) {
    static int (*real_exec)(sqlite3*,const char*,int(*)(void*,int,char**,char**),void*,char**);
    if (!real_exec) real_exec = dlsym(RTLD_NEXT, "sqlite3_exec");
    int rc = real_exec(db, sql, cb, arg, errmsg);
    record_sql("EXEC", rc, sql);
    return rc;
}

int sqlite3_step(sqlite3_stmt *stmt) {
    static int (*real_step)(sqlite3_stmt*);
    static const char *(*real_sql)(sqlite3_stmt*);
    if (!real_step) real_step = dlsym(RTLD_NEXT, "sqlite3_step");
    if (!real_sql) real_sql = dlsym(RTLD_NEXT, "sqlite3_sql");
    int rc = real_step(stmt);
    record_sql("STEP", rc, real_sql ? real_sql(stmt) : NULL);
    return rc;
}
'''


def compile_auditor():
    src = '/tmp/sqlite_audit.c'
    with open(src, 'w') as f:
        f.write(AUDIT_C)
    subprocess.run(
        ['gcc', '-shared', '-fPIC', '-O2', '-o', AUDIT_SO, src, '-ldl'],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )


def run_program():
    for path in (CSV_PATH, AUDIT_LOG):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass
    env = os.environ.copy()
    env['LD_PRELOAD'] = AUDIT_SO
    env['SQLITE_AUDIT_LOG'] = AUDIT_LOG
    result = subprocess.run(
        [C_BIN_PATH], cwd='/home/user', env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    assert result.returncode == 0, (
        f'analyze exited with {result.returncode}\nstdout: {result.stdout}\nstderr: {result.stderr}'
    )
    assert os.path.exists(CSV_PATH), f'Output CSV file not found at {CSV_PATH}'
    assert os.path.isfile(CSV_PATH), f'Path {CSV_PATH} is not a file'
    with open(AUDIT_LOG, 'r', errors='replace') as f:
        audit = f.read()
    successful = []
    for line in audit.splitlines():
        m = re.match(r'^(EXEC|STEP) (0|100|101)\|(.*)$', line, re.I)
        if m:
            successful.append(m.group(3))
    normalized = ' '.join(successful).lower()
    assert re.search(r'\breindex\b', normalized), 'No successfully executed REINDEX statement was observed'
    selects = [s.lower() for s in successful if re.search(r'\bselect\b', s, re.I)]
    analytical = [s for s in selects if 'devices' in s and 'telemetry' in s and ' over' in s]
    assert analytical, 'No executed analytical SELECT joining devices and telemetry with a window function was observed'
    query = ' '.join(analytical)
    assert ('json_extract' in query or '->' in query), 'The executed query does not extract temperature from JSON'
    assert re.search(r'\b2\s+preceding\b', query), 'The window does not include the two preceding rows'
    return read_csv()


def read_csv():
    with open(CSV_PATH, 'r', newline='') as f:
        return list(csv.reader(f))


def assert_original_rows(actual_rows):
    assert len(actual_rows) > 0, 'The CSV file is empty.'
    assert actual_rows[0] == EXPECTED_ROWS[0], (
        f'CSV header mismatch. Expected {EXPECTED_ROWS[0]}, got {actual_rows[0]}'
    )
    assert len(actual_rows) == len(EXPECTED_ROWS), (
        f'CSV row count mismatch. Expected {len(EXPECTED_ROWS)} rows '
        f'(including header), got {len(actual_rows)}'
    )
    for i, (actual, expected) in enumerate(zip(actual_rows[1:], EXPECTED_ROWS[1:]), start=1):
        assert len(actual) == 4, f'Row {i} has {len(actual)} columns instead of 4'
        assert actual[0] == expected[0], f'Row {i}: device_name mismatch'
        assert actual[1] == expected[1], f'Row {i}: timestamp mismatch'
        try:
            assert abs(float(actual[2]) - float(expected[2])) < 0.001, f'Row {i}: temperature mismatch'
        except ValueError:
            pytest.fail(f'Row {i}: temperature could not be parsed as float: {actual[2]}')
        try:
            assert abs(float(actual[3]) - float(expected[3])) < 0.005, f'Row {i}: moving_avg mismatch'
            parts = actual[3].split('.')
            if len(parts) == 2:
                assert len(parts[1]) == 2, f'Row {i}: moving_avg should be rounded to 2 decimal places'
        except ValueError:
            pytest.fail(f'Row {i}: moving_avg could not be parsed as float: {actual[3]}')


def install_dynamic_database():
    for suffix in ('', '-wal', '-shm', '-journal'):
        try:
            os.remove(DB_PATH + suffix)
        except FileNotFoundError:
            pass

    rng = random.SystemRandom()
    tag = rng.randrange(100000, 999999)
    devices = [
        (17, f'Gamma_{tag}', 'Zone_C'),
        (4, f'Alpha_{tag}', 'Zone_A'),
        (29, f'Beta_{tag}', 'Zone_B'),
        (90, f'Unused_{tag}', 'Zone_X'),
    ]
    rows = []
    tid = 100
    for device_id, base in [(17, 31.0), (4, -3.0), (29, 12.0)]:
        for minute, delta in [(0, 0.2), (7, 2.7), (13, -1.1), (22, 4.4), (35, 8.9)]:
            temp = round(base + delta + rng.randrange(-5, 6) / 10.0, 1)
            ts = f'2025-04-03 09:{minute:02d}:00'
            payload = '{{"humidity":%d,"temp":%.1f,"status":"ok"}}' % (rng.randrange(20, 80), temp)
            rows.append((tid, device_id, ts, payload, temp))
            tid += rng.randrange(2, 6)
    rng.shuffle(rows)

    conn = sqlite3.connect(DB_PATH)
    conn.execute('CREATE TABLE devices (id INTEGER PRIMARY KEY, name TEXT, location TEXT)')
    conn.execute('CREATE TABLE telemetry (id INTEGER PRIMARY KEY, device_id INTEGER, ts DATETIME, payload TEXT)')
    conn.executemany('INSERT INTO devices VALUES (?, ?, ?)', devices)
    conn.executemany('INSERT INTO telemetry VALUES (?, ?, ?, ?)', [r[:4] for r in rows])
    conn.execute('CREATE INDEX idx_telemetry_device_ts ON telemetry(device_id, ts)')
    conn.execute('CREATE INDEX verifier_bad_index ON telemetry(device_id, id DESC)')
    conn.commit()

    roots = dict(conn.execute(
        "SELECT name, rootpage FROM sqlite_master WHERE name IN "
        "('idx_telemetry_device_ts','verifier_bad_index')"
    ))
    schema_version = conn.execute('PRAGMA schema_version').fetchone()[0]
    conn.execute('PRAGMA writable_schema=ON')
    conn.execute('UPDATE sqlite_master SET rootpage=? WHERE name=?',
                 (roots['verifier_bad_index'], 'idx_telemetry_device_ts'))
    conn.execute('UPDATE sqlite_master SET rootpage=? WHERE name=?',
                 (roots['idx_telemetry_device_ts'], 'verifier_bad_index'))
    conn.execute(f'PRAGMA schema_version={schema_version + 1}')
    conn.commit()
    conn.close()

    conn = sqlite3.connect(DB_PATH)
    conn.execute('DROP INDEX verifier_bad_index')
    conn.commit()
    before = [r[0] for r in conn.execute('PRAGMA integrity_check')]
    conn.close()
    assert before != ['ok'], 'Verifier failed to construct the deliberately inconsistent index'

    names = {device_id: name for device_id, name, _ in devices}
    grouped = {}
    for _, device_id, ts, _, temp in rows:
        grouped.setdefault(device_id, []).append((ts, temp))
    expected = []
    for device_id, values in grouped.items():
        values.sort(key=lambda x: x[0])
        prior = []
        for ts, temp in values:
            prior.append(temp)
            avg = sum(prior[-3:]) / len(prior[-3:])
            expected.append((names[device_id], ts, temp, avg))
    expected.sort(key=lambda r: (r[0], r[1]))
    return expected


def assert_dynamic_rows(actual, expected):
    assert actual and actual[0] == ['device_name', 'timestamp', 'temperature', 'moving_avg']
    assert len(actual) == len(expected) + 1
    for i, (row, exp) in enumerate(zip(actual[1:], expected), start=1):
        assert len(row) == 4, f'Dynamic row {i} does not contain exactly four columns'
        assert row[0] == exp[0], f'Dynamic row {i} is not ordered/joined correctly'
        assert row[1] == exp[1], f'Dynamic row {i} has the wrong timestamp/order'
        assert abs(float(row[2]) - exp[2]) < 0.001, f'Dynamic row {i} has the wrong JSON temperature'
        assert re.fullmatch(r'-?\d+\.\d{2}', row[3]), f'Dynamic row {i} moving_avg is not formatted to two decimals'
        assert abs(float(row[3]) - exp[3]) < 0.0051, f'Dynamic row {i} has the wrong three-row moving average'


def test_complete_program():
    assert os.path.exists(C_SOURCE_PATH), f'C source file not found at {C_SOURCE_PATH}'
    assert os.path.exists(C_BIN_PATH), f'Compiled C binary not found at {C_BIN_PATH}'
    assert os.path.isfile(C_BIN_PATH), f'Binary path {C_BIN_PATH} is not a file'
    assert os.access(C_BIN_PATH, os.X_OK), f'Binary at {C_BIN_PATH} is not executable'

    with open(C_SOURCE_PATH, 'r', errors='replace') as f:
        source = f.read().lower()
    assert 'sqlite3' in source, 'C source does not use the SQLite3 C API'
    assert re.search(r'\breindex\b', source), 'C source contains no REINDEX command'

    compile_auditor()

    # Preserve and exercise all original fixed-data assertions, but only on output
    # freshly produced by the submitted executable.
    original_rows = run_program()
    assert_original_rows(original_rows)

    # Replace the fixture after the agent has finished, corrupt the named index,
    # and require the executable to repair and analyze data it could not hardcode.
    expected = install_dynamic_database()
    dynamic_rows = run_program()
    assert_dynamic_rows(dynamic_rows, expected)

    conn = sqlite3.connect(DB_PATH)
    integrity = [r[0] for r in conn.execute('PRAGMA integrity_check')]
    conn.close()
    assert integrity == ['ok'], f'Database/index was not repaired by REINDEX: {integrity}'
PY_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

#!/bin/bash
mkdir -p /logs/verifier

cat <<'PY_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import sqlite3
import subprocess
import tempfile

SOURCE = '/home/user/filter_and_analyze.c'
AGENT_BINARY = '/home/user/filter_and_analyze'
DB = '/home/user/backup.db'
REPORT = '/home/user/report.csv'
VERIFIER_BINARY = '/tmp/verifier_filter_and_analyze'
TRACE = '/tmp/sql_trace.log'
PRELOAD_SOURCE = '/tmp/sql_trace.c'
PRELOAD_LIBRARY = '/tmp/sql_trace.so'

EXPECTED_ROWS = [
    (1, 101, 1000, 25.0),
    (2, 101, 1005, 26.5),
    (3, 101, 1005, 26.1),
    (4, 102, 1000, 15.0),
    (5, 101, 1010, 27.0),
    (6, 102, 1005, 14.5),
    (7, 102, 1010, 14.0),
    (8, 102, 1010, 14.8),
    (9, 103, 2000, 10.0),
    (10, 103, 2005, 12.0),
    (11, 103, 2005, 12.5),
    (12, 103, 2010, 11.0),
]

EXPECTED_CSV = '''sensor_id,epoch_time,reading,prev_reading,difference
101,1005,26.1,25.0,1.1
101,1010,27.0,26.1,0.9
102,1005,14.5,15.0,-0.5
102,1010,14.8,14.5,0.3
103,2005,12.5,10.0,2.5
103,2010,11.0,12.5,-1.5
'''

PRELOAD_CODE = r'''
#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static void log_sql(const char *sql, int n) {
    const char *path = getenv("SQL_TRACE_PATH");
    if (!path || !sql) return;
    FILE *f = fopen(path, "ab");
    if (!f) return;
    if (n < 0) n = (int)strlen(sql);
    fwrite(sql, 1, (size_t)n, f);
    fwrite("\n--END--\n", 1, 9, f);
    fclose(f);
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int n,
                       sqlite3_stmt **stmt, const char **tail) {
    typedef int (*fn_t)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **);
    static fn_t real_fn;
    if (!real_fn) real_fn = (fn_t)dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    log_sql(sql, n);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v3(sqlite3 *db, const char *sql, int n, unsigned int flags,
                       sqlite3_stmt **stmt, const char **tail) {
    typedef int (*fn_t)(sqlite3 *, const char *, int, unsigned int, sqlite3_stmt **, const char **);
    static fn_t real_fn;
    if (!real_fn) real_fn = (fn_t)dlsym(RTLD_NEXT, "sqlite3_prepare_v3");
    log_sql(sql, n);
    return real_fn(db, sql, n, flags, stmt, tail);
}

int sqlite3_prepare(sqlite3 *db, const char *sql, int n,
                    sqlite3_stmt **stmt, const char **tail) {
    typedef int (*fn_t)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **);
    static fn_t real_fn;
    if (!real_fn) real_fn = (fn_t)dlsym(RTLD_NEXT, "sqlite3_prepare");
    log_sql(sql, n);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_exec(sqlite3 *db, const char *sql,
                 int (*callback)(void *, int, char **, char **),
                 void *arg, char **errmsg) {
    typedef int (*fn_t)(sqlite3 *, const char *, int (*)(void *, int, char **, char **), void *, char **);
    static fn_t real_fn;
    if (!real_fn) real_fn = (fn_t)dlsym(RTLD_NEXT, "sqlite3_exec");
    log_sql(sql, -1);
    return real_fn(db, sql, callback, arg, errmsg);
}
'''


def database_rows():
    conn = sqlite3.connect(DB)
    try:
        return conn.execute(
            'SELECT id, sensor_id, epoch_time, reading FROM sensor_data ORDER BY id'
        ).fetchall()
    finally:
        conn.close()


def expected_csv_from_database():
    conn = sqlite3.connect(DB)
    try:
        rows = conn.execute('''
            SELECT id, sensor_id, epoch_time, reading
            FROM sensor_data
            ORDER BY sensor_id, epoch_time, id
        ''').fetchall()
    finally:
        conn.close()

    newest = {}
    for row_id, sensor_id, epoch_time, reading in rows:
        key = (sensor_id, epoch_time)
        if key not in newest or row_id > newest[key][0]:
            newest[key] = (row_id, float(reading))

    lines = ['sensor_id,epoch_time,reading,prev_reading,difference']
    by_sensor = {}
    for (sensor_id, epoch_time), (_, reading) in newest.items():
        by_sensor.setdefault(sensor_id, []).append((epoch_time, reading))

    for sensor_id in sorted(by_sensor):
        corrected = sorted(by_sensor[sensor_id])
        for index in range(1, len(corrected)):
            epoch_time, reading = corrected[index]
            previous = corrected[index - 1][1]
            lines.append(f'{sensor_id},{epoch_time},{reading:.1f},{previous:.1f},{reading - previous:.1f}')
    return '\n'.join(lines) + '\n'


def read_report():
    assert os.path.exists(REPORT), f'The report file {REPORT} was not generated.'
    with open(REPORT, 'r', newline='') as f:
        return f.read()


def run_program():
    if os.path.exists(REPORT):
        os.remove(REPORT)
    if os.path.exists(TRACE):
        os.remove(TRACE)
    env = os.environ.copy()
    env['LD_PRELOAD'] = PRELOAD_LIBRARY
    env['SQL_TRACE_PATH'] = TRACE
    result = subprocess.run(
        [VERIFIER_BINARY], cwd='/home/user', env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15
    )
    assert result.returncode == 0, (
        f'Compiled program exited with status {result.returncode}. stderr: {result.stderr}'
    )
    assert os.path.isfile(REPORT), 'The compiled C program did not generate /home/user/report.csv.'


def assert_window_queries_were_executed():
    assert os.path.exists(TRACE), 'The program did not execute a captured SQLite query.'
    with open(TRACE, 'r', errors='replace') as f:
        sql = re.sub(r'\s+', ' ', f.read()).upper()

    assert re.search(r'\bLAG\s*\([^)]*\)\s*OVER\s*\(', sql), (
        'The executed SQLite SQL did not use the required LAG window function.'
    )
    has_partition = (
        re.search(r'PARTITION\s+BY[^;]*SENSOR_ID[^;]*EPOCH_TIME', sql) or
        re.search(r'PARTITION\s+BY[^;]*EPOCH_TIME[^;]*SENSOR_ID', sql)
    )
    assert has_partition, (
        'The executed SQL did not partition duplicate detection by sensor_id and epoch_time.'
    )
    has_rank_dedup = re.search(
        r'\b(?:ROW_NUMBER|RANK|DENSE_RANK)\s*\(\s*\)\s*OVER\s*\(', sql
    ) and re.search(r'ORDER\s+BY[^;]*\bID\b[^;]*\bDESC\b', sql)
    has_max_dedup = re.search(r'\bMAX\s*\(\s*ID\s*\)\s*OVER\s*\(', sql)
    assert has_rank_dedup or has_max_dedup, (
        'The executed SQL did not use a window function to retain the maximum id duplicate.'
    )


def main():
    # Preserve the original source-existence assertion and require the requested binary artifact.
    assert os.path.exists(SOURCE), 'The C source file /home/user/filter_and_analyze.c is missing.'
    assert os.path.isfile(SOURCE), 'The C source path is not a regular file.'
    assert os.path.isfile(AGENT_BINARY) and os.access(AGENT_BINARY, os.X_OK), (
        'The compiled executable /home/user/filter_and_analyze is missing or not executable.'
    )
    assert os.path.exists(DB), f'{DB} does not exist.'

    # Preserve and strengthen the original database-unmodified assertion.
    initial_rows = database_rows()
    assert len(initial_rows) == 12, (
        f'The original database was modified! Expected 12 rows, but found {len(initial_rows)}.'
    )
    assert initial_rows == EXPECTED_ROWS, 'The original sensor_data contents were modified.'

    with open(PRELOAD_SOURCE, 'w') as f:
        f.write(PRELOAD_CODE)
    subprocess.run(
        ['gcc', '-shared', '-fPIC', PRELOAD_SOURCE, '-o', PRELOAD_LIBRARY, '-ldl', '-lsqlite3'],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )
    subprocess.run(
        ['gcc', '-std=c11', SOURCE, '-o', VERIFIER_BINARY, '-lsqlite3'],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20
    )

    fd, saved_db = tempfile.mkstemp(prefix='backup-original-', suffix='.db')
    os.close(fd)
    shutil.copy2(DB, saved_db)
    try:
        # Execute the submitted source against the original database and retain the original exact check.
        run_program()
        assert read_report().strip() == EXPECTED_CSV.strip(), (
            'The contents of report.csv do not match the expected output.'
        )
        assert_window_queries_were_executed()
        assert database_rows() == EXPECTED_ROWS, 'The C program modified the original database.'

        # Exercise the same program on unpredictable additional duplicates and sensor histories.
        conn = sqlite3.connect(DB)
        try:
            next_id = conn.execute('SELECT MAX(id) + 1 FROM sensor_data').fetchone()[0]
            new_sensor = 500 + secrets.randbelow(10000)
            base_time = 3000 + secrets.randbelow(100000)
            existing_value = (200 + secrets.randbelow(200)) / 10.0
            values = [(50 + secrets.randbelow(400)) / 10.0 for _ in range(4)]
            additions = [
                (next_id, 101, 1005, existing_value - 0.7),
                (next_id + 1, 101, 1005, existing_value),
                (next_id + 2, 101, base_time + 50, existing_value + 1.3),
                (next_id + 3, new_sensor, base_time, values[0]),
                (next_id + 4, new_sensor, base_time + 10, values[1]),
                (next_id + 5, new_sensor, base_time + 10, values[2]),
                (next_id + 6, new_sensor, base_time + 20, values[3]),
            ]
            conn.executemany('INSERT INTO sensor_data VALUES (?, ?, ?, ?)', additions)
            conn.commit()
        finally:
            conn.close()

        dynamic_expected = expected_csv_from_database()
        run_program()
        assert read_report().strip() == dynamic_expected.strip(), (
            'The C program did not correctly handle additional duplicate and sensor data.'
        )
        assert_window_queries_were_executed()
    finally:
        shutil.copy2(saved_db, DB)
        os.remove(saved_db)

    # Leave the requested report corresponding to the restored original backup.
    run_program()
    assert read_report().strip() == EXPECTED_CSV.strip(), (
        'The final report.csv does not match the original backup database.'
    )
    assert database_rows() == EXPECTED_ROWS, 'The original database was modified.'


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

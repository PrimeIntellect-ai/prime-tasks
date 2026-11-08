#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import sqlite3
import struct
import subprocess
import tempfile
from pathlib import Path

HOME = Path('/home/user')
DB = HOME / 'topology.db'
CPP = HOME / 'analyzer.cpp'
EXE = HOME / 'analyzer'
OUTPUT = HOME / 'critical_path.txt'
BUILT_EXE = Path('/tmp/analyzer_from_source')
TRACE_SO = Path('/tmp/sqlite_trace.so')


def test_critical_path_output():
    """Preserve the original exact-output assertion."""
    assert OUTPUT.exists(), f"Output file not found at {OUTPUT}"
    assert OUTPUT.is_file(), f"{OUTPUT} is not a regular file"
    content = OUTPUT.read_text().strip()
    assert content == 'MAX_LATENCY: 75', f"Expected 'MAX_LATENCY: 75', but got '{content}'"


def test_analyzer_cpp_exists_and_contains_cte():
    """Preserve the original source and recursive-CTE assertions."""
    assert CPP.exists(), f"C++ source file not found at {CPP}"
    assert CPP.is_file(), f"{CPP} is not a regular file"
    content = CPP.read_text()
    assert re.search(r'WITH\s+RECURSIVE', content, re.IGNORECASE), \
        'C++ source code does not contain a recursive CTE (WITH RECURSIVE)'
    assert re.search(r'#\s*include\s*[<\"]sqlite3\.h[>\"]', content), \
        'analyzer.cpp does not include sqlite3.h'


def test_analyzer_executable_exists():
    """Preserve the original executable assertions."""
    assert EXE.exists(), f"Compiled executable not found at {EXE}"
    assert EXE.is_file(), f"{EXE} is not a regular file"
    assert os.access(EXE, os.X_OK), f"{EXE} is not executable"


def test_database_was_optimized_and_is_healthy():
    """Check durable effects of REINDEX followed by VACUUM and index health."""
    raw = DB.read_bytes()
    assert raw[:16] == b'SQLite format 3\x00', 'topology.db is not a SQLite database'

    # Setup performs five committed writes and creates three schema objects.
    # REINDEX and VACUUM each commit a database rewrite; VACUUM also advances
    # the schema cookie while rebuilding the file.
    change_counter = struct.unpack('>I', raw[24:28])[0]
    schema_cookie = struct.unpack('>I', raw[40:44])[0]
    assert change_counter >= 7, \
        f'Database write counter is {change_counter}; REINDEX and VACUUM were not both performed'
    assert schema_cookie >= 4, \
        f'Schema cookie is {schema_cookie}; database does not show a VACUUM rebuild'

    con = sqlite3.connect(str(DB))
    try:
        assert con.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
        assert con.execute('PRAGMA freelist_count').fetchone()[0] == 0, \
            'Database still contains free pages; VACUUM was not effective'
        row = con.execute(
            "SELECT tbl_name FROM sqlite_master WHERE type='index' AND name='idx_source'"
        ).fetchone()
        assert row == ('dependencies',), 'idx_source is missing or belongs to the wrong table'
        plan = con.execute(
            'EXPLAIN QUERY PLAN SELECT * FROM dependencies WHERE source_id=?', (1,)
        ).fetchall()
        assert any('idx_source' in str(part) for item in plan for part in item), \
            'idx_source is not usable by SQLite'
    finally:
        con.close()


def _compile_submission():
    proc = subprocess.run(
        ['g++', '-std=c++17', str(CPP), '-lsqlite3', '-o', str(BUILT_EXE)],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert proc.returncode == 0, f'analyzer.cpp does not compile:\n{proc.stderr}'
    symbols = subprocess.run(
        ['nm', '-D', str(BUILT_EXE)], text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, check=True
    ).stdout
    assert re.search(r'\bsqlite3_(open|open_v2|prepare_v2|prepare_v3|exec)\b', symbols), \
        'Compiled analyzer does not use the SQLite C API'


def _build_trace_library():
    src = Path('/tmp/sqlite_trace.c')
    src.write_text(r'''
#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

static void record_sql(const char *sql) {
    const char *path = getenv("SQLITE_TRACE_FILE");
    if (!path || !sql) return;
    FILE *f = fopen(path, "a");
    if (f) { fputs(sql, f); fputc('\n', f); fclose(f); }
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int n, sqlite3_stmt **st, const char **tail) {
    static int (*real_fn)(sqlite3*,const char*,int,sqlite3_stmt**,const char**) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    record_sql(sql);
    return real_fn(db, sql, n, st, tail);
}

int sqlite3_prepare_v3(sqlite3 *db, const char *sql, int n, unsigned int flags,
                       sqlite3_stmt **st, const char **tail) {
    static int (*real_fn)(sqlite3*,const char*,int,unsigned int,sqlite3_stmt**,const char**) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v3");
    record_sql(sql);
    return real_fn(db, sql, n, flags, st, tail);
}

int sqlite3_exec(sqlite3 *db, const char *sql, sqlite3_callback cb, void *arg, char **err) {
    static int (*real_fn)(sqlite3*,const char*,sqlite3_callback,void*,char**) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_exec");
    record_sql(sql);
    return real_fn(db, sql, cb, arg, err);
}
''')
    proc = subprocess.run(
        ['gcc', '-shared', '-fPIC', str(src), '-ldl', '-o', str(TRACE_SO)],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE
    )
    assert proc.returncode == 0, f'Could not build SQLite trace helper: {proc.stderr}'


def _create_case(path, values):
    a, b, c, d, direct = values
    con = sqlite3.connect(str(path))
    try:
        con.executescript('''
            CREATE TABLE services (id INTEGER PRIMARY KEY, name TEXT, is_active INTEGER);
            CREATE TABLE dependencies (source_id INTEGER, target_id INTEGER, latency_ms INTEGER);
            INSERT INTO services VALUES
              (1,'API_GATEWAY',1), (2,'ACTIVE_A',1), (3,'ACTIVE_B',1),
              (4,'STALE_SERVICE',0), (5,'DATABASE_PRIMARY',1), (6,'DECOY',1);
        ''')
        con.executemany('INSERT INTO dependencies VALUES (?,?,?)', [
            (1, 2, a), (2, 5, b),
            (1, 3, c), (3, 5, d),
            (1, 5, direct),
            (1, 4, 1000000), (4, 5, 1000000),
            (6, 5, 999999),
        ])
        con.commit()
    finally:
        con.close()
    return max(a + b, c + d, direct)


def _run_case(binary, expected, trace_file):
    if OUTPUT.exists():
        OUTPUT.unlink()
    if trace_file.exists():
        trace_file.unlink()
    env = os.environ.copy()
    env['LD_PRELOAD'] = str(TRACE_SO)
    env['SQLITE_TRACE_FILE'] = str(trace_file)
    proc = subprocess.run(
        [str(binary)], cwd=str(HOME), env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert proc.returncode == 0, \
        f'{binary} failed on a valid database: stdout={proc.stdout!r}, stderr={proc.stderr!r}'
    assert OUTPUT.is_file(), f'{binary} did not create {OUTPUT}'
    content = OUTPUT.read_text().strip()
    assert content == f'MAX_LATENCY: {expected}', \
        f'{binary} returned {content!r}; expected MAX_LATENCY: {expected}'
    trace = trace_file.read_text() if trace_file.exists() else ''
    assert re.search(r'WITH\s+RECURSIVE', trace, re.IGNORECASE), \
        f'{binary} did not execute a Recursive CTE through the SQLite API'


def test_analyzer_behavior_recursive_cte_and_error_handling():
    _compile_submission()
    _build_trace_library()

    saved_db = Path('/tmp/original_topology.db')
    saved_output = Path('/tmp/original_critical_path.txt')
    shutil.copy2(DB, saved_db)
    shutil.copy2(OUTPUT, saved_output)

    try:
        # Values are deliberately different from the setup answer, and the
        # enormous inactive route detects failure to filter inactive services.
        cases = [
            (17, 31, 9, 12, 6),
            (4, 8, 37, 29, 11),
        ]
        for case_number, values in enumerate(cases):
            DB.unlink(missing_ok=True)
            expected = _create_case(DB, values)
            for binary_number, binary in enumerate((EXE, BUILT_EXE)):
                trace = Path(f'/tmp/sql_trace_{case_number}_{binary_number}.txt')
                _run_case(binary, expected, trace)

        # A malformed database must produce a checked, graceful failure rather
        # than success, a crash, or a fabricated result file.
        DB.write_bytes(b'not an sqlite database')
        OUTPUT.unlink(missing_ok=True)
        proc = subprocess.run(
            [str(BUILT_EXE)], cwd=str(HOME), text=True,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
        )
        assert proc.returncode > 0, \
            f'Analyzer did not report SQLite failure gracefully (return code {proc.returncode})'
        assert proc.stdout.strip() or proc.stderr.strip(), \
            'Analyzer returned an SQLite error without any diagnostic message'
        assert not OUTPUT.exists(), 'Analyzer created a result file after an SQLite error'
    finally:
        shutil.copy2(saved_db, DB)
        shutil.copy2(saved_output, OUTPUT)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

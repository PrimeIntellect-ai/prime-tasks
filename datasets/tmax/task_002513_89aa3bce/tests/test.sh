#!/bin/bash
set -e
mkdir -p /logs/verifier

DB=/home/user/metrics.db
LOG=/home/user/anomalies.log
cp -a "$DB" /tmp/metrics.db.verifier-backup
if [ -e "$LOG" ]; then
    cp -a "$LOG" /tmp/anomalies.log.verifier-backup
    HAD_LOG=1
else
    HAD_LOG=0
fi
cleanup() {
    cp -a /tmp/metrics.db.verifier-backup "$DB"
    if [ "$HAD_LOG" = 1 ]; then
        cp -a /tmp/anomalies.log.verifier-backup "$LOG"
    else
        rm -f "$LOG"
    fi
}
trap cleanup EXIT

cat <<'WRAP_EOF' > /tmp/sqlite_trace.c
#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void event(const char *s) {
    const char *path = getenv("SQLITE_TRACE_LOG");
    if (!path) return;
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (fd >= 0) {
        write(fd, s, strlen(s));
        write(fd, "\n", 1);
        close(fd);
    }
}

static void sql_event(const char *sql) {
    const char *path = getenv("SQLITE_TRACE_LOG");
    if (!path || !sql) return;
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (fd >= 0) {
        const char prefix[] = "SQL:";
        write(fd, prefix, sizeof(prefix) - 1);
        for (const char *p = sql; *p; ++p) {
            char c = (*p == '\n' || *p == '\r') ? ' ' : *p;
            write(fd, &c, 1);
        }
        write(fd, "\n", 1);
        close(fd);
    }
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    event("PREPARE");
    sql_event(sql);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_bind_text(sqlite3_stmt *s, int i, const char *v, int n, void (*d)(void *)) {
    static int (*real_fn)(sqlite3_stmt *, int, const char *, int, void (*)(void *));
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_bind_text");
    event("BIND_TEXT");
    return real_fn(s, i, v, n, d);
}

int sqlite3_bind_double(sqlite3_stmt *s, int i, double v) {
    static int (*real_fn)(sqlite3_stmt *, int, double);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_bind_double");
    event("BIND_DOUBLE");
    return real_fn(s, i, v);
}

int sqlite3_bind_int(sqlite3_stmt *s, int i, int v) {
    static int (*real_fn)(sqlite3_stmt *, int, int);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_bind_int");
    event("BIND_INT");
    return real_fn(s, i, v);
}

int sqlite3_bind_int64(sqlite3_stmt *s, int i, sqlite3_int64 v) {
    static int (*real_fn)(sqlite3_stmt *, int, sqlite3_int64);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_bind_int64");
    event("BIND_INT64");
    return real_fn(s, i, v);
}

int sqlite3_step(sqlite3_stmt *s) {
    static int (*real_fn)(sqlite3_stmt *);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_step");
    int rc = real_fn(s);
    if (rc == SQLITE_ROW) event("STEP_ROW");
    return rc;
}

int sqlite3_finalize(sqlite3_stmt *s) {
    static int (*real_fn)(sqlite3_stmt *);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_finalize");
    event("FINALIZE");
    return real_fn(s);
}

int sqlite3_close(sqlite3 *db) {
    static int (*real_fn)(sqlite3 *);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_close");
    event("CLOSE");
    return real_fn(db);
}

int sqlite3_close_v2(sqlite3 *db) {
    static int (*real_fn)(sqlite3 *);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_close_v2");
    event("CLOSE");
    return real_fn(db);
}
WRAP_EOF

gcc -shared -fPIC /tmp/sqlite_trace.c -o /tmp/sqlite_trace.so -ldl -lsqlite3

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import sqlite3
import subprocess

SRC = '/home/user/analyze_metrics.c'
EXE = '/home/user/analyze_metrics'
DB = '/home/user/metrics.db'
LOG = '/home/user/anomalies.log'
PRELOAD = '/tmp/sqlite_trace.so'


def test_anomalies_log_content():
    assert os.path.exists(LOG), f"{LOG} does not exist."
    with open(LOG, 'r') as f:
        content = f.read()
    expected = "Server: server_A, TS: 103, CPU: 40.00, MA: 21.00"
    assert content in (expected, expected + "\n"), f"Expected exactly '{expected}', but found:\n{content}"


def test_c_source_code_parameterized_queries():
    assert os.path.exists(SRC), f"Source file {SRC} does not exist."
    with open(SRC, 'r') as f:
        src_content = f.read()
    assert 'sqlite3_prepare_v2' in src_content, "The C source code must use sqlite3_prepare_v2."
    assert 'sqlite3_bind_' in src_content, "The C source code must use sqlite3_bind_* functions."


def test_executable_exists():
    assert os.path.exists(EXE), f"Executable {EXE} does not exist."
    assert os.access(EXE, os.X_OK), f"File {EXE} is not executable."
    with open(EXE, 'rb') as f:
        assert f.read(4) == b'\x7fELF', "The submitted executable is not a compiled ELF program."


def expected_lines(rows, server_id, multiplier):
    selected = sorted((ts, cpu) for sid, ts, cpu in rows if sid == server_id)
    result = []
    for i, (ts, cpu) in enumerate(selected):
        avg = sum(v for _, v in selected[max(0, i - 2):i + 1]) / len(selected[max(0, i - 2):i + 1])
        if cpu > avg * multiplier:
            result.append(f"Server: {server_id}, TS: {ts}, CPU: {cpu:.2f}, MA: {avg:.2f}")
    return result


def install_database(rows):
    if os.path.exists(DB):
        os.unlink(DB)
    con = sqlite3.connect(DB)
    con.execute('CREATE TABLE server_metrics (server_id TEXT, timestamp INTEGER, cpu_usage REAL)')
    con.executemany('INSERT INTO server_metrics VALUES (?, ?, ?)', rows)
    con.commit()
    con.close()
    os.chmod(DB, 0o666)


def run_and_check(program, rows, server_id, multiplier, append=False):
    expected = expected_lines(rows, server_id, multiplier)
    if not append:
        with open(LOG, 'w'):
            pass
    before = []
    if append and os.path.exists(LOG):
        with open(LOG) as f:
            before = f.read().splitlines()

    trace = '/tmp/sqlite_runtime.trace'
    open(trace, 'w').close()
    env = os.environ.copy()
    env['LD_PRELOAD'] = PRELOAD
    env['SQLITE_TRACE_LOG'] = trace
    proc = subprocess.run([program, server_id, str(multiplier)], env=env,
                          stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                          text=True, timeout=10)
    assert proc.returncode == 0, f"Program failed: {proc.stderr}"
    assert os.path.exists(LOG), "Program did not create anomalies.log"
    with open(LOG) as f:
        actual = f.read().splitlines()
    assert actual == before + expected, f"Incorrect output. Expected {before + expected}, got {actual}"

    with open(trace) as f:
        events = f.read().splitlines()
    assert 'PREPARE' in events, "The running program did not call sqlite3_prepare_v2."
    assert 'BIND_TEXT' in events, "The running program did not bind the server_id with sqlite3_bind_text."
    assert 'FINALIZE' in events, "The prepared statement was not finalized."
    assert 'CLOSE' in events, "The SQLite connection was not closed."
    assert events.count('STEP_ROW') == len(expected), "The query itself must return only anomalous rows."
    sql = ' '.join(e[4:] for e in events if e.startswith('SQL:')).upper()
    for token in ('AVG', 'OVER', 'ROWS', 'PRECEDING'):
        assert token in sql, f"The prepared query is missing required rolling-window SQL token {token}."


def test_runtime_behavior_and_submitted_source():
    rows = [
        ('alpha', 10, 9.0), ('alpha', 20, 12.0), ('alpha', 30, 15.0),
        ('alpha', 40, 60.0), ('alpha', 50, 6.0), ('alpha', 60, 30.0),
        ("odd' OR 1=1 --", 5, 5.0), ("odd' OR 1=1 --", 15, 50.0),
        ('unrelated', 1, 999.0), ('unrelated', 2, 1.0),
    ]
    install_database(rows)

    run_and_check(EXE, rows, 'alpha', 1.5)
    run_and_check(EXE, rows, "odd' OR 1=1 --", 1.1, append=True)

    built = '/tmp/analyze_metrics_from_source'
    compile_proc = subprocess.run(['gcc', SRC, '-o', built, '-lsqlite3'],
                                  stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                                  text=True, timeout=20)
    assert compile_proc.returncode == 0, f"Source does not compile: {compile_proc.stderr}"
    run_and_check(built, rows, 'alpha', 0.75)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

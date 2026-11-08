#!/bin/bash
set +e
mkdir -p /logs/verifier

cat > /tmp/sqlite_audit.c <<'AUDIT_C'
#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <stdarg.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/syscall.h>
#include <time.h>
#include <unistd.h>

static long long now_ms(void) {
    struct timespec ts;
    clock_gettime(CLOCK_MONOTONIC, &ts);
    return (long long)ts.tv_sec * 1000 + ts.tv_nsec / 1000000;
}

static void audit_log(const char *fmt, ...) {
    const char *path = getenv("SQLITE_AUDIT_LOG");
    if (!path || !*path) return;
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (fd < 0) return;
    char buf[1200];
    va_list ap;
    va_start(ap, fmt);
    int n = vsnprintf(buf, sizeof(buf), fmt, ap);
    va_end(ap);
    if (n > 0) {
        if (n > (int)sizeof(buf)) n = sizeof(buf);
        write(fd, buf, n);
    }
    close(fd);
}

static void clean_sql(const char *in, char *out, size_t n) {
    size_t j = 0;
    if (!in) in = "";
    for (size_t i = 0; in[i] && j + 1 < n; ++i) {
        char c = in[i];
        if (c == '\n' || c == '\r' || c == '|') c = ' ';
        out[j++] = c;
    }
    out[j] = 0;
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int nbyte,
                       sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    int rc = real_fn(db, sql, nbyte, stmt, tail);
    char text[700]; clean_sql(sql, text, sizeof(text));
    audit_log("PREP|%lld|%ld|%p|%d|%s\n", now_ms(), (long)syscall(SYS_gettid),
              stmt ? (void *)*stmt : NULL, rc, text);
    return rc;
}

int sqlite3_bind_int(sqlite3_stmt *stmt, int idx, int value) {
    static int (*real_fn)(sqlite3_stmt *, int, int);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_bind_int");
    int rc = real_fn(stmt, idx, value);
    audit_log("BINDI|%lld|%ld|%p|%d|%d|%d\n", now_ms(),
              (long)syscall(SYS_gettid), (void *)stmt, idx, value, rc);
    return rc;
}

int sqlite3_bind_int64(sqlite3_stmt *stmt, int idx, sqlite3_int64 value) {
    static int (*real_fn)(sqlite3_stmt *, int, sqlite3_int64);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_bind_int64");
    int rc = real_fn(stmt, idx, value);
    audit_log("BINDI|%lld|%ld|%p|%d|%lld|%d\n", now_ms(),
              (long)syscall(SYS_gettid), (void *)stmt, idx, (long long)value, rc);
    return rc;
}

int sqlite3_bind_double(sqlite3_stmt *stmt, int idx, double value) {
    static int (*real_fn)(sqlite3_stmt *, int, double);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_bind_double");
    int rc = real_fn(stmt, idx, value);
    audit_log("BINDD|%lld|%ld|%p|%d|%.17g|%d\n", now_ms(),
              (long)syscall(SYS_gettid), (void *)stmt, idx, value, rc);
    return rc;
}

int sqlite3_step(sqlite3_stmt *stmt) {
    static int (*real_fn)(sqlite3_stmt *);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_step");
    int rc = real_fn(stmt);
    if ((rc & 255) == SQLITE_BUSY)
        audit_log("BUSY|%lld|%ld|STEP|%d\n", now_ms(),
                  (long)syscall(SYS_gettid), rc);
    return rc;
}

int sqlite3_exec(sqlite3 *db, const char *sql,
                 int (*callback)(void *, int, char **, char **),
                 void *arg, char **errmsg) {
    static int (*real_fn)(sqlite3 *, const char *, int (*)(void *, int, char **, char **), void *, char **);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_exec");
    int rc = real_fn(db, sql, callback, arg, errmsg);
    char text[700]; clean_sql(sql, text, sizeof(text));
    audit_log("EXEC|%lld|%ld|%d|%s\n", now_ms(),
              (long)syscall(SYS_gettid), rc, text);
    if ((rc & 255) == SQLITE_BUSY)
        audit_log("BUSY|%lld|%ld|EXEC|%d\n", now_ms(),
                  (long)syscall(SYS_gettid), rc);
    return rc;
}
AUDIT_C

cat > /tmp/test_final_state.py <<'TEST_EOF'
import os
import re
import shutil
import sqlite3
import subprocess

DB_PATH = "/home/user/graph.db"
RANK_FILE = "/home/user/rank.txt"
ERROR_FILE = "/home/user/error.txt"
CPP_FILE = "/home/user/pipeline.cpp"
SH_FILE = "/home/user/run.sh"
AUDIT_SO = "/tmp/sqlite_audit.so"

# Preserve the original final-state assertions.
def test_files_exist():
    assert os.path.isfile(CPP_FILE), f"Source file {CPP_FILE} is missing."
    assert os.path.isfile(SH_FILE), f"Bash script {SH_FILE} is missing."
    assert os.path.isfile(RANK_FILE), f"Output file {RANK_FILE} is missing."
    assert os.path.isfile(ERROR_FILE), f"Output file {ERROR_FILE} is missing."


def test_database_index_exists():
    assert os.path.isfile(DB_PATH), f"Database {DB_PATH} is missing."
    with sqlite3.connect(DB_PATH) as conn:
        result = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_edges_src_dst'"
        ).fetchone()
        assert result is not None, "Index 'idx_edges_src_dst' was not found in the database."
        assert result[0] == "idx_edges_src_dst"


def test_database_inserted_edge():
    with sqlite3.connect(DB_PATH) as conn:
        result = conn.execute(
            "SELECT weight FROM edges WHERE src=100 AND dst=200"
        ).fetchone()
        assert result is not None, "The edge with src=100 and dst=200 was not found."
        assert abs(result[0] - 1.5) < 1e-5, f"Expected weight 1.5, but got {result[0]}."


def test_rank_output():
    with open(RANK_FILE) as f:
        content = f.read().strip()
    assert content == "2", f"Expected rank.txt to contain '2', but got '{content}'."


def test_error_output():
    with open(ERROR_FILE) as f:
        content = f.read().strip()
    assert content == "5", f"Expected error.txt to contain '5' (SQLITE_BUSY), but got '{content}'."


def reset_database():
    for suffix in ("", "-wal", "-shm", "-journal"):
        try:
            os.remove(DB_PATH + suffix)
        except FileNotFoundError:
            pass
    with sqlite3.connect(DB_PATH) as conn:
        conn.executescript("""
            CREATE TABLE nodes(id INTEGER PRIMARY KEY, name TEXT);
            CREATE TABLE edges(src INTEGER, dst INTEGER, weight REAL);
            INSERT INTO nodes VALUES
                (10,'A'),(100,'B'),(200,'C'),(300,'D'),(400,'E'),(500,'F'),(600,'G');
            INSERT INTO edges VALUES
                (10,300,100.0),
                (20,400,90.0),
                (200,500,80.0),
                (30,200,1.0);
        """)
    os.chmod(DB_PATH, 0o666)
    for path in (RANK_FILE, ERROR_FILE):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def expected_rank_after_insert():
    with sqlite3.connect(DB_PATH) as conn:
        conn.execute("INSERT INTO edges(src,dst,weight) VALUES(100,200,1.5)")
        row = conn.execute("""
            WITH totals AS (
              SELECT dst, SUM(weight) AS total FROM edges GROUP BY dst
            ), ranked AS (
              SELECT dst, DENSE_RANK() OVER (ORDER BY total DESC) AS r FROM totals
            )
            SELECT r FROM ranked WHERE dst=200
        """).fetchone()
        conn.rollback()
    return str(row[0])


def parse_trace(path):
    assert os.path.isfile(path), "No SQLite API trace was produced"
    with open(path, errors="replace") as f:
        return [line.strip() for line in f if line.strip()]


def validate_trace(lines):
    assert any(line.startswith("BUSY|") for line in lines), \
        "Execution did not actually receive an SQLITE_BUSY result from SQLite"

    prep = []
    binds = []
    sql_events = []
    for line in lines:
        parts = line.split("|", 5)
        if line.startswith("PREP|") and len(parts) == 6:
            _, ms, tid, ptr, rc, sql = parts
            prep.append((int(ms), tid, ptr, sql))
            sql_events.append((int(ms), tid, sql))
        elif line.startswith("EXEC|") and len(parts) == 5:
            _, ms, tid, rc, sql = parts
            sql_events.append((int(ms), tid, sql))
        elif line.startswith(("BINDI|", "BINDD|")):
            binds.append(line.split("|"))

    insert_preps = [p for p in prep if "INSERT" in p[3].upper() and "EDGES" in p[3].upper()]
    insert_preps = [p for p in insert_preps if p[3].count("?") >= 3]
    assert insert_preps, "The edge insertion was not executed as a parameterized prepared statement"
    ptr = insert_preps[0][2]
    own_binds = [b for b in binds if len(b) >= 7 and b[3] == ptr]
    values = {(b[0], int(b[4]), b[5]) for b in own_binds}
    assert ("BINDI", 1, "100") in values, "src=100 was not bound with a SQLite bind API"
    assert ("BINDI", 2, "200") in values, "dst=200 was not bound with a SQLite bind API"
    assert any(k == "BINDD" and i == 3 and abs(float(v) - 1.5) < 1e-12
               for k, i, v in values), "weight=1.5 was not bound with sqlite3_bind_double"

    assert any("DENSE_RANK" in sql.upper() and "SUM" in sql.upper() and "OVER" in sql.upper()
               for _, _, _, sql in prep), "No executed analytical query used SUM and DENSE_RANK OVER"

    def events_matching(pattern):
        rx = re.compile(pattern, re.I | re.S)
        return [(ms, tid, sql) for ms, tid, sql in sql_events if rx.search(sql)]

    up_a = events_matching(r"UPDATE\s+EDGES.*SRC\s*=\s*100")
    up_b = events_matching(r"UPDATE\s+EDGES.*SRC\s*=\s*200")
    assert up_a and up_b, "Both required concurrent UPDATE statements were not executed"
    tid_a, tid_b = up_a[0][1], up_b[0][1]
    assert tid_a != tid_b, "The two UPDATE statements did not run in distinct threads"

    def thread_has(tid, pattern):
        return any(t == tid and re.search(pattern, sql, re.I | re.S)
                   for _, t, sql in sql_events)

    for tid in (tid_a, tid_b):
        assert thread_has(tid, r"\bBEGIN\b"), "A worker did not execute BEGIN"
        assert thread_has(tid, r"SELECT\s+COUNT\s*\(\s*\*\s*\)\s+FROM\s+EDGES"), \
            "A worker did not execute SELECT COUNT(*) FROM edges"

    a_select = [ms for ms, tid, sql in sql_events if tid == tid_a and
                re.search(r"SELECT\s+COUNT", sql, re.I)]
    a_update = [ms for ms, tid, sql in sql_events if tid == tid_a and
                re.search(r"UPDATE\s+EDGES.*SRC\s*=\s*100", sql, re.I | re.S)]
    assert a_select and a_update and max(a_update) - min(a_select) >= 150, \
        "Thread A did not pause approximately 200ms before its update"

    a_begin = [ms for ms, tid, sql in sql_events if tid == tid_a and re.search(r"\bBEGIN\b", sql, re.I)]
    b_begin = [ms for ms, tid, sql in sql_events if tid == tid_b and re.search(r"\bBEGIN\b", sql, re.I)]
    assert a_begin and b_begin and min(b_begin) - min(a_begin) >= 25, \
        "Thread B did not start after the required initial delay"


def validate_outputs(expected):
    assert os.path.isfile(RANK_FILE), "Execution did not create rank.txt"
    assert os.path.isfile(ERROR_FILE), "Execution did not create error.txt"
    with open(RANK_FILE) as f:
        assert f.read().strip() == expected
    with open(ERROR_FILE) as f:
        assert f.read().strip() == str(sqlite3.SQLITE_BUSY)

    with sqlite3.connect(DB_PATH) as conn:
        index = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_edges_src_dst'"
        ).fetchone()
        assert index is not None
        columns = [r[2] for r in conn.execute("PRAGMA index_info('idx_edges_src_dst')")]
        assert columns == ["src", "dst"], f"Index has wrong columns: {columns}"
        rows = conn.execute(
            "SELECT weight FROM edges WHERE src=100 AND dst=200"
        ).fetchall()
        assert len(rows) == 1 and abs(rows[0][0] - 1.5) < 1e-9


def run_and_check(command, trace_path, expected):
    try:
        os.remove(trace_path)
    except FileNotFoundError:
        pass
    env = os.environ.copy()
    env["LD_PRELOAD"] = AUDIT_SO
    env["SQLITE_AUDIT_LOG"] = trace_path
    result = subprocess.run(command, cwd="/home/user", env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
                            text=True, timeout=20)
    assert result.returncode == 0, f"Execution failed:\n{result.stdout}"
    validate_outputs(expected)
    validate_trace(parse_trace(trace_path))


def test_source_and_actual_execution():
    source = open(CPP_FILE, errors="replace").read()
    assert re.search(r"#\s*include\s*[<\"]sqlite3\.h[>\"]", source)
    assert re.search(r"#\s*include\s*[<\"]thread[>\"]", source)
    assert re.search(r"#\s*include\s*[<\"]chrono[>\"]", source)
    assert "sqlite3_prepare_v2" in source
    assert "sqlite3_bind" in source
    assert re.search(r"DENSE_RANK\s*\(", source, re.I)
    assert re.search(r"SUM\s*\(", source, re.I)
    assert re.search(r"std\s*::\s*thread", source)

    # First exercise the required run.sh on data whose rank differs from the
    # original hardcoded answer.
    reset_database()
    expected = expected_rank_after_insert()
    assert expected != "2"
    run_and_check(["bash", SH_FILE], "/tmp/sqlite_trace_runsh.log", expected)

    # Compile pipeline.cpp independently, then execute that exact artifact so
    # run.sh cannot substitute a different implementation.
    reset_database()
    expected = expected_rank_after_insert()
    binary = "/tmp/pipeline_under_test"
    result = subprocess.run(
        ["g++", "-std=c++17", CPP_FILE, "-lsqlite3", "-pthread", "-o", binary],
        stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, timeout=20)
    assert result.returncode == 0, f"pipeline.cpp did not compile:\n{result.stdout}"
    run_and_check([binary], "/tmp/sqlite_trace_binary.log", expected)
TEST_EOF

if gcc -shared -fPIC -O2 /tmp/sqlite_audit.c -o /tmp/sqlite_audit.so -ldl && \
   python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

#!/bin/bash
mkdir -p /logs/verifier

cat <<'SHIM_EOF' > /tmp/sqlite_trace_shim.c
#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void log_sql(const char *sql) {
    const char *path = getenv("VERIFIER_SQL_TRACE");
    if (!path || !sql) return;
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd >= 0) {
        write(fd, sql, strlen(sql));
        write(fd, "\n", 1);
        close(fd);
    }
}

int sqlite3_exec(sqlite3 *db, const char *sql, sqlite3_callback cb, void *arg, char **errmsg) {
    static int (*real_fn)(sqlite3 *, const char *, sqlite3_callback, void *, char **);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_exec");
    log_sql(sql);
    return real_fn(db, sql, cb, arg, errmsg);
}

int sqlite3_prepare(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare");
    log_sql(sql);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    log_sql(sql);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v3(sqlite3 *db, const char *sql, int n, unsigned int flags, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, unsigned int, sqlite3_stmt **, const char **);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v3");
    log_sql(sql);
    return real_fn(db, sql, n, flags, stmt, tail);
}
SHIM_EOF

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import sqlite3
import subprocess

DB = "/home/user/backup_graph.db"
LOG = "/home/user/backup_plan.log"
SOURCE = "/home/user/resolver.c"
EXECUTABLE = "/home/user/resolver"
COMPILED_SOURCE = "/tmp/resolver_compiled_from_source"
SHIM = "/tmp/sqlite_trace_shim.so"

EXPECTED_BASELINE = [
    "Phase 0: storage-array",
    "Phase 1: db-primary",
    "Phase 2: cache-node",
    "Phase 2: db-replica",
    "Phase 3: app-server-1",
    "Phase 3: app-server-2",
    "Phase 4: load-balancer",
]


def run_program(path, trace=None):
    if os.path.exists(LOG):
        os.remove(LOG)
    env = os.environ.copy()
    if trace:
        open(trace, "w").close()
        env["LD_PRELOAD"] = SHIM
        env["VERIFIER_SQL_TRACE"] = trace
    result = subprocess.run([path], cwd="/home/user", env=env,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, timeout=15)
    assert result.returncode == 0, (
        f"{path} exited with {result.returncode}. stderr: {result.stderr}"
    )
    assert os.path.exists(LOG), f"{path} did not generate {LOG}."


def read_lines():
    with open(LOG, "r") as f:
        return [line.strip() for line in f.readlines() if line.strip()]


def test_00_execute_submitted_program():
    assert os.path.exists(EXECUTABLE), f"Executable {EXECUTABLE} does not exist."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    run_program(EXECUTABLE)


def test_c_file_exists_and_includes_sqlite():
    """Keep the original source-file assertion and ensure it really compiles."""
    assert os.path.exists(SOURCE), f"C source file {SOURCE} does not exist."
    with open(SOURCE, "r") as f:
        content = f.read()
    assert "#include" in content and "sqlite3.h" in content, \
        "resolver.c does not seem to include sqlite3.h."
    built = subprocess.run(
        ["gcc", "-O2", SOURCE, "-o", COMPILED_SOURCE, "-lsqlite3"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=20)
    assert built.returncode == 0, f"resolver.c does not compile: {built.stderr}"


def test_executable_exists():
    """Keep the original executable assertions."""
    assert os.path.exists(EXECUTABLE), f"Executable {EXECUTABLE} does not exist."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."


def test_index_created():
    """Keep the original assertion that an index was created."""
    assert os.path.exists(DB), f"Database file {DB} does not exist."
    conn = sqlite3.connect(DB)
    indexes = conn.execute(
        "SELECT name FROM sqlite_master WHERE type='index' AND tbl_name='dependencies'"
    ).fetchall()
    conn.close()
    assert len(indexes) > 0, "No index was created on the 'dependencies' table."


def test_output_file_correct():
    """Keep the original exact expected-result assertions."""
    assert os.path.exists(LOG), f"Output file {LOG} does not exist."
    lines = read_lines()
    assert len(lines) == len(EXPECTED_BASELINE), \
        f"Expected {len(EXPECTED_BASELINE)} lines, but got {len(lines)}."
    for i, (actual, expected) in enumerate(zip(lines, EXPECTED_BASELINE)):
        assert actual == expected, \
            f"Line {i+1} mismatch: expected '{expected}', got '{actual}'."


def create_dynamic_database(token):
    names = [f"node-{token}-{secrets.token_hex(3)}" for _ in range(8)]
    edges = [
        (3, 1),
        (4, 1), (4, 2),
        (5, 3),
        (6, 3), (6, 4),
        (7, 5), (7, 6),
    ]
    for suffix in ("", "-wal", "-shm"):
        try:
            os.remove(DB + suffix)
        except FileNotFoundError:
            pass
    conn = sqlite3.connect(DB)
    conn.executescript("""
        CREATE TABLE servers (id INTEGER PRIMARY KEY, hostname TEXT NOT NULL);
        CREATE TABLE dependencies (
            server_id INTEGER,
            depends_on_id INTEGER,
            FOREIGN KEY(server_id) REFERENCES servers(id),
            FOREIGN KEY(depends_on_id) REFERENCES servers(id)
        );
        CREATE TABLE stale_routes_cache (server_id INTEGER, route_path TEXT);
    """)
    conn.executemany("INSERT INTO servers(id, hostname) VALUES (?, ?)",
                     [(i + 1, name) for i, name in enumerate(names)])
    conn.executemany(
        "INSERT INTO dependencies(server_id, depends_on_id) VALUES (?, ?)", edges)
    conn.executemany(
        "INSERT INTO stale_routes_cache(server_id, route_path) VALUES (?, ?)",
        [(i, "corrupt->circular->corrupt") for i in range(1, 9)])
    conn.commit()
    conn.close()
    os.chmod(DB, 0o666)

    deps = {i: [] for i in range(1, 9)}
    for server, dependency in edges:
        deps[server].append(dependency)
    phases = {}
    remaining = set(deps)
    while remaining:
        progressed = False
        for server in list(remaining):
            if all(dep in phases for dep in deps[server]):
                phases[server] = 0 if not deps[server] else 1 + max(phases[d] for d in deps[server])
                remaining.remove(server)
                progressed = True
        assert progressed
    return [f"Phase {phases[i]}: {names[i-1]}"
            for i in sorted(phases, key=lambda x: (phases[x], names[x-1]))]


def assert_real_sql_work(program, label):
    expected = create_dynamic_database(secrets.token_hex(5))
    trace = f"/tmp/{label}.sqltrace"
    run_program(program, trace)
    assert read_lines() == expected, \
        f"{program} did not calculate phases for a fresh, unknown dependency graph."

    with open(trace, "r", errors="replace") as f:
        sql = f.read()
    normalized = re.sub(r"\s+", " ", sql).upper()
    assert "WITH RECURSIVE" in normalized, \
        f"{program} did not execute a recursive CTE through the SQLite C API."
    assert "STALE_ROUTES_CACHE" not in normalized, \
        f"{program} queried the forbidden stale_routes_cache table."
    assert re.search(r"CREATE\s+(?:UNIQUE\s+)?INDEX\b.*\bON\s+[^;]*DEPENDENCIES", normalized), \
        f"{program} did not execute CREATE INDEX on dependencies."

    conn = sqlite3.connect(DB)
    useful = False
    for row in conn.execute("PRAGMA index_list('dependencies')"):
        cols = [r[2].lower() for r in conn.execute(
            "PRAGMA index_info(%s)" % ("'" + row[1].replace("'", "''") + "'"))]
        if cols and cols[0] == "depends_on_id":
            useful = True
    conn.close()
    assert useful, \
        "No traversal index with leading column dependencies.depends_on_id was created."


def test_dynamic_graph_and_actual_sql_execution():
    """Exercise both the submitted binary and a fresh build of resolver.c."""
    assert os.path.exists(COMPILED_SOURCE), "Freshly compiled resolver.c is unavailable."
    db_backup = "/tmp/original_backup_graph.db"
    log_backup = "/tmp/original_backup_plan.log"
    shutil.copy2(DB, db_backup)
    had_log = os.path.exists(LOG)
    if had_log:
        shutil.copy2(LOG, log_backup)
    try:
        assert_real_sql_work(EXECUTABLE, "submitted_resolver")
        assert_real_sql_work(COMPILED_SOURCE, "compiled_source_resolver")
    finally:
        for suffix in ("", "-wal", "-shm"):
            try:
                os.remove(DB + suffix)
            except FileNotFoundError:
                pass
        shutil.copy2(db_backup, DB)
        if had_log:
            shutil.copy2(log_backup, LOG)
        else:
            try:
                os.remove(LOG)
            except FileNotFoundError:
                pass
TEST_EOF

if gcc -shared -fPIC /tmp/sqlite_trace_shim.c -o /tmp/sqlite_trace_shim.so -ldl -lsqlite3 \
   && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

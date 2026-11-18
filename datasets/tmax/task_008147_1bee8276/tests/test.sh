#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TRACE_EOF' > /tmp/sqlite_trace.c
#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void log_sql(const char *sql, int nbyte) {
    const char *path = getenv("TRACE_SQL_PATH");
    if (!path || !sql) return;
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0600);
    if (fd < 0) return;
    size_t n = nbyte < 0 ? strlen(sql) : (size_t)nbyte;
    write(fd, sql, n);
    write(fd, "\n--END-SQL--\n", 13);
    close(fd);
}

int sqlite3_prepare(sqlite3 *db, const char *sql, int nbyte,
                    sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare");
    log_sql(sql, nbyte);
    return real_fn(db, sql, nbyte, stmt, tail);
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int nbyte,
                       sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    log_sql(sql, nbyte);
    return real_fn(db, sql, nbyte, stmt, tail);
}

int sqlite3_prepare_v3(sqlite3 *db, const char *sql, int nbyte, unsigned flags,
                       sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, unsigned, sqlite3_stmt **, const char **);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v3");
    log_sql(sql, nbyte);
    return real_fn(db, sql, nbyte, flags, stmt, tail);
}

int sqlite3_exec(sqlite3 *db, const char *sql,
                 int (*callback)(void *, int, char **, char **),
                 void *arg, char **errmsg) {
    static int (*real_fn)(sqlite3 *, const char *, int (*)(void *, int, char **, char **), void *, char **);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_exec");
    log_sql(sql, -1);
    return real_fn(db, sql, callback, arg, errmsg);
}
TRACE_EOF

gcc -shared -fPIC -o /tmp/sqlite_trace.so /tmp/sqlite_trace.c -ldl

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import sqlite3
import subprocess
import tempfile
from collections import deque

SOURCE = "/home/user/find_restore_path.c"
EXECUTABLE = "/home/user/find_restore_path"
OUTPUT = "/home/user/path_output.txt"
DATABASE = "/home/user/backups.db"
TRACE = "/tmp/executed_sql.log"
PRELOAD = "/tmp/sqlite_trace.so"
EXPECTED_ORIGINAL = "RESTORE_PATH: 42 -> 8 -> 3 -> 1"


def test_c_source_file_exists():
    assert os.path.isfile(SOURCE), f"C source file {SOURCE} is missing."


def test_executable_exists_and_is_executable():
    assert os.path.isfile(EXECUTABLE), f"Executable file {EXECUTABLE} is missing."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."


def test_output_file_content():
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} is missing."
    with open(OUTPUT, "r") as f:
        content = f.read().strip()
    assert EXPECTED_ORIGINAL in content, (
        f"Output file content is incorrect. Expected to find "
        f"'{EXPECTED_ORIGINAL}', but got:\n{content}"
    )


def compile_submission():
    with open(SOURCE, "r", errors="replace") as f:
        source = f.read()
    assert re.search(r"#\s*include\s*[<\"]sqlite3\.h[>\"]", source), \
        "The source must include sqlite3.h."
    assert re.search(r"\bsqlite3_open(?:_v2)?\s*\(", source), \
        "The source must open the database through the SQLite C API."
    assert re.search(r"\bsqlite3_(?:prepare(?:_v[23])?|exec)\s*\(", source), \
        "The source must execute SQL through the SQLite C API."

    result = subprocess.run(
        ["gcc", "-std=c11", "-O2", SOURCE, "-o", EXECUTABLE, "-lsqlite3"],
        text=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert result.returncode == 0, f"C source did not compile:\n{result.stderr}"
    assert os.path.isfile(EXECUTABLE) and os.access(EXECUTABLE, os.X_OK)


def run_submission():
    open(TRACE, "w").close()
    env = os.environ.copy()
    env["LD_PRELOAD"] = PRELOAD
    env["TRACE_SQL_PATH"] = TRACE
    try:
        result = subprocess.run(
            [EXECUTABLE], text=True, stdout=subprocess.PIPE,
            stderr=subprocess.PIPE, env=env, timeout=6
        )
    except subprocess.TimeoutExpired:
        raise AssertionError("The program did not terminate (the graph may contain cycles).")

    assert result.returncode == 0, (
        f"Program exited with status {result.returncode}. stderr:\n{result.stderr}"
    )
    with open(TRACE, "r", errors="replace") as f:
        sql = f.read()
    assert re.search(r"\bWITH\s+RECURSIVE\b", sql, re.I), \
        "The running program did not execute a recursive CTE."
    assert re.search(r"\bdeps\b", sql, re.I) and re.search(r"\bbackups\b", sql, re.I), \
        "The recursive query must use both deps and backups."
    assert re.search(r"\bis_base_backup\b", sql, re.I), \
        "The recursive query must identify a base backup."
    return result.stdout.strip()


def parse_path(output):
    assert re.fullmatch(r"RESTORE_PATH: 42(?: -> [0-9]+)+", output), \
        f"Output does not exactly match the required schema: {output!r}"
    return [int(x) for x in re.findall(r"[0-9]+", output)]


def shortest_distance(edges, bases):
    adjacency = {}
    for a, b in edges:
        adjacency.setdefault(a, []).append(b)
    queue = deque([(42, 0)])
    seen = {42}
    while queue:
        node, distance = queue.popleft()
        if node in bases:
            return distance
        for nxt in adjacency.get(node, []):
            if nxt not in seen:
                seen.add(nxt)
                queue.append((nxt, distance + 1))
    return None


def install_database(nodes, bases, edges):
    for suffix in ("", "-wal", "-shm"):
        try:
            os.remove(DATABASE + suffix)
        except FileNotFoundError:
            pass
    con = sqlite3.connect(DATABASE)
    con.executescript("""
        CREATE TABLE backups (id INTEGER PRIMARY KEY, name TEXT, is_base_backup INTEGER);
        CREATE TABLE deps (backup_id INTEGER, depends_on INTEGER);
    """)
    con.executemany(
        "INSERT INTO backups(id, name, is_base_backup) VALUES (?, ?, ?)",
        [(n, f"backup_{n}", int(n in bases)) for n in nodes]
    )
    con.executemany("INSERT INTO deps(backup_id, depends_on) VALUES (?, ?)", edges)
    con.commit()
    con.close()


def random_case():
    rng = secrets.SystemRandom()
    chosen = set()
    while len(chosen) < 20:
        chosen.add(rng.randrange(1000, 1000000000))
    others = list(chosen)
    nodes = [42] + others
    bases = set(rng.sample(others, 2))
    nonbases = [n for n in others if n not in bases]

    target = rng.choice(list(bases))
    chain = [42] + rng.sample(nonbases, rng.randint(2, 5)) + [target]
    edges = set(zip(chain, chain[1:]))

    for _ in range(40):
        edges.add((rng.choice(nodes), rng.choice(nodes)))
    cycle_node = rng.choice(nonbases)
    edges.add((cycle_node, cycle_node))
    return nodes, bases, list(edges)


def validate_path(output, edges, bases):
    path = parse_path(output)
    edge_set = set(edges)
    assert all(pair in edge_set for pair in zip(path, path[1:])), \
        f"Output contains an edge not present in deps: {path}"
    assert path[-1] in bases, f"Path does not end at a base backup: {path}"
    expected_distance = shortest_distance(edges, bases)
    assert expected_distance is not None
    assert len(path) - 1 == expected_distance, \
        f"Path is not shortest: got {len(path)-1} edges, expected {expected_distance}."


def test_compiled_program_executes_recursive_query_and_computes_shortest_paths():
    compile_submission()

    original_stdout = run_submission()
    assert original_stdout == EXPECTED_ORIGINAL, (
        f"Program gave the wrong result for the supplied database: {original_stdout!r}"
    )

    fd, saved_db = tempfile.mkstemp(prefix="backups-original-", suffix=".db")
    os.close(fd)
    shutil.copyfile(DATABASE, saved_db)
    try:
        for _ in range(3):
            nodes, bases, edges = random_case()
            install_database(nodes, bases, edges)
            validate_path(run_submission(), edges, bases)
    finally:
        for suffix in ("", "-wal", "-shm"):
            try:
                os.remove(DATABASE + suffix)
            except FileNotFoundError:
                pass
        shutil.copyfile(saved_db, DATABASE)
        os.remove(saved_db)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

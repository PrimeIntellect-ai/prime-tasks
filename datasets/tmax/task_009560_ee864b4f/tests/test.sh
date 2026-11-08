#!/bin/bash
set -e
mkdir -p /logs/verifier
reward=0
trap 'echo "$reward" > /logs/verifier/reward.txt' EXIT

cat << 'TRACE_EOF' > /tmp/audit_sqlite_trace.c
#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

static void log_line(const char *kind, const char *value) {
    const char *path = getenv("AUDIT_TRACE_FILE");
    if (!path) return;
    FILE *f = fopen(path, "a");
    if (!f) return;
    fprintf(f, "%s %s\n", kind, value ? value : "(null)");
    fclose(f);
}

int sqlite3_open(const char *filename, sqlite3 **ppDb) {
    static int (*real_fn)(const char *, sqlite3 **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_open");
    log_line("OPEN", filename);
    return real_fn(filename, ppDb);
}

int sqlite3_open_v2(const char *filename, sqlite3 **ppDb, int flags, const char *zVfs) {
    static int (*real_fn)(const char *, sqlite3 **, int, const char *) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_open_v2");
    log_line("OPEN", filename);
    return real_fn(filename, ppDb, flags, zVfs);
}

int sqlite3_exec(sqlite3 *db, const char *sql, int (*callback)(void *, int, char **, char **), void *arg, char **errmsg) {
    static int (*real_fn)(sqlite3 *, const char *, int (*)(void *, int, char **, char **), void *, char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_exec");
    log_line("SQL", sql);
    return real_fn(db, sql, callback, arg, errmsg);
}

int sqlite3_prepare(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare");
    log_line("SQL", sql);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    log_line("SQL", sql);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v3(sqlite3 *db, const char *sql, int n, unsigned int flags, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, unsigned int, sqlite3_stmt **, const char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v3");
    log_line("SQL", sql);
    return real_fn(db, sql, n, flags, stmt, tail);
}
TRACE_EOF

gcc -shared -fPIC /tmp/audit_sqlite_trace.c -o /tmp/libaudit_sqlite_trace.so -ldl

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import subprocess
from collections import defaultdict, deque

SOURCE = "/home/user/audit_tool.c"
EXECUTABLE = "/home/user/audit_tool"
COMPILED_SOURCE = "/tmp/audit_tool_from_source"
GRAPH = "/home/user/access_graph.csv"
RESTRICTED = "/home/user/restricted_systems.csv"
REPORT = "/home/user/compliance_report.csv"
TRACE_LIB = "/tmp/libaudit_sqlite_trace.so"


def run_tool(path, timeout=10):
    trace = "/tmp/sqlite_trace_" + secrets.token_hex(8)
    if os.path.exists(REPORT):
        os.remove(REPORT)
    env = os.environ.copy()
    env["LD_PRELOAD"] = TRACE_LIB
    env["AUDIT_TRACE_FILE"] = trace
    result = subprocess.run([path], env=env, stdout=subprocess.PIPE,
                            stderr=subprocess.PIPE, text=True, timeout=timeout)
    assert result.returncode == 0, (
        f"{path} exited with {result.returncode}. stderr: {result.stderr}"
    )
    assert os.path.isfile(REPORT), f"{path} did not generate {REPORT}"
    assert os.path.isfile(trace), f"{path} did not call the traced SQLite API"
    with open(trace, "r", encoding="utf-8", errors="replace") as f:
        calls = f.read()
    assert re.search(r"^OPEN :memory:$", calls, re.MULTILINE), (
        f"{path} did not open an SQLite :memory: database"
    )
    assert re.search(r"WITH\s+RECURSIVE", calls, re.IGNORECASE), (
        f"{path} did not execute a WITH RECURSIVE SQL statement"
    )


def read_report():
    with open(REPORT, "r", encoding="utf-8") as f:
        content = [line.strip() for line in f.read().splitlines() if line.strip()]
    if content and content[0].lower().startswith("user"):
        content = content[1:]
    parsed = []
    for line in content:
        fields = line.split(",")
        assert len(fields) == 2, f"Malformed report line: {line!r}"
        try:
            count = int(fields[1])
        except ValueError:
            raise AssertionError(f"Non-integer access count in line: {line!r}")
        parsed.append((fields[0], count))
    return parsed


def write_inputs(edges, restricted):
    with open(GRAPH, "w", encoding="utf-8", newline="") as f:
        for source, target in edges:
            f.write(f"{source},{target}\n")
    with open(RESTRICTED, "w", encoding="utf-8", newline="") as f:
        for system in restricted:
            f.write(f"{system}\n")


def expected_report(edges, restricted):
    adjacency = defaultdict(set)
    users = set()
    for source, target in edges:
        adjacency[source].add(target)
        if source.startswith("USR_"):
            users.add(source)
        if target.startswith("USR_"):
            users.add(target)
    restricted_set = set(restricted)
    result = []
    for user in users:
        seen = {user}
        queue = deque([user])
        while queue:
            node = queue.popleft()
            for target in adjacency[node]:
                if target not in seen:
                    seen.add(target)
                    queue.append(target)
        count = len(seen & restricted_set)
        if count > 0:
            result.append((user, count))
    return sorted(result, key=lambda item: (-item[1], item[0]))


def test_audit_tool_source_exists_and_uses_required_api():
    assert os.path.isfile(SOURCE), f"Source file {SOURCE} is missing."
    source = open(SOURCE, "r", encoding="utf-8", errors="replace").read()
    without_comments = re.sub(r"/\*.*?\*/|//[^\n]*", "", source, flags=re.DOTALL)
    assert re.search(r"#\s*include\s*[<\"]sqlite3\.h[>\"]", without_comments)
    assert ":memory:" in without_comments
    assert re.search(r"\bsqlite3_open(?:_v2)?\s*\(", without_comments)
    assert re.search(r"\bsqlite3_(?:exec|prepare(?:_v[23])?)\s*\(", without_comments)
    assert re.search(r"WITH\s+RECURSIVE", without_comments, re.IGNORECASE)
    result = subprocess.run(
        ["gcc", SOURCE, "-o", COMPILED_SOURCE, "-lsqlite3"],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    assert result.returncode == 0, f"Source does not compile: {result.stderr}"


def test_audit_tool_executable_exists():
    assert os.path.isfile(EXECUTABLE), f"Executable file {EXECUTABLE} is missing."
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."


def test_compliance_report_exists_and_correct():
    run_tool(EXECUTABLE)
    expected_lines = [
        ("USR_Alice", 3),
        ("USR_Bob", 1),
        ("USR_Diana", 1),
        ("USR_Eve", 1),
    ]
    assert read_report() == expected_lines


def test_tools_recompute_report_from_changed_inputs():
    nonce = secrets.token_hex(5)
    users = [f"USR_{nonce}_{i}" for i in range(6)]
    groups = [f"GRP_{nonce}_{i}" for i in range(5)]
    systems = [f"SRV_RESTRICTED_{nonce}_{i}" for i in range(4)]
    public = f"SRV_PUBLIC_{nonce}"

    edges = [
        (users[0], groups[0]),
        (groups[0], systems[0]),
        (groups[0], systems[1]),
        (users[0], systems[0]),
        (users[1], groups[1]),
        (groups[1], groups[2]),
        (groups[2], systems[2]),
        (users[1], groups[3]),
        (groups[3], systems[2]),
        (users[2], systems[3]),
        (users[3], groups[4]),
        (groups[4], public),
        (users[4], groups[0]),
        (users[5], groups[1]),
        (groups[1], systems[0]),
        (groups[1], systems[1]),
        (users[0], groups[0]),
    ]
    expected = expected_report(edges, systems)
    write_inputs(edges, systems)

    for tool in (EXECUTABLE, COMPILED_SOURCE):
        run_tool(tool)
        assert read_report() == expected, (
            f"{tool} produced the wrong distinct counts or ordering"
        )


def test_tools_handle_no_restricted_access():
    nonce = secrets.token_hex(5)
    edges = [
        (f"USR_{nonce}_A", f"GRP_{nonce}_A"),
        (f"GRP_{nonce}_A", f"SRV_PUBLIC_{nonce}"),
        (f"USR_{nonce}_B", f"SRV_OTHER_{nonce}"),
    ]
    restricted = [f"SRV_RESTRICTED_{nonce}"]
    write_inputs(edges, restricted)
    for tool in (EXECUTABLE, COMPILED_SOURCE):
        run_tool(tool)
        assert read_report() == [], f"{tool} included a user with zero restricted access"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    reward=1
fi

#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import pwd
import random
import shutil
import sqlite3
import subprocess
import tempfile

DB_PATH = "/home/user/research_data.db"
TSV_PATH = "/home/user/cycles.tsv"
SOURCE_PATH = "/home/user/extract_pattern.cpp"
EXE_PATH = "/home/user/extract_pattern"


def get_expected_cycles(db_path):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    query = """
    SELECT c1.source_id, c2.source_id, c3.source_id
    FROM citations c1
    JOIN citations c2 ON c1.target_id = c2.source_id
    JOIN citations c3 ON c2.target_id = c3.source_id AND c3.target_id = c1.source_id
    JOIN papers p1 ON c1.source_id = p1.id
    JOIN papers p2 ON c2.source_id = p2.id
    JOIN papers p3 ON c3.source_id = p3.id
    WHERE p1.year >= 2020 AND p2.year >= 2020 AND p3.year >= 2020
    """
    cursor.execute(query)
    rows = cursor.fetchall()
    conn.close()
    return sorted({tuple(sorted(row)) for row in rows})


def read_and_check_tsv(expected):
    assert os.path.exists(TSV_PATH), f"Output file {TSV_PATH} is missing."
    with open(TSV_PATH, "r") as f:
        lines = [line.strip() for line in f.read().splitlines() if line.strip()]

    actual = []
    for i, line in enumerate(lines):
        parts = line.split('\t')
        assert len(parts) == 3, (
            f"Line {i+1} in {TSV_PATH} does not contain exactly 3 "
            f"tab-separated values: '{line}'"
        )
        try:
            ids = tuple(int(p) for p in parts)
        except ValueError:
            raise AssertionError(
                f"Line {i+1} in {TSV_PATH} contains non-integer values: '{line}'"
            )
        actual.append(ids)

    assert actual == expected, (
        f"Contents of {TSV_PATH} do not match the expected cycles. "
        f"Expected: {expected}, Actual: {actual}"
    )


def test_cpp_source_exists():
    assert os.path.exists(SOURCE_PATH), "C++ source file /home/user/extract_pattern.cpp is missing."


def test_executable_exists():
    assert os.path.exists(EXE_PATH), f"Executable {EXE_PATH} is missing."
    assert os.access(EXE_PATH, os.X_OK), f"File {EXE_PATH} is not executable."


def test_cycles_tsv_output():
    assert os.path.exists(TSV_PATH), f"Output file {TSV_PATH} is missing."
    read_and_check_tsv(get_expected_cycles(DB_PATH))


def build_trace_library(workdir):
    trace_c = os.path.join(workdir, "sqlite_trace.c")
    trace_so = os.path.join(workdir, "sqlite_trace.so")
    code = r'''
#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>

static void mark(const char *kind, const char *sql) {
    const char *path = getenv("SQLITE_TRACE_PATH");
    if (!path) return;
    FILE *f = fopen(path, "a");
    if (!f) return;
    if (sql) fprintf(f, "%s\n%s\nENDQUERY\n", kind, sql);
    else fprintf(f, "%s\n", kind);
    fclose(f);
}

int sqlite3_open(const char *name, sqlite3 **db) {
    static int (*real_fn)(const char *, sqlite3 **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_open");
    mark("OPEN", NULL);
    return real_fn(name, db);
}

int sqlite3_open_v2(const char *name, sqlite3 **db, int flags, const char *vfs) {
    static int (*real_fn)(const char *, sqlite3 **, int, const char *) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_open_v2");
    mark("OPEN", NULL);
    return real_fn(name, db, flags, vfs);
}

int sqlite3_prepare(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare");
    mark("QUERY", sql);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    mark("QUERY", sql);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v3(sqlite3 *db, const char *sql, int n, unsigned int flags, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, unsigned int, sqlite3_stmt **, const char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v3");
    mark("QUERY", sql);
    return real_fn(db, sql, n, flags, stmt, tail);
}

int sqlite3_exec(sqlite3 *db, const char *sql, int (*cb)(void*,int,char**,char**), void *arg, char **err) {
    static int (*real_fn)(sqlite3 *, const char *, int (*)(void*,int,char**,char**), void *, char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_exec");
    mark("QUERY", sql);
    return real_fn(db, sql, cb, arg, err);
}

int sqlite3_get_table(sqlite3 *db, const char *sql, char ***result, int *rows, int *cols, char **err) {
    static int (*real_fn)(sqlite3 *, const char *, char ***, int *, int *, char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_get_table");
    mark("QUERY", sql);
    return real_fn(db, sql, result, rows, cols, err);
}
'''
    with open(trace_c, "w") as f:
        f.write(code)
    subprocess.run(
        ["gcc", "-shared", "-fPIC", trace_c, "-ldl", "-o", trace_so],
        check=True, capture_output=True, text=True
    )
    return trace_so


def install_random_fixture():
    rng = random.SystemRandom()
    ids = rng.sample(range(10000, 900000), 12)
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("DELETE FROM citations")
    cur.execute("DELETE FROM papers")
    years = [2021, 2022, 2024, 2020, 2023, 2025, 2018, 2022, 2023, 2024, 2019, 2021]
    cur.executemany(
        "INSERT INTO papers(id, title, year) VALUES (?, ?, ?)",
        [(paper_id, f"dynamic-{i}", years[i]) for i, paper_id in enumerate(ids)]
    )
    edges = [
        (ids[0], ids[1]), (ids[1], ids[2]), (ids[2], ids[0]),
        (ids[3], ids[4]), (ids[4], ids[5]), (ids[5], ids[3]),
        (ids[6], ids[7]), (ids[7], ids[8]), (ids[8], ids[6]),
        (ids[0], ids[1]),
        (ids[0], ids[9]), (ids[9], ids[10]),
        (ids[11], ids[4]), (ids[2], ids[8])
    ]
    cur.executemany("INSERT INTO citations(source_id, target_id) VALUES (?, ?)", edges)
    conn.commit()
    conn.close()
    return get_expected_cycles(DB_PATH)


def run_and_verify(executable, trace_so, trace_path):
    expected = install_random_fixture()
    if os.path.exists(TSV_PATH):
        os.remove(TSV_PATH)
    with open(trace_path, "w"):
        pass
    os.chmod(trace_path, 0o666)

    user = pwd.getpwnam("user")
    env = os.environ.copy()
    env["LD_PRELOAD"] = trace_so
    env["SQLITE_TRACE_PATH"] = trace_path

    def demote():
        os.setgid(user.pw_gid)
        os.setuid(user.pw_uid)

    result = subprocess.run(
        [executable], cwd="/home/user", env=env, preexec_fn=demote,
        capture_output=True, text=True, timeout=15
    )
    assert result.returncode == 0, (
        f"{executable} exited with status {result.returncode}. "
        f"stdout: {result.stdout!r}, stderr: {result.stderr!r}"
    )
    read_and_check_tsv(expected)

    with open(trace_path, "r", errors="replace") as f:
        trace = f.read()
    assert "OPEN\n" in trace, "Program did not open the database through the SQLite3 C API."
    queries = re.findall(r"QUERY\n(.*?)\nENDQUERY", trace, flags=re.DOTALL)
    suitable = []
    for query in queries:
        upper = query.upper()
        if (upper.count("JOIN") >= 5 and "CITATIONS" in upper and
                "PAPERS" in upper and "YEAR" in upper):
            suitable.append(query)
    assert suitable, (
        "Program did not execute the required complex SQLite join over citations "
        "and papers with the year filter."
    )


def test_program_is_real_sqlite_implementation():
    with open(SOURCE_PATH, "r", errors="replace") as f:
        source = f.read()
    uncommented = re.sub(r"/\*.*?\*/", "", source, flags=re.DOTALL)
    uncommented = re.sub(r"//[^\n]*", "", uncommented)
    assert re.search(r"#\s*include\s*[<\"]sqlite3\.h[>\"]", uncommented), \
        "Source must include sqlite3.h."
    assert re.search(r"\bsqlite3_open(?:_v2)?\s*\(", uncommented), \
        "Source must open the database with the SQLite3 C API."
    assert re.search(r"\bsqlite3_(?:prepare(?:_v2|_v3)?|exec|get_table)\s*\(", uncommented), \
        "Source must execute SQL through the SQLite3 C API."
    assert uncommented.upper().count("JOIN") >= 5, \
        "Source does not contain the required complex SQL joins."

    with open(EXE_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/extract_pattern is not a compiled ELF executable."

    workdir = tempfile.mkdtemp(prefix="verify_extract_", dir="/tmp")
    db_backup = os.path.join(workdir, "research_data.db")
    shutil.copy2(DB_PATH, db_backup)
    cycles_existed = os.path.exists(TSV_PATH)
    cycles_backup = os.path.join(workdir, "cycles.tsv")
    if cycles_existed:
        shutil.copy2(TSV_PATH, cycles_backup)

    try:
        rebuilt = os.path.join(workdir, "extract_pattern_rebuilt")
        compile_result = subprocess.run(
            ["g++", "-std=c++17", SOURCE_PATH, "-lsqlite3", "-o", rebuilt],
            capture_output=True, text=True, timeout=30
        )
        assert compile_result.returncode == 0, (
            "extract_pattern.cpp does not compile with SQLite3: " + compile_result.stderr
        )
        os.chmod(rebuilt, 0o755)
        trace_so = build_trace_library(workdir)
        os.chmod(trace_so, 0o755)

        run_and_verify(EXE_PATH, trace_so, os.path.join(workdir, "submitted.trace"))
        run_and_verify(rebuilt, trace_so, os.path.join(workdir, "rebuilt.trace"))
    finally:
        shutil.copy2(db_backup, DB_PATH)
        if cycles_existed:
            shutil.copy2(cycles_backup, TSV_PATH)
        elif os.path.exists(TSV_PATH):
            os.remove(TSV_PATH)
        shutil.rmtree(workdir, ignore_errors=True)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

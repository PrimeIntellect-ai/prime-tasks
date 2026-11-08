#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import sqlite3
import subprocess

OUTPUT_FILE = "/home/user/charlie_permissions.txt"
C_SOURCE_FILE = "/home/user/audit_resolver.c"
BINARY_FILE = "/home/user/audit_resolver"
DATABASE_FILE = "/home/user/audit.db"
TRACE_FILE = "/tmp/audit_sqlite_trace.log"
TEST_BINARY = "/tmp/audit_resolver_from_source"
SHIM_SOURCE = "/tmp/sqlite_trace.c"
SHIM_LIBRARY = "/tmp/sqlite_trace.so"

EXPECTED_PERMISSIONS = [
    "EXPORT_AUDIT_LOGS",
    "INTERNAL_LOGIN",
    "READ_WIKI",
    "VIEW_FINANCIALS",
    "VIEW_PUBLIC_PAGES"
]

SHIM_CODE = r'''
#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <fcntl.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

static void log_item(const char *kind, const char *value) {
    const char *path = getenv("AUDIT_TRACE");
    if (!path) return;
    int fd = open(path, O_WRONLY | O_CREAT | O_APPEND, 0666);
    if (fd < 0) return;
    write(fd, "@@", 2);
    write(fd, kind, strlen(kind));
    write(fd, "@@\n", 3);
    if (value) write(fd, value, strlen(value));
    write(fd, "\n@@END@@\n", 10);
    close(fd);
}

int sqlite3_open(const char *filename, sqlite3 **db) {
    static int (*real_fn)(const char *, sqlite3 **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_open");
    log_item("OPEN", filename);
    return real_fn(filename, db);
}

int sqlite3_open_v2(const char *filename, sqlite3 **db, int flags, const char *vfs) {
    static int (*real_fn)(const char *, sqlite3 **, int, const char *) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_open_v2");
    log_item("OPEN", filename);
    return real_fn(filename, db, flags, vfs);
}

int sqlite3_exec(sqlite3 *db, const char *sql, int (*cb)(void*,int,char**,char**), void *arg, char **errmsg) {
    static int (*real_fn)(sqlite3 *, const char *, int (*)(void*,int,char**,char**), void *, char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_exec");
    log_item("SQL", sql);
    return real_fn(db, sql, cb, arg, errmsg);
}

int sqlite3_prepare(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare");
    log_item("SQL", sql);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    log_item("SQL", sql);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v3(sqlite3 *db, const char *sql, int n, unsigned int flags, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, unsigned int, sqlite3_stmt **, const char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v3");
    log_item("SQL", sql);
    return real_fn(db, sql, n, flags, stmt, tail);
}

int sqlite3_get_table(sqlite3 *db, const char *sql, char ***result, int *rows, int *cols, char **errmsg) {
    static int (*real_fn)(sqlite3 *, const char *, char ***, int *, int *, char **) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_get_table");
    log_item("SQL", sql);
    return real_fn(db, sql, result, rows, cols, errmsg);
}
'''


def test_source_and_binary_exist():
    """Verify that the C source code and compiled binary exist."""
    assert os.path.isfile(C_SOURCE_FILE), f"C source file not found at {C_SOURCE_FILE}"
    assert os.path.isfile(BINARY_FILE), f"Compiled binary not found at {BINARY_FILE}"
    assert os.access(BINARY_FILE, os.X_OK), f"Compiled file at {BINARY_FILE} is not executable"


def test_output_file_exists_and_correct():
    """Verify that the output file exists and contains the correct resolved permissions."""
    assert os.path.isfile(OUTPUT_FILE), f"Output file not found at {OUTPUT_FILE}"

    with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines == EXPECTED_PERMISSIONS, (
        f"Output file contents do not match expected permissions.\n"
        f"Expected: {EXPECTED_PERMISSIONS}\n"
        f"Found: {lines}"
    )


def build_fixture():
    for path in (DATABASE_FILE, DATABASE_FILE + "-wal", DATABASE_FILE + "-shm", OUTPUT_FILE, TRACE_FILE):
        if os.path.exists(path):
            os.remove(path)

    token = secrets.token_hex(6).upper()
    permissions = [
        f"ALPHA_{token}",
        f"DIRECT_{token}",
        f"MID_{token}",
        f"ROOT_{token}",
        f"ZETA_{token}",
    ]

    con = sqlite3.connect(DATABASE_FILE)
    con.executescript(f"""
        CREATE TABLE users (user_id INTEGER PRIMARY KEY, username TEXT);
        CREATE TABLE roles (role_id INTEGER PRIMARY KEY, role_name TEXT);
        CREATE TABLE user_roles (user_id INTEGER, role_id INTEGER);
        CREATE TABLE role_inheritance (parent_role_id INTEGER, child_role_id INTEGER);
        CREATE TABLE role_permissions (role_id INTEGER, permission_name TEXT);

        INSERT INTO users VALUES (77, 'Charlie_Compliance'), (88, 'Someone_Else');
        INSERT INTO roles VALUES
            (101, 'AssignedLeaf'), (102, 'ParentOne'), (103, 'ParentTwo'),
            (104, 'RootRole'), (201, 'SecondDirect'), (999, 'Unrelated');
        INSERT INTO user_roles VALUES (77, 101), (77, 201), (88, 999);
        INSERT INTO role_inheritance VALUES (102, 101), (103, 102), (104, 103);
        INSERT INTO role_permissions VALUES
            (101, '{permissions[4]}'),
            (102, '{permissions[2]}'),
            (103, '{permissions[0]}'),
            (104, '{permissions[3]}'),
            (201, '{permissions[1]}'),
            (201, '{permissions[1]}'),
            (999, 'MUST_NOT_APPEAR_{token}');

        CREATE INDEX idx_user_roles ON user_roles(user_id);
        CREATE INDEX idx_inheritance ON role_inheritance(child_role_id);

        CREATE TABLE reindex_probe(value TEXT);
        INSERT INTO reindex_probe VALUES ('one'), ('two'), ('three');
        CREATE INDEX idx_reindex_probe ON reindex_probe(value);
    """)

    # Change the declared index expression without rebuilding its btree. A real
    # REINDEX repairs this deliberately inconsistent index.
    con.execute("PRAGMA writable_schema=ON")
    con.execute(
        "UPDATE sqlite_master SET sql=? WHERE type='index' AND name='idx_reindex_probe'",
        ("CREATE INDEX idx_reindex_probe ON reindex_probe((value || '_suffix'))",),
    )
    schema_version = con.execute("PRAGMA schema_version").fetchone()[0]
    con.execute(f"PRAGMA schema_version={schema_version + 1}")
    con.commit()
    con.close()

    check = sqlite3.connect(DATABASE_FILE)
    before = [row[0] for row in check.execute("PRAGMA integrity_check")]
    check.close()
    assert before != ["ok"], "Verifier failed to construct the REINDEX test fixture"
    return sorted(set(permissions))


def check_execution(executable):
    expected = build_fixture()
    env = os.environ.copy()
    env["LD_PRELOAD"] = SHIM_LIBRARY
    env["AUDIT_TRACE"] = TRACE_FILE
    result = subprocess.run(
        [executable], cwd="/home/user", env=env,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=15
    )
    assert result.returncode == 0, (
        f"{executable} failed with exit code {result.returncode}:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT_FILE), "Resolver did not create the requested output file"
    with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
        actual = [line.strip() for line in f if line.strip()]
    assert actual == expected, f"Dynamic permission result was {actual}, expected {expected}"

    con = sqlite3.connect(DATABASE_FILE)
    after = [row[0] for row in con.execute("PRAGMA integrity_check")]
    con.close()
    assert after == ["ok"], "The deliberately inconsistent index was not repaired by REINDEX"

    assert os.path.isfile(TRACE_FILE), "No SQLite C API activity was observed"
    trace = open(TRACE_FILE, "r", encoding="utf-8", errors="replace").read()
    assert "/home/user/audit.db" in trace, "Program did not open the required database through SQLite"
    sql_blocks = re.findall(r"@@SQL@@\n(.*?)\n@@END@@", trace, flags=re.DOTALL)
    assert any(re.fullmatch(r"\s*REINDEX\s*;?\s*", sql, flags=re.IGNORECASE) for sql in sql_blocks), (
        "Program did not execute REINDEX through the SQLite C API"
    )
    recursive = [sql.lower() for sql in sql_blocks if re.search(r"\bwith\s+recursive\b", sql, re.I)]
    assert any(all(table in sql for table in
                   ("users", "user_roles", "role_inheritance", "role_permissions"))
               for sql in recursive), (
        "No recursive CTE traversing the access-control tables was executed through SQLite"
    )


def test_binary_and_source_execute_real_sqlite_work():
    with open(BINARY_FILE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "The requested compiled binary is not an ELF executable"

    with open(SHIM_SOURCE, "w", encoding="utf-8") as f:
        f.write(SHIM_CODE)
    subprocess.run(
        ["gcc", "-shared", "-fPIC", SHIM_SOURCE, "-o", SHIM_LIBRARY, "-ldl"],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )
    subprocess.run(
        ["gcc", C_SOURCE_FILE, "-o", TEST_BINARY, "-lsqlite3"],
        check=True, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True
    )

    original_db = open(DATABASE_FILE, "rb").read()
    original_output = open(OUTPUT_FILE, "rb").read() if os.path.isfile(OUTPUT_FILE) else None
    try:
        check_execution(BINARY_FILE)
        check_execution(TEST_BINARY)
    finally:
        for path in (DATABASE_FILE, DATABASE_FILE + "-wal", DATABASE_FILE + "-shm", OUTPUT_FILE, TRACE_FILE):
            if os.path.exists(path):
                os.remove(path)
        with open(DATABASE_FILE, "wb") as f:
            f.write(original_db)
        if original_output is not None:
            with open(OUTPUT_FILE, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

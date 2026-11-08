#!/bin/bash
mkdir -p /logs/verifier

cat << 'HOOK_EOF' > /tmp/sqlite_trace.c
#define _GNU_SOURCE
#include <sqlite3.h>
#include <dlfcn.h>
#include <stdio.h>
#include <string.h>

static void write_hex(FILE *f, const unsigned char *s, size_t n) {
    for (size_t i = 0; i < n; ++i) fprintf(f, "%02x", s[i]);
}

static void log_prepare(sqlite3_stmt *stmt, const char *sql, int nByte) {
    if (!sql) return;
    size_t n = nByte < 0 ? strlen(sql) : (size_t)nByte;
    while (n && sql[n - 1] == '\0') --n;
    FILE *f = fopen("/tmp/report_sqlite_trace.log", "a");
    if (!f) return;
    fprintf(f, "P %p ", (void *)stmt);
    write_hex(f, (const unsigned char *)sql, n);
    fputc('\n', f);
    fclose(f);
}

static void log_bind(sqlite3_stmt *stmt, int index, const char *kind,
                     const unsigned char *value, size_t n) {
    FILE *f = fopen("/tmp/report_sqlite_trace.log", "a");
    if (!f) return;
    fprintf(f, "B %p %d %s ", (void *)stmt, index, kind);
    if (value) write_hex(f, value, n);
    fputc('\n', f);
    fclose(f);
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int nByte,
                       sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, sqlite3_stmt **, const char **);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    int rc = real_fn(db, sql, nByte, stmt, tail);
    log_prepare(stmt ? *stmt : NULL, sql, nByte);
    return rc;
}

int sqlite3_prepare_v3(sqlite3 *db, const char *sql, int nByte, unsigned int flags,
                       sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3 *, const char *, int, unsigned int, sqlite3_stmt **, const char **);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v3");
    int rc = real_fn(db, sql, nByte, flags, stmt, tail);
    log_prepare(stmt ? *stmt : NULL, sql, nByte);
    return rc;
}

int sqlite3_bind_text(sqlite3_stmt *stmt, int index, const char *value, int n,
                      void (*destroy)(void *)) {
    static int (*real_fn)(sqlite3_stmt *, int, const char *, int, void (*)(void *));
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_bind_text");
    size_t len = value ? (n < 0 ? strlen(value) : (size_t)n) : 0;
    log_bind(stmt, index, "T8", (const unsigned char *)value, len);
    return real_fn(stmt, index, value, n, destroy);
}

int sqlite3_bind_text64(sqlite3_stmt *stmt, int index, const char *value,
                        sqlite3_uint64 n, void (*destroy)(void *), unsigned char encoding) {
    static int (*real_fn)(sqlite3_stmt *, int, const char *, sqlite3_uint64, void (*)(void *), unsigned char);
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_bind_text64");
    log_bind(stmt, index, "T8", (const unsigned char *)value, value ? (size_t)n : 0);
    return real_fn(stmt, index, value, n, destroy, encoding);
}

int sqlite3_bind_text16(sqlite3_stmt *stmt, int index, const void *value, int n,
                        void (*destroy)(void *)) {
    static int (*real_fn)(sqlite3_stmt *, int, const void *, int, void (*)(void *));
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_bind_text16");
    size_t len = 0;
    if (value) {
        if (n >= 0) len = (size_t)n;
        else {
            const unsigned char *p = value;
            while (p[len] || p[len + 1]) len += 2;
        }
    }
    log_bind(stmt, index, "T16", (const unsigned char *)value, len);
    return real_fn(stmt, index, value, n, destroy);
}
HOOK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import sqlite3
import subprocess
import uuid

HOME = "/home/user"
DB = os.path.join(HOME, "retail.db")
EXE = os.path.join(HOME, "report")
TRACE = "/tmp/report_sqlite_trace.log"
HOOK = "/tmp/libsqlite_trace.so"


def expected_for(db_path, city):
    conn = sqlite3.connect(db_path)
    try:
        rows = conn.execute(
            """SELECT u.name, SUM(p.amount) AS total
               FROM users AS u
               JOIN cities AS c ON c.id = u.city_id
               JOIN purchases AS p ON p.user_id = u.id
               WHERE c.name = ?
               GROUP BY u.id, u.name
               ORDER BY total DESC
               LIMIT 3""",
            (city,),
        ).fetchall()
        return [f"{name}|{float(total):.2f}" for name, total in rows]
    finally:
        conn.close()


def run_report(city, traced=False):
    env = os.environ.copy()
    if traced:
        env["LD_PRELOAD"] = HOOK
    result = subprocess.run(
        [EXE, city], cwd=HOME, env=env, text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=10
    )
    assert result.returncode == 0, (
        f"report failed for {city!r} with status {result.returncode}: {result.stderr}"
    )
    return result.stdout.splitlines()


def custom_indexes(db_path):
    conn = sqlite3.connect(db_path)
    try:
        return [row[0] for row in conn.execute(
            "SELECT name FROM sqlite_master "
            "WHERE type='index' AND name NOT LIKE 'sqlite_autoindex%'"
        )]
    finally:
        conn.close()


def parse_trace():
    prepared = {}
    bindings = {}
    with open(TRACE, "r", encoding="ascii") as f:
        for line in f:
            parts = line.rstrip("\n").split(" ")
            if parts[0] == "P" and len(parts) == 3:
                prepared[parts[1]] = bytes.fromhex(parts[2]).decode("utf-8", "strict")
            elif parts[0] == "B" and len(parts) == 5:
                raw = bytes.fromhex(parts[4])
                value = raw.decode("utf-16" if parts[3] == "T16" else "utf-8")
                bindings.setdefault(parts[1], {})[int(parts[2])] = value
    return prepared, bindings


def test_report_output_file():
    output_path = "/home/user/report_output.txt"
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."
    with open(output_path, "r") as f:
        content = f.read().strip()
    expected_lines = ["Charlie|500.00", "David|450.00", "Alice|350.50"]
    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]
    assert actual_lines == expected_lines, f"Expected output {expected_lines}, but got {actual_lines}"


def test_executable_exists():
    assert os.path.isfile(EXE), f"Executable {EXE} does not exist."
    assert os.access(EXE, os.X_OK), f"File {EXE} is not executable."
    with open(EXE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "report is not a compiled ELF executable."


def test_cpp_source_code():
    cpp_path = "/home/user/report.cpp"
    assert os.path.isfile(cpp_path), f"Source file {cpp_path} does not exist."
    with open(cpp_path, "r") as f:
        content = f.read()
    upper = content.upper()
    assert "JOIN" in upper, "The source code does not contain a JOIN query."
    assert "sqlite3_bind_" in content, "The source code does not contain parameterized queries (sqlite3_bind_*)."
    assert "GROUP BY" in upper, "The source code does not contain a GROUP BY clause."
    assert "ORDER BY" in upper, "The source code does not contain an ORDER BY clause."
    assert "LIMIT" in upper, "The source code does not contain a LIMIT clause."


def test_database_index():
    assert os.path.isfile(DB), f"Database file {DB} does not exist."
    indexes = custom_indexes(DB)
    assert len(indexes) > 0, "No custom index was created in the database."


def test_executable_behavior_parameterization_and_index_usage():
    # First verify ordinary invocations against answers derived from the database.
    for city in ("Seattle", "Portland"):
        assert run_report(city) == expected_for(DB, city)

    backup = "/tmp/retail-verifier-backup.db"
    shutil.copy2(DB, backup)
    token = uuid.uuid4().hex[:10]
    city = "Audit ' City; -- " + token
    names = ["AuditA_" + token, "AuditB_" + token, "AuditC_" + token, "AuditD_" + token]
    try:
        conn = sqlite3.connect(DB)
        city_id = conn.execute("SELECT COALESCE(MAX(id), 0) + 100 FROM cities").fetchone()[0]
        user_base = conn.execute("SELECT COALESCE(MAX(id), 0) + 100 FROM users").fetchone()[0]
        conn.execute("INSERT INTO cities(id, name) VALUES (?, ?)", (city_id, city))
        totals = [913.37, 721.19, 608.43, 111.11]
        for offset, (name, total) in enumerate(zip(names, totals)):
            uid = user_base + offset
            conn.execute("INSERT INTO users(id, name, city_id) VALUES (?, ?, ?)", (uid, name, city_id))
            conn.execute("INSERT INTO purchases(user_id, amount) VALUES (?, ?)", (uid, total / 2))
            conn.execute("INSERT INTO purchases(user_id, amount) VALUES (?, ?)", (uid, total / 2))
        conn.commit()
        conn.close()

        expected = expected_for(DB, city)
        if os.path.exists(TRACE):
            os.remove(TRACE)
        actual = run_report(city, traced=True)
        assert actual == expected, f"Expected dynamic output {expected}, got {actual}"
        assert os.path.isfile(TRACE), "The executable did not call the SQLite prepared-statement API."
        prepared, bindings = parse_trace()

        candidates = []
        for stmt, sql in prepared.items():
            upper = sql.upper()
            if ("SELECT" in upper and "JOIN" in upper and "GROUP BY" in upper
                    and "ORDER BY" in upper and "LIMIT" in upper):
                bound_values = bindings.get(stmt, {}).values()
                if city in bound_values:
                    candidates.append(sql)
        assert candidates, (
            "No executed single SELECT used JOIN, GROUP BY, ORDER BY, LIMIT and bound the city parameter."
        )
        query = candidates[0]
        assert city not in query, "The city was embedded directly in SQL instead of supplied as a parameter."

        indexes = custom_indexes(DB)
        conn = sqlite3.connect(DB)
        try:
            plan = conn.execute("EXPLAIN QUERY PLAN " + query, (city,)).fetchall()
        finally:
            conn.close()
        details = "\n".join(str(row[3]) for row in plan)
        assert any(re.search(r"(?<![A-Za-z0-9_])" + re.escape(name) + r"(?![A-Za-z0-9_])", details, re.I)
                   for name in indexes), (
            "The executed report query does not use any custom database index. Query plan:\n" + details
        )
    finally:
        shutil.copy2(backup, DB)
        os.remove(backup)
TEST_EOF

if gcc -shared -fPIC -o /tmp/libsqlite_trace.so /tmp/sqlite_trace.c -ldl && \
   python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

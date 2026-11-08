#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import collections
import json
import os
import re
import secrets
import shutil
import sqlite3
import stat
import subprocess
import tempfile


def test_binary_compiled():
    package = "/app/sod-graph-checker-1.1.0"
    binary_path = package + "/bin/check_sod"
    assert os.path.isfile(binary_path), f"Compiled binary {binary_path} is missing. Did you fix the Makefile and run make?"
    assert os.access(binary_path, os.X_OK), f"Compiled binary {binary_path} is not executable."

    clean = subprocess.run(["make", "clean"], cwd=package, capture_output=True, text=True)
    assert clean.returncode == 0, f"make clean failed:\n{clean.stdout}\n{clean.stderr}"
    build = subprocess.run(["make"], cwd=package, capture_output=True, text=True)
    assert build.returncode == 0, f"A clean rebuild failed:\n{build.stdout}\n{build.stderr}"
    assert os.path.isfile(binary_path) and os.access(binary_path, os.X_OK)
    with open(binary_path, "rb") as f:
        assert f.read(4) == b"\x7fELF", "check_sod is not a compiled ELF binary"
    assert os.path.isfile(package + "/src/main.o")
    assert os.path.isfile(package + "/src/risk.o")

    uid = secrets.randbelow(50000) + 2000
    proc = subprocess.run(
        [binary_path],
        input=json.dumps({"uid": uid, "roles": [], "recent_resources": []}),
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert proc.returncode == 0, proc.stderr
    expected = f"Risk Score: {uid ** 1.05:f}"
    assert proc.stdout.strip() == expected


def test_agent_script_exists():
    script_path = "/home/user/audit_user.sh"
    assert os.path.isfile(script_path), f"Wrapper script {script_path} is missing."
    assert os.access(script_path, os.X_OK) or os.access(script_path, os.R_OK), f"Wrapper script {script_path} cannot be read/executed."


def test_fuzz_equivalence():
    oracle_path = "/usr/local/bin/oracle_audit.sh"
    agent_path = "/home/user/audit_user.sh"
    assert os.path.isfile(oracle_path), f"Oracle script {oracle_path} is missing."

    import random
    random.seed(42)
    uids = random.sample(range(1000, 1100), 25)
    for uid in uids:
        oracle_proc = subprocess.run([oracle_path, str(uid)], capture_output=True, text=True, timeout=20)
        assert oracle_proc.returncode == 0, f"Oracle failed on uid {uid} with stderr: {oracle_proc.stderr}"
        agent_proc = subprocess.run(["bash", agent_path, str(uid)], capture_output=True, text=True, timeout=20)
        assert agent_proc.returncode == 0, f"Agent script failed on uid {uid} with stderr: {agent_proc.stderr}"
        assert oracle_proc.stdout.strip() == agent_proc.stdout.strip(), (
            f"Mismatch on uid {uid}.\nOracle output:\n{oracle_proc.stdout.strip()}\n"
            f"Agent output:\n{agent_proc.stdout.strip()}\n"
        )


def test_wrapper_queries_database_builds_json_and_pipes_to_checker():
    db_path = "/var/data/hr.db"
    binary_path = "/app/sod-graph-checker-1.1.0/bin/check_sod"
    agent_path = "/home/user/audit_user.sh"

    uid = secrets.randbelow(800000) + 200000
    other_uid = uid + 1
    suffix = secrets.token_hex(6)
    roles = [f"Auditor_{suffix}", f"Approver_{suffix}"]
    resources = [f"alpha_{suffix}", f"beta_{suffix}", f"gamma_{suffix}", f"delta_{suffix}", f"denied_{suffix}"]
    expected_resources = [
        {"resource_id": resources[1], "latest_access": "2041-07-08 12:35:00"},
        {"resource_id": resources[0], "latest_access": "2041-07-08 12:30:00"},
        {"resource_id": resources[3], "latest_access": "2041-07-08 12:25:00"},
    ]
    token = "VERIFIED_" + secrets.token_hex(20)

    shim_source = r'''
#define _GNU_SOURCE
#include <dlfcn.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sqlite3.h>

static void log_sql(const char *sql, int n) {
    const char *path = getenv("AUDIT_SQL_LOG");
    if (!path || !sql) return;
    FILE *f = fopen(path, "a");
    if (!f) return;
    fputs("\n---SQL---\n", f);
    if (n >= 0) fwrite(sql, 1, (size_t)n, f); else fputs(sql, f);
    fputc('\n', f);
    fclose(f);
}

int sqlite3_prepare_v2(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3*, const char*, int, sqlite3_stmt**, const char**) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v2");
    log_sql(sql, n);
    return real_fn(db, sql, n, stmt, tail);
}

int sqlite3_prepare_v3(sqlite3 *db, const char *sql, int n, unsigned int flags, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3*, const char*, int, unsigned int, sqlite3_stmt**, const char**) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare_v3");
    log_sql(sql, n);
    return real_fn(db, sql, n, flags, stmt, tail);
}

int sqlite3_prepare(sqlite3 *db, const char *sql, int n, sqlite3_stmt **stmt, const char **tail) {
    static int (*real_fn)(sqlite3*, const char*, int, sqlite3_stmt**, const char**) = NULL;
    if (!real_fn) real_fn = dlsym(RTLD_NEXT, "sqlite3_prepare");
    log_sql(sql, n);
    return real_fn(db, sql, n, stmt, tail);
}
'''

    with tempfile.TemporaryDirectory() as td:
        db_backup = os.path.join(td, "hr.db.backup")
        binary_backup = os.path.join(td, "check_sod.backup")
        shim_c = os.path.join(td, "sqlite_trace.c")
        shim_so = os.path.join(td, "sqlite_trace.so")
        sql_log = os.path.join(td, "sql.log")
        shutil.copy2(db_path, db_backup)
        shutil.copy2(binary_path, binary_backup)

        try:
            os.unlink(db_path)
            conn = sqlite3.connect(db_path)
            conn.executescript("""
                CREATE TABLE users(uid INTEGER, name TEXT);
                CREATE TABLE roles(role_id INTEGER, role_name TEXT);
                CREATE TABLE user_roles(uid INTEGER, role_id INTEGER);
                CREATE TABLE access_logs(log_id INTEGER, uid INTEGER, resource_id TEXT, access_time TEXT, status TEXT);
            """)
            conn.executemany("INSERT INTO users VALUES (?, ?)", [(uid, "Target"), (other_uid, "Noise")])
            conn.executemany("INSERT INTO roles VALUES (?, ?)", [(71, roles[0]), (93, roles[1]), (99, "NoiseRole")])
            conn.executemany("INSERT INTO user_roles VALUES (?, ?)", [(uid, 71), (uid, 93), (other_uid, 99)])
            logs = [
                (1, uid, resources[0], "2041-07-08 12:10:00", "GRANTED"),
                (2, uid, resources[0], "2041-07-08 12:30:00", "GRANTED"),
                (3, uid, resources[1], "2041-07-08 12:35:00", "GRANTED"),
                (4, uid, resources[2], "2041-07-08 12:15:00", "GRANTED"),
                (5, uid, resources[2], "2041-07-08 12:50:00", "DENIED"),
                (6, uid, resources[3], "2041-07-08 12:25:00", "GRANTED"),
                (7, uid, resources[4], "2041-07-08 12:55:00", "DENIED"),
                (8, other_uid, resources[4], "2041-07-08 13:00:00", "GRANTED"),
            ]
            conn.executemany("INSERT INTO access_logs VALUES (?, ?, ?, ?, ?)", logs)
            conn.commit()
            conn.close()

            probe = f'''#!/usr/bin/env python3
import collections
import json
import os
import stat
import sys

if not stat.S_ISFIFO(os.fstat(0).st_mode):
    print("checker stdin was not a pipe", file=sys.stderr)
    sys.exit(20)
try:
    data = json.load(sys.stdin)
except Exception as exc:
    print("invalid JSON: " + str(exc), file=sys.stderr)
    sys.exit(21)
if set(data) != {{"uid", "roles", "recent_resources"}}:
    print("wrong JSON keys", file=sys.stderr)
    sys.exit(22)
if type(data["uid"]) is not int or data["uid"] != {uid!r}:
    print("wrong uid", file=sys.stderr)
    sys.exit(23)
if collections.Counter(data["roles"]) != collections.Counter({roles!r}):
    print("wrong roles: " + repr(data["roles"]), file=sys.stderr)
    sys.exit(24)
if data["recent_resources"] != {expected_resources!r}:
    print("wrong recent resources: " + repr(data["recent_resources"]), file=sys.stderr)
    sys.exit(25)
print({token!r})
'''
            with open(binary_path, "w") as f:
                f.write(probe)
            os.chmod(binary_path, 0o755)

            with open(shim_c, "w") as f:
                f.write(shim_source)
            cc = subprocess.run(["gcc", "-shared", "-fPIC", "-o", shim_so, shim_c, "-ldl"], capture_output=True, text=True)
            assert cc.returncode == 0, cc.stderr

            env = os.environ.copy()
            env["LD_PRELOAD"] = shim_so
            env["AUDIT_SQL_LOG"] = sql_log
            proc = subprocess.run(["bash", agent_path, str(uid)], capture_output=True, text=True, env=env, timeout=20)
            logged = ""
            if os.path.exists(sql_log):
                with open(sql_log, errors="replace") as f:
                    logged = f.read()
        finally:
            shutil.copy2(db_backup, db_path)
            shutil.copy2(binary_backup, binary_path)
            os.chmod(binary_path, 0o755)

    assert proc.returncode == 0, f"Wrapper failed against hidden database/probe: {proc.stderr}"
    assert proc.stdout.strip() == token, f"Wrapper did not print only checker stdout: {proc.stdout!r}"
    assert proc.stderr == "", f"Wrapper produced extraneous stderr: {proc.stderr!r}"

    statements = logged.split("---SQL---")
    window_statements = []
    for statement in statements:
        normalized = re.sub(r"\s+", " ", statement.upper())
        has_window = " OVER" in normalized and re.search(r"\b(ROW_NUMBER|RANK|DENSE_RANK)\s*\(", normalized)
        has_partition = re.search(r"PARTITION\s+BY\s+(?:\w+\.)?RESOURCE_ID", normalized)
        has_order = re.search(r"ORDER\s+BY\s+(?:\w+\.)?ACCESS_TIME\s+DESC", normalized)
        has_filter = "ACCESS_LOGS" in normalized and "STATUS" in normalized
        has_top_three = re.search(r"LIMIT\s+3\b", normalized) or re.search(r"(?:RN|ROW_NUM|ROW_NUMBER)\s*<=?\s*3\b", normalized)
        if has_window and has_partition and has_order and has_filter and has_top_three:
            window_statements.append(statement)
    assert window_statements, (
        "No executed SQL statement used a window function over access_logs to select the top three "
        "latest distinct granted resources. Executed SQL was:\n" + logged
    )

TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

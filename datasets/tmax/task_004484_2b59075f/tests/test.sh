#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import shutil
import sqlite3
import subprocess
import tempfile
import random
import pytest

AGENT_SCRIPT = "/home/user/audit_repro.py"
ORACLE_BINARY = "/app/legacy_audit"
DATABASE = "/home/user/audit.db"


def run_agent(user_id, traced=False):
    if not traced:
        return subprocess.run(
            ["/usr/bin/python3", AGENT_SCRIPT, str(user_id)],
            capture_output=True,
            text=True,
            timeout=10,
        ), None

    fd, trace_path = tempfile.mkstemp(prefix="audit_trace_", suffix=".log")
    os.close(fd)
    try:
        result = subprocess.run(
            [
                "/usr/bin/strace", "-f",
                "-e", "trace=execve,execveat,open,openat",
                "-o", trace_path,
                "/usr/bin/python3", AGENT_SCRIPT, str(user_id),
            ],
            capture_output=True,
            text=True,
            timeout=10,
        )
        with open(trace_path, "r", errors="replace") as f:
            trace = f.read()
        return result, trace
    finally:
        try:
            os.unlink(trace_path)
        except FileNotFoundError:
            pass


def test_fuzz_equivalence():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} does not exist."
    assert os.path.isfile(ORACLE_BINARY), f"Oracle binary {ORACLE_BINARY} does not exist."

    random.seed(42)
    fuzz_inputs = [random.randint(1, 1000) for _ in range(100)]

    for user_id in fuzz_inputs:
        oracle_res = subprocess.run(
            [ORACLE_BINARY, str(user_id)], capture_output=True, text=True, timeout=10
        )
        agent_res, _ = run_agent(user_id)

        assert oracle_res.returncode == 0, f"Oracle failed on input {user_id}: {oracle_res.stderr}"
        assert agent_res.returncode == 0, f"Agent script failed on input {user_id}: {agent_res.stderr}"

        oracle_out = oracle_res.stdout.strip()
        agent_out = agent_res.stdout.strip()
        assert oracle_out == agent_out, (
            f"Mismatch on user_id={user_id}.\n"
            f"Oracle output: '{oracle_out}'\n"
            f"Agent output: '{agent_out}'"
        )


def build_independent_database():
    for suffix in ("", "-wal", "-shm", "-journal"):
        try:
            os.unlink(DATABASE + suffix)
        except FileNotFoundError:
            pass

    conn = sqlite3.connect(DATABASE)
    cur = conn.cursor()
    cur.executescript("""
        CREATE TABLE users (id INTEGER);
        CREATE TABLE user_roles (user_id INTEGER, role_id INTEGER);
        CREATE TABLE role_hierarchy (parent_role_id INTEGER, child_role_id INTEGER);
        CREATE TABLE role_resources (role_id INTEGER, resource_id INTEGER, access_level INTEGER);
        CREATE TABLE resources (id INTEGER);

        INSERT INTO users VALUES (1), (2), (3), (4);
        INSERT INTO user_roles VALUES
            (1, 10), (1, 20), (2, 30), (3, 99);

        INSERT INTO role_hierarchy VALUES
            (10, 11), (11, 12), (12, 10),
            (20, 21), (20, 22), (21, 23),
            (30, 31), (31, 32), (32, 31),
            (77, 78);

        INSERT INTO resources VALUES
            (1), (2), (2), (4), (7);

        INSERT INTO role_resources VALUES
            (10, 1, 2),
            (999, 2, 5),
            (11, 4, 1),
            (30, 7, 9),
            (55, 404, 100),
            (22, 1, -1);
    """)
    conn.commit()
    conn.close()
    os.chmod(DATABASE, 0o666)


def independently_expected(user_id):
    conn = sqlite3.connect(DATABASE)
    try:
        row = conn.execute(
            "WITH RECURSIVE RoleTree AS ("
            "SELECT role_id FROM user_roles WHERE user_id = ? "
            "UNION "
            "SELECT rh.child_role_id FROM role_hierarchy rh "
            "JOIN RoleTree rt ON rh.parent_role_id = rt.role_id) "
            "SELECT COALESCE(COUNT(r.id) + SUM(rr.access_level), 0) "
            "FROM RoleTree rt, role_resources rr, resources r "
            "WHERE r.id = rr.resource_id;",
            (user_id,),
        ).fetchone()
        return int(row[0])
    finally:
        conn.close()


def test_executes_python_sqlite_logic_without_delegating_to_binary():
    original = None
    if os.path.exists(DATABASE):
        with open(DATABASE, "rb") as f:
            original = f.read()

    try:
        build_independent_database()
        for user_id in (1, 2, 3, 4, 999):
            expected = independently_expected(user_id)
            result, trace = run_agent(user_id, traced=True)

            assert result.returncode == 0, (
                f"Agent script failed on independent input {user_id}: {result.stderr}"
            )
            assert re.fullmatch(r"-?\d+\n?", result.stdout), (
                f"Output must contain only one integer, got {result.stdout!r}"
            )
            assert int(result.stdout.strip()) == expected, (
                f"Incorrect result on independently generated database for user_id={user_id}"
            )

            assert DATABASE in trace, (
                "The Python implementation did not open /home/user/audit.db"
            )
            assert ORACLE_BINARY not in trace, (
                "The submission accessed the legacy binary at runtime instead of reproducing its logic"
            )

            exec_calls = re.findall(r"\bexecve(?:at)?\(", trace)
            assert len(exec_calls) == 1, (
                "The submission launched another executable; the calculation must be performed "
                "by the Python script through SQLite"
            )
    finally:
        for suffix in ("", "-wal", "-shm", "-journal"):
            try:
                os.unlink(DATABASE + suffix)
            except FileNotFoundError:
                pass
        if original is not None:
            with open(DATABASE, "wb") as f:
                f.write(original)
            os.chmod(DATABASE, 0o666)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

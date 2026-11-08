#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import socket
import sqlite3
import subprocess
import time
import urllib.parse
import urllib.request

WORKSPACE = "/home/user/workspace"
DB_PATH = os.path.join(WORKSPACE, "data.db")
AGENT_PATH = "/home/user/process.sh"


def expected(v1, v2, op):
    if op == "add":
        return v1 + v2
    if op == "sub":
        return v1 - v2
    if op == "mul":
        return v1 * v2
    raise AssertionError(f"unexpected operation: {op}")


def audit_rows_after(row_id):
    with sqlite3.connect(DB_PATH, timeout=5) as db:
        return db.execute(
            "SELECT id, expression, result FROM audit_log WHERE id > ? ORDER BY id",
            (row_id,),
        ).fetchall()


def latest_audit_id():
    with sqlite3.connect(DB_PATH, timeout=5) as db:
        return db.execute("SELECT COALESCE(MAX(id), 0) FROM audit_log").fetchone()[0]


def wait_for_audit(row_id, expression_prefix, result):
    deadline = time.time() + 3
    while time.time() < deadline:
        rows = audit_rows_after(row_id)
        if any(expr is not None and expr.startswith(expression_prefix) and res == result
               for _, expr, res in rows):
            return
        time.sleep(0.05)
    raise AssertionError(
        f"No matching audit row after id {row_id}: "
        f"expression prefix={expression_prefix!r}, result={result}; rows={audit_rows_after(row_id)!r}"
    )


def http_get(url):
    with urllib.request.urlopen(url, timeout=5) as response:
        assert response.status == 200
        return response.read().decode()


def test_database_migration_applied():
    assert os.path.isfile(DB_PATH), f"Migrated database not found at {DB_PATH}"
    with sqlite3.connect(DB_PATH, timeout=5) as db:
        table = db.execute(
            "SELECT sql FROM sqlite_master WHERE type='table' AND name='audit_log'"
        ).fetchone()
        assert table is not None, "audit_log table was not created"
        columns = db.execute("PRAGMA table_info(audit_log)").fetchall()
    names = [column[1] for column in columns]
    assert names == ["id", "expression", "result", "timestamp"], names
    assert columns[0][5] == 1, "audit_log.id is not the primary key"


def test_c_evaluator_repaired_built_running_and_logging():
    c_dir = os.path.join(WORKSPACE, "c_eval")
    makefile_path = os.path.join(c_dir, "Makefile")
    source_path = os.path.join(c_dir, "eval.c")
    binary_path = os.path.join(c_dir, "eval")

    makefile = open(makefile_path, encoding="utf-8").read()
    assert "-lsqlite3" in makefile, "Makefile still lacks the sqlite3 linker flag"
    assert re.search(r"(?:^|\s)-lm(?:\s|$)", makefile), "Makefile still lacks the math linker flag"

    source = open(source_path, encoding="utf-8").read()
    assert not re.search(r"\bfloat\s+float_val\b", source), "eval.c line-42 result type mismatch was not repaired"

    build = subprocess.run(
        ["make", "-B"], cwd=c_dir, capture_output=True, text=True, timeout=30
    )
    assert build.returncode == 0, f"C evaluator does not build:\n{build.stdout}\n{build.stderr}"
    assert os.path.isfile(binary_path) and os.access(binary_path, os.X_OK)

    before = latest_audit_id()
    with socket.create_connection(("127.0.0.1", 5002), timeout=5) as sock:
        sock.sendall(b"17 6 mul")
        result = sock.recv(1024).decode()
    assert result == "102", f"Service C returned {result!r}, expected '102'"
    wait_for_audit(before, "17 6 mul", 102)


def test_proxy_running_and_connected_to_service_c():
    before = latest_audit_id()
    result = http_get("http://127.0.0.1:5001/compute?v1=29&v2=8&op=sub")
    assert result == "21", f"Proxy returned {result!r}, expected '21'"
    wait_for_audit(before, "29 8 sub", 21)


def test_nginx_configuration_and_router_running():
    config_path = os.path.join(WORKSPACE, "nginx.conf")
    config = open(config_path, encoding="utf-8").read()
    assert re.search(r"proxy_pass\s+http://127\.0\.0\.1:5001\s*;", config), (
        "nginx.conf does not proxy /compute to port 5001"
    )
    syntax = subprocess.run(
        ["nginx", "-t", "-c", config_path], capture_output=True, text=True, timeout=10
    )
    assert syntax.returncode == 0, f"Invalid Nginx configuration:\n{syntax.stdout}\n{syntax.stderr}"

    before = latest_audit_id()
    result = http_get("http://127.0.0.1:8080/compute?v1=31&v2=12&op=add")
    assert result == "43", f"Nginx router returned {result!r}, expected '43'"
    wait_for_audit(before, "31 12 add", 43)


def test_process_script_uses_pipeline_and_logs():
    assert os.path.isfile(AGENT_PATH), f"Agent script not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent script {AGENT_PATH} is not executable"

    script = open(AGENT_PATH, encoding="utf-8").read()
    first_line = script.splitlines()[0] if script.splitlines() else ""
    assert "bash" in first_line, "process.sh must be a Bash script"
    assert re.search(r"(?:^|[\s;&|()])(?:/usr/bin/|/bin/)?curl(?:[\s]|$)", script), (
        "process.sh does not invoke curl"
    )
    assert "127.0.0.1:8080/compute" in script, (
        "process.sh does not target the required Nginx compute endpoint"
    )

    before = latest_audit_id()
    query = "val1=41&val2=9&op=mul"
    run = subprocess.run([AGENT_PATH, query], capture_output=True, text=True, timeout=10)
    assert run.returncode == 0, run.stderr
    assert run.stdout == "RESULT: 369\n", run.stdout
    wait_for_audit(before, "41 9 mul", 369)


def test_fuzz_equivalence():
    assert os.path.isfile(AGENT_PATH), f"Agent script not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent script {AGENT_PATH} is not executable"

    random.seed(42)
    ops = ["add", "sub", "mul"]
    for _ in range(1000):
        val1 = random.randint(0, 9999)
        val2 = random.randint(0, 9999)
        op = random.choice(ops)
        query = f"val1={val1}&val2={val2}&op={op}"

        agent_res = subprocess.run(
            [AGENT_PATH, query], capture_output=True, text=True, timeout=10
        )
        wanted = f"RESULT: {expected(val1, val2, op)}\n"
        assert agent_res.returncode == 0, (
            f"Nonzero return code on input {query!r}: {agent_res.returncode}\n"
            f"stderr: {agent_res.stderr}"
        )
        assert agent_res.stdout == wanted, (
            f"Output mismatch on input {query!r}.\n"
            f"Expected: {wanted!r}\nGot: {agent_res.stdout!r}\n"
            f"stderr: {agent_res.stderr}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

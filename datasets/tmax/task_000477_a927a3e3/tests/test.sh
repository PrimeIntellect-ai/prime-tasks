#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import fcntl
import json
import os
import re
import sqlite3
import subprocess
import tempfile
import uuid

PROJECT = "/home/user/project"
BUILD = os.path.join(PROJECT, "build.sh")
DB = os.path.join(PROJECT, "build_state.db")
REPORT = "/home/user/fix_report.txt"


def test_build_script_parallel_execution_maintained():
    assert os.path.isfile(BUILD), f"File {BUILD} does not exist."
    with open(BUILD, "r") as f:
        content = f.read()
    assert "&" in content, "The parallel execution feature (&) was removed from build.sh."


def test_database_all_done():
    assert os.path.isfile(DB), f"Database file {DB} does not exist."
    with sqlite3.connect(DB) as conn:
        count = conn.execute("SELECT count(*) FROM tasks WHERE status='pending';").fetchone()[0]
    assert count == 0, f"Expected 0 pending tasks in the database, found {count}."


def test_fix_report_content():
    assert os.path.isfile(REPORT), f"Report file {REPORT} does not exist."
    with open(REPORT, "r") as f:
        content = f.read().strip()
    assert re.search(r"ERROR=.*database is locked.*", content, re.IGNORECASE), \
        f"The report file does not contain the expected error message. Content: {content}"


def test_build_script_execution():
    init_script = os.path.join(PROJECT, "init_db.sh")
    subprocess.run([init_script], check=True)
    result = subprocess.run([BUILD], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, \
        f"build.sh failed with exit code {result.returncode}.\nStdout: {result.stdout}\nStderr: {result.stderr}"
    with sqlite3.connect(DB) as conn:
        count = conn.execute("SELECT count(*) FROM tasks WHERE status='pending';").fetchone()[0]
    assert count == 0, f"After running build.sh, expected 0 pending tasks, found {count}."


def test_parallel_per_module_work_survives_lock_contention():
    task_count = 24
    names = [f"verify_{uuid.uuid4().hex}_{i}" for i in range(task_count)]
    with sqlite3.connect(DB) as conn:
        conn.execute("DROP TABLE IF EXISTS tasks")
        conn.execute("CREATE TABLE tasks (id INTEGER PRIMARY KEY, module_name TEXT, status TEXT)")
        conn.executemany("INSERT INTO tasks(module_name,status) VALUES (?, 'pending')",
                         [(name,) for name in names])
        conn.commit()

    wrapper_dir = tempfile.mkdtemp(prefix="build-verify-")
    state_file = os.path.join(wrapper_dir, "sleep_state.json")
    update_log = os.path.join(wrapper_dir, "updates.log")
    with open(state_file, "w") as f:
        json.dump({"active": 0, "maximum": 0, "calls": 0}, f)

    sleep_wrapper = r'''#!/usr/bin/env python3
import fcntl, json, os, subprocess, sys
state_path = os.environ["VERIFY_SLEEP_STATE"]
def change(delta):
    with open(state_path, "r+") as f:
        fcntl.flock(f, fcntl.LOCK_EX)
        try:
            try: state = json.load(f)
            except Exception: state = {"active": 0, "maximum": 0, "calls": 0}
            state["active"] += delta
            if delta > 0:
                state["calls"] += 1
                state["maximum"] = max(state["maximum"], state["active"])
            f.seek(0); f.truncate(); json.dump(state, f); f.flush()
        finally:
            fcntl.flock(f, fcntl.LOCK_UN)
change(1)
try:
    raise SystemExit(subprocess.call(["/usr/bin/sleep"] + sys.argv[1:]))
finally:
    change(-1)
'''

    sqlite_wrapper = r'''#!/usr/bin/env python3
import fcntl, os, re, sqlite3, subprocess, sys, time
args = sys.argv[1:]
cmds = []
i = 0
while i < len(args) and args[i].startswith("-"):
    if args[i] == "-cmd" and i + 1 < len(args):
        cmds.append(args[i + 1]); i += 2
    else:
        i += 1
if i >= len(args):
    raise SystemExit(subprocess.call(["/usr/bin/sqlite3"] + args))
db = args[i]
sql = " ".join(args[i + 1:])
if not re.search(r"\bUPDATE\s+tasks\b", sql, re.I):
    raise SystemExit(subprocess.call(["/usr/bin/sqlite3"] + args))
with open(os.environ["VERIFY_UPDATE_LOG"], "a") as f:
    fcntl.flock(f, fcntl.LOCK_EX)
    f.write(sql.replace("\n", " ") + "\n"); f.flush()
    fcntl.flock(f, fcntl.LOCK_UN)
all_control = "\n".join(cmds + [sql])
m = re.search(r"(?:\.timeout\s+|busy_timeout\s*=\s*)(\d+)", all_control, re.I)
timeout_ms = int(m.group(1)) if m else 0
try:
    conn = sqlite3.connect(db, timeout=timeout_ms / 1000.0, isolation_level=None)
    conn.execute(f"PRAGMA busy_timeout={timeout_ms}")
    conn.execute("BEGIN IMMEDIATE")
    statements = []
    for statement in sql.split(";"):
        statement = statement.strip()
        if not statement or re.match(r"^(?:PRAGMA\s+busy_timeout|\.timeout)\b", statement, re.I):
            continue
        if re.match(r"^(?:BEGIN|COMMIT|END|ROLLBACK)\b", statement, re.I):
            continue
        statements.append(statement)
    for statement in statements:
        conn.execute(statement)
    time.sleep(0.06)
    conn.execute("COMMIT")
    conn.close()
except sqlite3.Error as e:
    try: conn.close()
    except Exception: pass
    print(f"Error: {e}", file=sys.stderr)
    raise SystemExit(1)
'''

    for name, body in (("sleep", sleep_wrapper), ("sqlite3", sqlite_wrapper)):
        path = os.path.join(wrapper_dir, name)
        with open(path, "w") as f:
            f.write(body)
        os.chmod(path, 0o755)

    env = os.environ.copy()
    env["PATH"] = wrapper_dir + os.pathsep + env.get("PATH", "")
    env["VERIFY_SLEEP_STATE"] = state_file
    env["VERIFY_UPDATE_LOG"] = update_log
    result = subprocess.run([BUILD], cwd=PROJECT, env=env, capture_output=True,
                            text=True, timeout=45)
    assert result.returncode == 0, \
        f"build.sh did not handle concurrent SQLite locking.\nStdout: {result.stdout}\nStderr: {result.stderr}"

    with sqlite3.connect(DB) as conn:
        pending = conn.execute("SELECT module_name FROM tasks WHERE status='pending'").fetchall()
        done = conn.execute("SELECT count(*) FROM tasks WHERE status='done'").fetchone()[0]
    assert not pending and done == task_count, \
        f"The stressed run did not complete every generated task; pending={pending}"

    with open(state_file) as f:
        state = json.load(f)
    assert state["calls"] >= task_count, \
        f"Expected a compilation step for each of {task_count} tasks, observed {state['calls']}."
    assert state["maximum"] >= 2, \
        "Compilation steps did not actually overlap; '&' in a comment or unrelated command is insufficient."

    try:
        with open(update_log) as f:
            updates = [line for line in f if line.strip()]
    except FileNotFoundError:
        updates = []
    assert len(updates) >= task_count, \
        f"Expected per-task database updates, observed only {len(updates)} update command(s)."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

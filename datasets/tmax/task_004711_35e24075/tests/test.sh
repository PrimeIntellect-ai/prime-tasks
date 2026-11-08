#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import sqlite3
import stat
import subprocess
import tempfile
from collections import defaultdict, deque

DB_PATH = "/home/user/audit.db"
SCRIPT_PATH = "/home/user/analyze_audit.sh"
CSV_PATH = "/home/user/recent_violations.csv"
TRACE_TEXT = ""


def test_script_exists_and_executable():
    """Check if the bash script exists and is executable."""
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."

    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f"Script {SCRIPT_PATH} is not executable."


def test_sqlite3_installed():
    """Check if sqlite3 CLI is installed."""
    try:
        subprocess.run(["sqlite3", "--version"], check=True,
                       stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    except FileNotFoundError:
        assert False, "sqlite3 CLI tool is not installed."
    except subprocess.CalledProcessError:
        assert False, "sqlite3 CLI tool is installed but failed to run."


def test_script_contains_reindex():
    """Check if the script contains the REINDEX command."""
    with open(SCRIPT_PATH, "r") as f:
        content = f.read().upper()
    assert "REINDEX" in content, "Script does not appear to contain a REINDEX command."


def test_script_contains_required_pipeline_logic():
    with open(SCRIPT_PATH, "r") as f:
        content = f.read()
    upper = content.upper()
    assert re.search(r"\b(WITH\s+RECURSIVE|WITH[\s\S]*?\bRECURSIVE\b)", upper), \
        "Script does not contain a recursive CTE."
    assert re.search(r"\b(ROW_NUMBER|RANK|DENSE_RANK)\s*\(", upper), \
        "Script does not contain a ranking window function."
    assert re.search(r"\bOVER\s*\(", upper), "Script does not contain a window OVER clause."
    assert re.search(r"(COMMAND\s+-V|\bWHICH\b)[\s\S]*?SQLITE3", upper), \
        "Script does not check whether sqlite3 is installed."
    assert re.search(r"APT-GET[\s\S]*?INSTALL[\s\S]*?SQLITE3", upper), \
        "Script does not contain sqlite3 installation logic."


def _add_unseen_test_data():
    token = secrets.token_hex(5)
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    next_user = cur.execute("SELECT COALESCE(MAX(user_id), 0) + 1 FROM users").fetchone()[0]
    next_role = cur.execute("SELECT COALESCE(MAX(role_id), 0) + 1 FROM roles").fetchone()[0]
    next_log = cur.execute("SELECT COALESCE(MAX(log_id), 0) + 1 FROM access_logs").fetchone()[0]

    username = "audit_" + token
    roles = [next_role + i for i in range(4)]
    deep_permission = "deep_allowed_" + token
    bad_resources = ["forbidden_" + token + "_" + str(i) for i in range(3)]

    cur.execute("INSERT INTO users(user_id, username) VALUES (?, ?)", (next_user, username))
    cur.executemany("INSERT INTO roles(role_id, role_name) VALUES (?, ?)",
                    [(role, "role_" + token + "_" + str(i)) for i, role in enumerate(roles)])
    cur.execute("INSERT INTO user_roles(user_id, role_id) VALUES (?, ?)", (next_user, roles[0]))
    cur.executemany("INSERT INTO role_inheritance(parent_role_id, child_role_id) VALUES (?, ?)",
                    [(roles[0], roles[1]), (roles[1], roles[2]), (roles[2], roles[3])])
    cur.execute("INSERT INTO role_permissions(role_id, resource_name) VALUES (?, ?)",
                (roles[3], deep_permission))

    rows = [
        (next_log, "2040-01-01 09:00:00", next_user, deep_permission),
        (next_log + 1, "2040-01-01 10:00:00", next_user, bad_resources[0]),
        (next_log + 2, "2040-01-01 11:00:00", next_user, bad_resources[1]),
        (next_log + 3, "2040-01-01 12:00:00", next_user, bad_resources[2]),
        (next_log + 4, "2040-01-02 10:00:00", 2, "bob_dynamic_" + token),
        (next_log + 5, "2040-01-02 11:00:00", 2, "bob_dynamic2_" + token),
    ]
    cur.executemany(
        "INSERT INTO access_logs(log_id, timestamp, user_id, resource_name) VALUES (?, ?, ?, ?)", rows)
    conn.commit()
    conn.close()


def _strip_sql_comments(text):
    text = re.sub(r"/\*.*?\*/", "", text, flags=re.S)
    return re.sub(r"--[^\n]*", "", text)


def test_execute_complete_pipeline():
    """Run the submitted artifact on unseen data and observe its sqlite3 input."""
    global TRACE_TEXT
    _add_unseen_test_data()
    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)

    real_sqlite = os.path.realpath(subprocess.check_output(["which", "sqlite3"], text=True).strip())
    backup = real_sqlite + ".verifier-real-" + secrets.token_hex(6)
    trace_fd, trace_path = tempfile.mkstemp(prefix="sqlite-trace-")
    os.close(trace_fd)
    os.rename(real_sqlite, backup)

    wrapper = f'''#!/bin/bash
trace={trace_path!r}
real={backup!r}
tmp=$(mktemp)
cat > "$tmp"
{{
  echo "=== SQLITE INVOCATION ==="
  printf '%s\\n' "$@"
  cat "$tmp"
}} >> "$trace"
"$real" "$@" < "$tmp"
rc=$?
rm -f "$tmp"
exit $rc
'''
    try:
        with open(real_sqlite, "w") as f:
            f.write(wrapper)
        os.chmod(real_sqlite, 0o755)
        result = subprocess.run(
            [SCRIPT_PATH], cwd="/home/user", stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True, timeout=60)
    finally:
        if os.path.exists(real_sqlite):
            os.remove(real_sqlite)
        os.rename(backup, real_sqlite)

    with open(trace_path, "r", errors="replace") as f:
        TRACE_TEXT = f.read()
    os.remove(trace_path)

    assert result.returncode == 0, \
        f"Script failed with exit code {result.returncode}. stderr: {result.stderr}"
    assert os.path.exists(CSV_PATH), "Script did not generate recent_violations.csv when executed."

    sql = _strip_sql_comments(TRACE_TEXT).upper()
    assert re.search(r"\bREINDEX\b(?:\s+[A-Z_][A-Z0-9_]*)?\s*;", sql), \
        "No executed sqlite3 input contained a REINDEX statement."

    invocations = sql.split("=== SQLITE INVOCATION ===")
    assert any(re.search(r"\b(WITH\s+RECURSIVE|WITH[\s\S]*?\bRECURSIVE\b)", part)
               and re.search(r"\b(ROW_NUMBER|RANK|DENSE_RANK)\s*\(", part)
               and re.search(r"\bOVER\s*\(", part)
               for part in invocations), \
        "The executed analysis did not use a recursive CTE and ranking window function in one query."

    conn = sqlite3.connect(DB_PATH)
    assert conn.execute("PRAGMA integrity_check").fetchone()[0] == "ok"
    assert conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type='index' AND name='idx_logs_time'"
    ).fetchone() is not None
    conn.close()


def compute_expected_violations():
    """Compute the expected violations directly from the database."""
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    users = {row['user_id']: row['username'] for row in cursor.execute("SELECT * FROM users")}

    user_roles = defaultdict(list)
    for row in cursor.execute("SELECT * FROM user_roles"):
        user_roles[row['user_id']].append(row['role_id'])

    inheritance = defaultdict(list)
    for row in cursor.execute("SELECT * FROM role_inheritance"):
        inheritance[row['parent_role_id']].append(row['child_role_id'])

    role_perms = defaultdict(list)
    for row in cursor.execute("SELECT * FROM role_permissions"):
        role_perms[row['role_id']].append(row['resource_name'])

    logs = [dict(row) for row in cursor.execute("SELECT * FROM access_logs")]
    conn.close()

    user_effective_perms = defaultdict(set)
    for user_id in users:
        roles_to_process = deque(user_roles[user_id])
        processed_roles = set()
        while roles_to_process:
            current_role = roles_to_process.popleft()
            if current_role in processed_roles:
                continue
            processed_roles.add(current_role)
            for perm in role_perms[current_role]:
                user_effective_perms[user_id].add(perm)
            for child_role in inheritance[current_role]:
                if child_role not in processed_roles:
                    roles_to_process.append(child_role)

    violations = []
    for log in logs:
        user_id = log['user_id']
        if log['resource_name'] not in user_effective_perms[user_id]:
            violations.append({
                'username': users[user_id],
                'resource_name': log['resource_name'],
                'timestamp': log['timestamp']
            })

    user_violations = defaultdict(list)
    for violation in violations:
        user_violations[violation['username']].append(violation)

    final_violations = []
    for username, values in user_violations.items():
        values.sort(key=lambda item: item['timestamp'], reverse=True)
        final_violations.extend(values[:2])

    final_violations.sort(key=lambda item: item['timestamp'], reverse=True)
    final_violations.sort(key=lambda item: item['username'])
    return final_violations


def test_csv_output():
    """Check if the generated CSV matches the expected output."""
    assert os.path.exists(CSV_PATH), f"Output file {CSV_PATH} does not exist."
    expected_data = compute_expected_violations()

    with open(CSV_PATH, "r", newline="") as f:
        reader = csv.DictReader(f)
        actual_data = list(reader)
        fieldnames = reader.fieldnames

    assert fieldnames == ['username', 'resource_name', 'timestamp'], \
        f"CSV headers are incorrect. Expected ['username', 'resource_name', 'timestamp'], got {fieldnames}"
    assert len(actual_data) == len(expected_data), \
        f"Expected {len(expected_data)} rows in CSV, got {len(actual_data)}."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual['username'] == expected['username'], \
            f"Row {i+1} username mismatch: expected {expected['username']}, got {actual['username']}"
        assert actual['resource_name'] == expected['resource_name'], \
            f"Row {i+1} resource_name mismatch: expected {expected['resource_name']}, got {actual['resource_name']}"
        assert actual['timestamp'] == expected['timestamp'], \
            f"Row {i+1} timestamp mismatch: expected {expected['timestamp']}, got {actual['timestamp']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import contextlib
import os
import re
import shlex
import shutil
import sqlite3
import subprocess
import tempfile
import uuid

import pytest

SCRIPT_PATH = "/home/user/audit_path.sh"
RESULTS_PATH = "/home/user/audit_results.txt"
DB_PATH = "/home/user/corp_audit.db"


def run_script(*args):
    return subprocess.run(
        [SCRIPT_PATH, *args],
        capture_output=True,
        text=True,
        timeout=10,
    )


@pytest.fixture(scope="session", autouse=True)
def restore_database_after_tests():
    fd, backup = tempfile.mkstemp(prefix="corp_audit_backup_", suffix=".db")
    os.close(fd)
    shutil.copy2(DB_PATH, backup)
    try:
        yield
    finally:
        shutil.copy2(backup, DB_PATH)
        os.unlink(backup)


@contextlib.contextmanager
def trace_sqlite_cli():
    sqlite_path = os.path.realpath(shutil.which("sqlite3"))
    token = uuid.uuid4().hex
    real_path = sqlite_path + ".verifier-real-" + token
    log_path = "/tmp/sqlite-trace-" + token
    os.rename(sqlite_path, real_path)
    wrapper = f'''#!/bin/bash
printf '%s\\n' "$*" >> {shlex.quote(log_path)}
tmp=$(mktemp)
cat > "$tmp"
cat "$tmp" >> {shlex.quote(log_path)}
{shlex.quote(real_path)} "$@" < "$tmp"
status=$?
rm -f "$tmp"
exit $status
'''
    try:
        with open(sqlite_path, "w") as f:
            f.write(wrapper)
        os.chmod(sqlite_path, 0o755)
        yield log_path
    finally:
        if os.path.exists(sqlite_path):
            os.unlink(sqlite_path)
        os.rename(real_path, sqlite_path)


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."

    with open(SCRIPT_PATH, "r", errors="replace") as f:
        source = f.read()
    first_line = source.splitlines()[0] if source.splitlines() else ""
    assert re.search(r"^#!.*\bbash\b", first_line), "audit_path.sh must be a Bash script."
    active_source = "\n".join(
        line for line in source.splitlines() if not line.lstrip().startswith("#")
    )
    assert re.search(r"\bsqlite3\b", active_source), "The script must invoke the sqlite3 CLI."


def test_audit_results_content():
    assert os.path.isfile(RESULTS_PATH), f"Results file {RESULTS_PATH} does not exist."

    with open(RESULTS_PATH, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 2, f"Expected at least 2 lines in {RESULTS_PATH}, found {len(lines)}."

    expected_line_1 = "Employee:Mallory -> Group:Interns -> Group:Dev_Team -> Group:Engineering -> Group:SuperAdmins -> Resource:Project_Apollo_Secrets"
    expected_line_2 = "NO_ACCESS"

    assert lines[0] == expected_line_1, f"Line 1 in {RESULTS_PATH} is incorrect. Expected: '{expected_line_1}', Got: '{lines[0]}'"
    assert lines[1] == expected_line_2, f"Line 2 in {RESULTS_PATH} is incorrect. Expected: '{expected_line_2}', Got: '{lines[1]}'"


def test_required_scenarios_execute_to_recorded_values():
    first = run_script("Mallory", "Project_Apollo_Secrets")
    second = run_script("Bob", "Public_Share")
    assert first.returncode == 0, first.stderr
    assert second.returncode == 0, second.stderr
    assert first.stdout.strip() == "Employee:Mallory -> Group:Interns -> Group:Dev_Team -> Group:Engineering -> Group:SuperAdmins -> Resource:Project_Apollo_Secrets"
    assert second.stdout.strip() == "NO_ACCESS"


def test_script_dynamic_execution():
    result = run_script("Bob", "Financial_Q4_Report")
    assert result.returncode == 0, f"Script execution failed: {result.stderr}"
    output = result.stdout.strip()
    expected_output = "Employee:Bob -> Group:HR -> Group:All_Staff -> Resource:Financial_Q4_Report"
    assert output == expected_output, f"Script failed dynamic test. Expected: '{expected_output}', Got: '{output}'"


def test_script_dynamic_execution_no_access():
    result = run_script("Alice", "Project_Apollo_Secrets")
    assert result.returncode == 0, f"Script execution failed: {result.stderr}"
    output = result.stdout.strip()
    expected_output = "NO_ACCESS"
    assert output == expected_output, f"Script failed dynamic NO_ACCESS test. Expected: '{expected_output}', Got: '{output}'"


def test_randomized_database_contents_shortest_path_and_recursive_cli():
    token = uuid.uuid4().hex
    username = "AuditUser_" + token
    resource = "AuditResource_" + token
    short0 = "ShortEntry_" + token
    short1 = "ShortGrant_" + token
    long0 = "LongEntry_" + token
    long1 = "LongMiddle_" + token
    long2 = "LongGrant_" + token

    with sqlite3.connect(DB_PATH) as db:
        next_user = db.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM users").fetchone()[0]
        next_group = db.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM groups").fetchone()[0]
        next_resource = db.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM resources").fetchone()[0]
        group_ids = {
            short0: next_group,
            short1: next_group + 1,
            long0: next_group + 2,
            long1: next_group + 3,
            long2: next_group + 4,
        }
        db.execute("INSERT INTO users(id, username) VALUES (?, ?)", (next_user, username))
        db.execute("INSERT INTO resources(id, name, classification) VALUES (?, ?, ?)",
                   (next_resource, resource, "Verifier generated"))
        db.executemany("INSERT INTO groups(id, name) VALUES (?, ?)",
                       [(gid, name) for name, gid in group_ids.items()])
        db.executemany("INSERT INTO user_groups(user_id, group_id) VALUES (?, ?)", [
            (next_user, group_ids[long0]),
            (next_user, group_ids[short0]),
        ])
        db.executemany("INSERT INTO group_nesting(child_group_id, parent_group_id) VALUES (?, ?)", [
            (group_ids[short0], group_ids[short1]),
            (group_ids[long0], group_ids[long1]),
            (group_ids[long1], group_ids[long2]),
        ])
        db.executemany("INSERT INTO group_resources(group_id, resource_id) VALUES (?, ?)", [
            (group_ids[short1], next_resource),
            (group_ids[long2], next_resource),
        ])

    expected = f"Employee:{username} -> Group:{short0} -> Group:{short1} -> Resource:{resource}"
    with trace_sqlite_cli() as trace_path:
        result = run_script(username, resource)

    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == expected
    assert os.path.isfile(trace_path), "The script did not execute the sqlite3 CLI."
    with open(trace_path, "r", errors="replace") as f:
        trace = f.read()
    assert re.search(r"\bWITH\s+RECURSIVE\b", trace, re.IGNORECASE), \
        "The SQL actually sent to sqlite3 must use WITH RECURSIVE."

    missing_user = "MissingUser_" + uuid.uuid4().hex
    no_access = run_script(missing_user, resource)
    assert no_access.returncode == 0, no_access.stderr
    assert no_access.stdout.strip() == "NO_ACCESS"


def test_secure_dynamic_parameters_with_quotes():
    token = uuid.uuid4().hex
    username = "O'Brien_" + token
    group = "Legal's_Group_" + token
    resource = "Quarter's_Report_" + token

    with sqlite3.connect(DB_PATH) as db:
        uid = db.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM users").fetchone()[0]
        gid = db.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM groups").fetchone()[0]
        rid = db.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM resources").fetchone()[0]
        db.execute("INSERT INTO users(id, username) VALUES (?, ?)", (uid, username))
        db.execute("INSERT INTO groups(id, name) VALUES (?, ?)", (gid, group))
        db.execute("INSERT INTO resources(id, name, classification) VALUES (?, ?, ?)",
                   (rid, resource, "Verifier generated"))
        db.execute("INSERT INTO user_groups(user_id, group_id) VALUES (?, ?)", (uid, gid))
        db.execute("INSERT INTO group_resources(group_id, resource_id) VALUES (?, ?)", (gid, rid))

    result = run_script(username, resource)
    assert result.returncode == 0, result.stderr
    assert result.stdout.strip() == f"Employee:{username} -> Group:{group} -> Resource:{resource}"

    injection = run_script("x' OR 1=1 --", resource)
    assert injection.returncode == 0, injection.stderr
    assert injection.stdout.strip() == "NO_ACCESS"
    with sqlite3.connect(DB_PATH) as db:
        assert db.execute("SELECT COUNT(*) FROM users WHERE username = ?", (username,)).fetchone()[0] == 1


def test_requires_exactly_two_arguments():
    for args in [(), ("Mallory",), ("Mallory", "Project_Apollo_Secrets", "extra")]:
        result = run_script(*args)
        assert result.returncode != 0, f"Script must reject {len(args)} arguments."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

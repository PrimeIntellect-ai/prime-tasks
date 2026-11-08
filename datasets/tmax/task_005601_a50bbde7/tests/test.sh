#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import sqlite3
import stat
import subprocess
import sys
import pytest

POLICIES_PATH = '/home/user/policies.json'
DB_PATH = '/home/user/iam.db'
AUDIT_PATH = '/home/user/audit.py'
RESULT_PATH = '/home/user/audit_result.json'


def remove_path(path):
    if os.path.islink(path) or os.path.isfile(path):
        os.unlink(path)
    elif os.path.isdir(path):
        shutil.rmtree(path)


def restore_original_inputs():
    """Restore the exact policy and IAM database supplied by setup."""
    remove_path(POLICIES_PATH)
    remove_path(DB_PATH)

    policies = {
        "DOC-12A": {"allowed_groups": ["All-Staff"]},
        "DOC-77X": {"allowed_groups": ["Compliance", "IT-Admin"]},
    }
    with open(POLICIES_PATH, 'w') as f:
        json.dump(policies, f)

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute('CREATE TABLE users (id INTEGER PRIMARY KEY, username TEXT)')
    cursor.execute('CREATE TABLE groups (id INTEGER PRIMARY KEY, group_name TEXT)')
    cursor.execute('CREATE TABLE group_members (group_id INTEGER, member_user_id INTEGER, member_group_id INTEGER)')

    cursor.executemany('INSERT INTO users VALUES (?, ?)', [
        (1, 'alice'),
        (2, 'bob'),
        (3, 'charlie'),
        (4, 'david'),
        (5, 'eve'),
    ])
    cursor.executemany('INSERT INTO groups VALUES (?, ?)', [
        (101, 'Compliance'),
        (102, 'IT-Admin'),
        (103, 'SysOps'),
        (104, 'All-Staff'),
        (105, 'Contractors'),
    ])
    cursor.executemany('INSERT INTO group_members VALUES (?, ?, ?)', [
        (101, 1, None),
        (102, 2, None),
        (102, None, 103),
        (103, 3, None),
        (104, 4, None),
        (104, None, 101),
        (104, None, 102),
    ])
    conn.commit()
    conn.close()


def get_expected_users():
    """Derive expected users from the freshly restored original inputs."""
    assert os.path.exists(POLICIES_PATH), f"Missing {POLICIES_PATH}"
    assert os.path.exists(DB_PATH), f"Missing {DB_PATH}"

    with open(POLICIES_PATH, 'r') as f:
        policies = json.load(f)

    allowed_groups = policies.get("DOC-77X", {}).get("allowed_groups", [])
    if not allowed_groups:
        return []

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    placeholders = ','.join(['?'] * len(allowed_groups))
    cursor.execute(f"SELECT id FROM groups WHERE group_name IN ({placeholders})", allowed_groups)
    group_ids = [row[0] for row in cursor.fetchall()]

    visited_groups = set()
    queue = list(group_ids)
    user_ids = set()

    while queue:
        current_group = queue.pop(0)
        if current_group in visited_groups:
            continue
        visited_groups.add(current_group)

        cursor.execute(
            "SELECT member_user_id, member_group_id FROM group_members WHERE group_id = ?",
            (current_group,),
        )
        for u_id, g_id in cursor.fetchall():
            if u_id is not None:
                user_ids.add(u_id)
            if g_id is not None and g_id not in visited_groups:
                queue.append(g_id)

    if not user_ids:
        conn.close()
        return []

    u_placeholders = ','.join(['?'] * len(user_ids))
    cursor.execute(f"SELECT username FROM users WHERE id IN ({u_placeholders})", list(user_ids))
    usernames = sorted([row[0] for row in cursor.fetchall()])
    conn.close()
    return usernames


def test_audit_result_correctness():
    assert os.path.lexists(AUDIT_PATH), f"The required script {AUDIT_PATH} was not created."
    audit_stat = os.stat(AUDIT_PATH, follow_symlinks=False)
    assert stat.S_ISREG(audit_stat.st_mode), f"{AUDIT_PATH} must be a regular file, not a symlink or directory."

    restore_original_inputs()
    expected_users = get_expected_users()
    remove_path(RESULT_PATH)

    try:
        completed = subprocess.run(
            [sys.executable, AUDIT_PATH],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{AUDIT_PATH} did not finish within 15 seconds.")

    assert completed.returncode == 0, (
        f"{AUDIT_PATH} exited with status {completed.returncode}.\n"
        f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
    )

    assert os.path.exists(RESULT_PATH), f"The output file {RESULT_PATH} was not created."

    with open(RESULT_PATH, 'r') as f:
        try:
            result = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {RESULT_PATH} does not contain valid JSON.")

    assert "document" in result, "The key 'document' is missing from the JSON output."
    assert result["document"] == "DOC-77X", f"Expected document 'DOC-77X', but got '{result['document']}'."

    assert "authorized_users" in result, "The key 'authorized_users' is missing from the JSON output."
    actual_users = result["authorized_users"]

    assert isinstance(actual_users, list), "'authorized_users' should be a list."
    assert actual_users == sorted(actual_users), "The 'authorized_users' list is not sorted alphabetically."
    assert len(actual_users) == len(set(actual_users)), "The 'authorized_users' list contains duplicate usernames."
    assert actual_users == expected_users, f"Authorized users mismatch. Expected {expected_users}, but got {actual_users}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

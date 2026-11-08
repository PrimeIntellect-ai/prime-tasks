#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sqlite3
import subprocess
import sys
import pytest

DB_PATH = '/home/user/iam_graph.db'
SCRIPT_PATH = '/home/user/audit_script.py'
OUTPUT_FILE = '/home/user/flagged_users.txt'

def get_expected_users(db_path):
    """
    Derives the expected users who have WRITE access to FINANCIAL_LEDGER
    by querying the database with the exact rules specified in the prompt.
    """
    if not os.path.exists(db_path):
        pytest.fail(f"Database file {db_path} is missing. Cannot determine truth.")

    conn = sqlite3.connect(db_path)
    c = conn.cursor()

    query = """
    WITH RECURSIVE RoleInheritance AS (
        -- Base cases: Roles that directly have CAN_WRITE to FINANCIAL_LEDGER
        SELECT e.source_id as role_id
        FROM edges e
        JOIN nodes n ON e.target_id = n.id
        WHERE e.rel_type = 'CAN_WRITE' AND n.name = 'FINANCIAL_LEDGER' AND n.type = 'ASSET'

        UNION ALL

        -- Recursive step: Roles that INHERIT from a role in RoleInheritance
        SELECT e.source_id as role_id
        FROM edges e
        JOIN RoleInheritance ri ON e.target_id = ri.role_id
        WHERE e.rel_type = 'INHERITS'
    )
    SELECT DISTINCT u.name
    FROM nodes u
    JOIN edges e ON u.id = e.source_id
    JOIN RoleInheritance ri ON e.target_id = ri.role_id
    WHERE u.type = 'USER' AND e.rel_type = 'HAS_ROLE'
    ORDER BY u.name ASC;
    """

    try:
        c.execute(query)
        users = [row[0] for row in c.fetchall()]
    except sqlite3.Error as e:
        pytest.fail(f"Failed to query the database to determine expected state: {e}")
    finally:
        conn.close()

    return users

def test_audit_script_exists_and_runs():
    assert os.path.exists(SCRIPT_PATH), f"The required script '{SCRIPT_PATH}' does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"'{SCRIPT_PATH}' is not a file."

    if os.path.lexists(OUTPUT_FILE):
        if os.path.isdir(OUTPUT_FILE) and not os.path.islink(OUTPUT_FILE):
            pytest.fail(f"Expected output path '{OUTPUT_FILE}' is a directory.")
        os.unlink(OUTPUT_FILE)

    try:
        result = subprocess.run(
            [sys.executable, SCRIPT_PATH],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"The script '{SCRIPT_PATH}' did not finish within 30 seconds.")

    assert result.returncode == 0, (
        f"The script '{SCRIPT_PATH}' failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )
    assert os.path.exists(OUTPUT_FILE), (
        f"Running '{SCRIPT_PATH}' did not create '{OUTPUT_FILE}'."
    )

def test_flagged_users_file_exists():
    assert os.path.exists(OUTPUT_FILE), f"The output file '{OUTPUT_FILE}' does not exist."
    assert os.path.isfile(OUTPUT_FILE), f"'{OUTPUT_FILE}' is not a file."

def test_flagged_users_content():
    assert os.path.exists(OUTPUT_FILE), f"Cannot check content, '{OUTPUT_FILE}' is missing."

    expected_users = get_expected_users(DB_PATH)

    with open(OUTPUT_FILE, 'r') as f:
        content = f.read().strip()

    if not content:
        pytest.fail(f"The output file '{OUTPUT_FILE}' is empty.")

    actual_users = [line.strip() for line in content.splitlines() if line.strip()]

    assert actual_users == expected_users, (
        f"The users in '{OUTPUT_FILE}' do not match the expected result.\n"
        f"Expected: {expected_users}\n"
        f"Actual:   {actual_users}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

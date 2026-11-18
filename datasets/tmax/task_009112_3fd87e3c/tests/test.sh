#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import sqlite3
import subprocess
import pytest

SCRIPT_PATH = '/home/user/run_audit.sh'
CSV_PATH = '/home/user/suspicious_accounts.csv'
DB_PATH = '/home/user/audit.db'


@pytest.fixture(scope='session', autouse=True)
def run_submitted_script():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} does not exist."

    # Derive the expected result from the supplied database before executing the
    # submission, rather than relying on a hardcoded CSV.
    conn = sqlite3.connect(DB_PATH)
    cur = conn.cursor()
    cur.execute("""
        SELECT a.account_id, a.owner_name, SUM(t1.amount)
        FROM transactions AS t1
        JOIN transactions AS t2
          ON t1.receiver_id = t2.sender_id
        JOIN transactions AS t3
          ON t2.receiver_id = t3.sender_id
         AND t3.receiver_id = t1.sender_id
        JOIN accounts AS a
          ON a.account_id = t1.sender_id
        WHERE t1.tx_timestamp < t2.tx_timestamp
          AND t2.tx_timestamp < t3.tx_timestamp
        GROUP BY a.account_id, a.owner_name
        ORDER BY a.account_id DESC
    """)
    expected_content = [f"{account_id},{owner_name},{total}" for account_id, owner_name, total in cur.fetchall()]

    # Ensure the index assertion verifies indexes created by the submitted
    # script itself, not indexes created manually before verification.
    cur.execute("""
        SELECT name
        FROM sqlite_master
        WHERE type='index'
          AND tbl_name='transactions'
          AND name NOT LIKE 'sqlite_autoindex%'
    """)
    for (name,) in cur.fetchall():
        quoted_name = name.replace('"', '""')
        cur.execute(f'DROP INDEX "{quoted_name}"')
    conn.commit()
    conn.close()

    if os.path.lexists(CSV_PATH):
        if os.path.isdir(CSV_PATH) and not os.path.islink(CSV_PATH):
            pytest.fail(f"{CSV_PATH} is a directory and cannot be replaced safely.")
        os.remove(CSV_PATH)

    try:
        result = subprocess.run(
            [SCRIPT_PATH],
            cwd='/home/user',
            text=True,
            capture_output=True,
            timeout=30,
        )
    except subprocess.TimeoutExpired:
        pytest.fail('Submitted audit script timed out.')

    assert result.returncode == 0, (
        f"Submitted script exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\n"
        f"stderr:\n{result.stderr}"
    )

    return expected_content


def test_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f"Script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    assert os.access(SCRIPT_PATH, os.X_OK), f"Script {SCRIPT_PATH} is not executable."


def test_csv_exists():
    assert os.path.exists(CSV_PATH), f"Output file {CSV_PATH} does not exist."
    assert os.path.isfile(CSV_PATH), f"{CSV_PATH} is not a file."


def test_csv_content(run_submitted_script):
    expected_content = run_submitted_script

    with open(CSV_PATH, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert lines == expected_content, (
        f"CSV content does not match expected.\n"
        f"Expected:\n{expected_content}\n"
        f"Found:\n{lines}"
    )


def test_indexes_created():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} does not exist."

    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("""
        SELECT name
        FROM sqlite_master
        WHERE type='index' AND tbl_name='transactions' AND name NOT LIKE 'sqlite_autoindex%'
    """)
    indexes = c.fetchall()
    conn.close()

    assert len(indexes) > 0, "No indexes were created on the 'transactions' table to optimize the query."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

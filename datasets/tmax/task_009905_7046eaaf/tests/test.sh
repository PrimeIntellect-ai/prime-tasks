#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import shutil
import sqlite3
import statistics
import subprocess
import tempfile

SCRIPT_PATH = "/home/user/fraud_check.py"
DB_PATH = "/home/user/transactions.db"
OUTPUT_PATH = "/home/user/flagged_accounts.txt"


def run_script():
    if os.path.lexists(OUTPUT_PATH):
        os.unlink(OUTPUT_PATH)
    subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        check=True,
        timeout=20,
    )


def expected_lines(db_path):
    conn = sqlite3.connect(db_path)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT id FROM accounts WHERE status IN ('active', 'suspended')")
        valid_accounts = [row[0] for row in cursor.fetchall()]

        expected = []
        for acc_id in sorted(valid_accounts):
            cursor.execute(
                "SELECT amount FROM transactions WHERE account_id = ?",
                (acc_id,),
            )
            txs = [row[0] for row in cursor.fetchall()]
            if len(txs) > 1:
                sd = statistics.stdev(txs)
                expected.append(f"{acc_id},{sd:.4f}")
        return expected
    finally:
        conn.close()


def actual_lines():
    assert os.path.isfile(OUTPUT_PATH), f"Output file missing: {OUTPUT_PATH}"
    with open(OUTPUT_PATH, "r") as f:
        return [line.strip() for line in f if line.strip()]


def assert_output_matches(db_path):
    expected = expected_lines(db_path)
    actual = actual_lines()
    assert actual == expected, (
        "Output file contents do not match the expected values.\n"
        f"Expected: {expected}\nActual: {actual}"
    )


def create_dynamic_database(path):
    ids = sorted(secrets.SystemRandom().sample(range(1000, 9000), 4))
    active_id, suspended_id, closed_id, singleton_id = ids
    base = 10_000_000_000 + secrets.randbelow(1_000_000)

    conn = sqlite3.connect(path)
    try:
        cursor = conn.cursor()
        cursor.execute("CREATE TABLE accounts (id INTEGER PRIMARY KEY, status TEXT)")
        cursor.execute("CREATE TABLE transactions (account_id INTEGER, amount REAL)")
        cursor.executemany(
            "INSERT INTO accounts VALUES (?, ?)",
            [
                (active_id, "active"),
                (suspended_id, "suspended"),
                (closed_id, "closed"),
                (singleton_id, "active"),
            ],
        )
        cursor.executemany(
            "INSERT INTO transactions VALUES (?, ?)",
            [
                (active_id, base + 0.01),
                (active_id, base + 0.02),
                (active_id, base + 0.01),
                (active_id, base + 0.03),
                (suspended_id, 13.0),
                (suspended_id, 21.0),
                (suspended_id, 34.0),
                (closed_id, 1.0),
                (closed_id, 100.0),
                (singleton_id, 7.0),
            ],
        )
        conn.commit()
    finally:
        conn.close()


def test_fraud_check_script_and_output():
    assert os.path.isfile(SCRIPT_PATH), f"Script missing: {SCRIPT_PATH}"
    assert os.path.isfile(DB_PATH), f"Database file missing: {DB_PATH}"

    # Execute the submitted artifact and retain the original fixed-database check.
    run_script()
    assert_output_matches(DB_PATH)

    with tempfile.TemporaryDirectory() as tmpdir:
        backup_path = os.path.join(tmpdir, "original.db")
        dynamic_path = os.path.join(tmpdir, "dynamic.db")
        shutil.copy2(DB_PATH, backup_path)
        create_dynamic_database(dynamic_path)

        try:
            shutil.copy2(dynamic_path, DB_PATH)
            run_script()
            assert_output_matches(DB_PATH)
        finally:
            shutil.copy2(backup_path, DB_PATH)
            # Leave the required output artifact generated from the original DB.
            run_script()

    assert_output_matches(DB_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

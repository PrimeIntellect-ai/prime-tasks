#!/bin/bash
set +e
mkdir -p /logs/verifier

APP_DIR=/home/user/app
BACKUP_DB=/tmp/recon-data.db.backup
rm -f "$BACKUP_DB"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import re
import sqlite3
import subprocess
from decimal import Decimal

APP_DIR = "/home/user/app"
RESULT_FILE = os.path.join(APP_DIR, "result.txt")
DB_GO_FILE = os.path.join(APP_DIR, "db.go")
AGGREGATOR_GO_FILE = os.path.join(APP_DIR, "aggregator.go")
BINARY = os.path.join(APP_DIR, "recon-service")
DB_FILE = os.path.join(APP_DIR, "data.db")


def run_service(expected):
    proc = subprocess.run(
        [BINARY],
        cwd=APP_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=5,
    )
    assert proc.returncode == 0, f"service exited with {proc.returncode}: {proc.stderr}"
    assert len(proc.stdout.splitlines()) == 1, f"service produced extra output: {proc.stdout!r}"
    assert proc.stdout.strip() == expected, (
        f"Expected exact output {expected!r}, got {proc.stdout.strip()!r}. "
        f"stderr was: {proc.stderr!r}"
    )


def replace_database(accounts, transactions):
    conn = sqlite3.connect(DB_FILE)
    try:
        conn.executescript("""
            DROP TABLE IF EXISTS transactions;
            DROP TABLE IF EXISTS accounts;
            CREATE TABLE accounts (id INTEGER PRIMARY KEY, parent_id INTEGER);
            CREATE TABLE transactions (
                id INTEGER PRIMARY KEY,
                account_id INTEGER,
                amount REAL,
                status TEXT
            );
        """)
        conn.executemany("INSERT INTO accounts(id, parent_id) VALUES (?, ?)", accounts)
        conn.executemany(
            "INSERT INTO transactions(id, account_id, amount, status) VALUES (?, ?, ?, ?)",
            transactions,
        )
        conn.commit()
    finally:
        conn.close()


def cents_output(cents):
    sign = "-" if cents < 0 else ""
    cents = abs(cents)
    return f"Total: {sign}{cents // 100}.{cents % 100:02d}"


def test_result_file_exists_and_correct():
    assert os.path.isfile(RESULT_FILE), f"Expected result file {RESULT_FILE} does not exist. Did you run the service and redirect output?"
    with open(RESULT_FILE, "r") as f:
        content = f.read().strip()
    assert content == "Total: 1501.50", f"Expected exact output 'Total: 1501.50', but got '{content}'. Check your precision, cycle detection, and SETTLED filtering."


def test_db_go_filtering():
    assert os.path.isfile(DB_GO_FILE), f"File {DB_GO_FILE} is missing."
    with open(DB_GO_FILE, "r") as f:
        content = f.read()
    assert "SETTLED" in content, "db.go does not appear to filter transactions by the 'SETTLED' status."


def test_aggregator_go_precision_fix():
    assert os.path.isfile(AGGREGATOR_GO_FILE), f"File {AGGREGATOR_GO_FILE} is missing."
    with open(AGGREGATOR_GO_FILE, "r") as f:
        content = f.read()
    assert "float32" not in content, "aggregator.go still contains 'float32'. You must use exact integer arithmetic (cents) for accumulation to prevent precision loss."
    assert re.search(r"\bint64\b", content), "aggregator.go must accumulate monetary values as int64 cents."


def test_runtime_handles_cycles_disconnected_accounts_and_statuses():
    # Values are generated at verification time, and the expected answer is
    # independently derived from the generated settled transaction cents.
    rng = random.SystemRandom()
    accounts = [
        (1, None),
        (2, 1),
        (3, 2),
        (4, 5),
        (5, 4),       # dirty disconnected cycle
        (6, 3),
        (7, 6),
    ]
    transactions = []
    expected_cents = 0
    txid = 1
    for account_id, _ in accounts:
        for _ in range(2):
            cents = rng.randint(101, 900000)
            expected_cents += cents
            transactions.append((txid, account_id, f"{cents // 100}.{cents % 100:02d}", "SETTLED"))
            txid += 1
        pending_cents = rng.randint(500000, 1500000)
        transactions.append((txid, account_id, f"{pending_cents // 100}.{pending_cents % 100:02d}", "PENDING"))
        txid += 1

    # These near-miss statuses must not be treated as SETTLED.
    transactions.append((txid, 1, "7777.77", "SETTLED "))
    transactions.append((txid + 1, 2, "8888.88", "settled"))
    replace_database(accounts, transactions)
    run_service(cents_output(expected_cents))


def test_runtime_terminates_on_reachable_cycle_and_counts_each_account_once():
    accounts = [(1, 3), (2, 1), (3, 2)]
    transactions = [
        (1, 1, "11.11", "SETTLED"),
        (2, 2, "22.22", "SETTLED"),
        (3, 3, "33.33", "SETTLED"),
        (4, 1, "9999.99", "PENDING"),
    ]
    replace_database(accounts, transactions)
    run_service("Total: 66.66")


def test_runtime_avoids_float32_accumulation_loss():
    accounts = [(1, None)]
    transactions = [(i, 1, "0.01", "SETTLED") for i in range(1, 50001)]
    transactions.append((50001, 1, "12345.67", "PENDING"))
    replace_database(accounts, transactions)
    run_service("Total: 500.00")
TEST_EOF

passed=0
if cp "$APP_DIR/data.db" "$BACKUP_DB" \
   && cd "$APP_DIR" \
   && go build -o recon-service . \
   && timeout 5 ./recon-service > "$APP_DIR/result.txt" \
   && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    passed=1
fi

if [ -f "$BACKUP_DB" ]; then
    cp "$BACKUP_DB" "$APP_DIR/data.db"
fi

if [ "$passed" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0

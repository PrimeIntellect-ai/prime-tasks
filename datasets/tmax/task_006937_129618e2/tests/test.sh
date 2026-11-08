#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import random
import re
import shutil
import sqlite3
import subprocess

SCRIPT = "/home/user/detect_cycles.sh"
USERS = "/home/user/users.csv"
TRANSACTIONS = "/home/user/transactions.csv"
DB = "/home/user/graph.db"
OUTPUT = "/home/user/cycle_summary.csv"


def test_script_exists_and_executable():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."
    with open(SCRIPT, "rb") as f:
        first_line = f.readline().decode("utf-8", errors="replace").lower()
    assert first_line.startswith("#!") and "bash" in first_line, "Submission is not a Bash script."


def test_script_execution_and_output():
    # Preserve the original execution and exact-output assertions.
    result = subprocess.run([SCRIPT], capture_output=True, text=True)
    assert result.returncode == 0, f"Script failed to execute. stderr: {result.stderr}"

    assert os.path.isfile(DB), f"Database {DB} was not created by the script."
    assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} was not created by the script."

    with open(OUTPUT, "r") as f:
        content = [line.strip() for line in f.read().strip().split('\n') if line.strip()]

    expected_content = [
        "name,total_outgoing_cycle_amount",
        "Alice,1200",
        "Bob,700",
        "Charlie,1700",
        "David,1000"
    ]
    assert content == expected_content, (
        f"Output CSV content does not match expected.\n"
        f"Expected: {expected_content}\nGot: {content}"
    )


def expected_summary(users, transactions):
    participating = set()
    for i, first in enumerate(transactions):
        if first[3] < 500:
            continue
        for second in transactions:
            if second[3] < 500 or first[2] != second[1]:
                continue
            for third in transactions:
                if third[3] < 500:
                    continue
                if second[2] == third[1] and third[2] == first[1]:
                    if len({first[1], first[2], second[2]}) == 3:
                        participating.update((i, transactions.index(second), transactions.index(third)))

    totals = {}
    for i in participating:
        _, sender, _, amount = transactions[i]
        totals[sender] = totals.get(sender, 0) + amount

    names = dict(users)
    rows = [(names[user_id], total) for user_id, total in totals.items()]
    return sorted(rows, key=lambda row: row[0])


def assert_database_imported(users, transactions):
    assert os.path.isfile(DB), f"Database {DB} was not created by the script."
    con = sqlite3.connect(DB)
    try:
        tables = {row[0] for row in con.execute(
            "SELECT name FROM sqlite_master WHERE type='table'"
        )}
        assert "users" in tables, "Database does not contain a users table."
        assert "transactions" in tables, "Database does not contain a transactions table."

        actual_users = {
            (str(row[0]), str(row[1]))
            for row in con.execute("SELECT id, name FROM users")
        }
        expected_users = {(str(uid), name) for uid, name in users}
        assert actual_users == expected_users, "The users table was not imported from the supplied CSV."

        actual_transactions = {
            tuple(str(value) for value in row)
            for row in con.execute(
                "SELECT tx_id, sender_id, receiver_id, amount FROM transactions"
            )
        }
        expected_transactions = {
            tuple(str(value) for value in row) for row in transactions
        }
        assert actual_transactions == expected_transactions, (
            "The transactions table was not imported from the supplied CSV."
        )
    finally:
        con.close()


def test_fresh_inputs_database_and_graph_computation():
    # Use values unavailable when the agent wrote its script, so a fixed output or
    # empty placeholder database cannot pass.
    rng = random.SystemRandom()
    ids = rng.sample(range(1000, 9000), 6)
    suffixes = [f"{rng.randrange(0, 1 << 32):08x}" for _ in range(6)]
    names = [prefix + suffix for prefix, suffix in zip(
        ["Zara_", "Amy_", "Mike_", "Beth_", "Omar_", "Nina_"], suffixes
    )]
    users = list(zip(ids, names))
    a, b, c, d, e, f = ids

    amounts = [rng.randrange(500, 1300) for _ in range(9)]
    transactions = [
        (rng.randrange(10000, 20000), a, b, amounts[0]),
        (rng.randrange(20000, 30000), b, c, amounts[1]),
        (rng.randrange(30000, 40000), c, a, amounts[2]),
        # A second transaction on an edge: both transactions participate.
        (rng.randrange(40000, 50000), a, b, amounts[3]),
        (rng.randrange(50000, 60000), b, d, amounts[4]),
        (rng.randrange(60000, 70000), d, e, amounts[5]),
        (rng.randrange(70000, 80000), e, b, amounts[6]),
        # These form the topology of a cycle, but one edge is below threshold.
        (rng.randrange(80000, 90000), c, d, amounts[7]),
        (rng.randrange(90000, 100000), d, f, amounts[8]),
        (rng.randrange(100000, 110000), f, c, rng.randrange(1, 500)),
        # Self-loop and two-node traffic must not become length-3 cycles.
        (rng.randrange(110000, 120000), e, e, rng.randrange(500, 1300)),
        (rng.randrange(120000, 130000), a, f, rng.randrange(500, 1300)),
        (rng.randrange(130000, 140000), f, a, rng.randrange(500, 1300)),
    ]

    with open(USERS, "rb") as fobj:
        old_users = fobj.read()
    with open(TRANSACTIONS, "rb") as fobj:
        old_transactions = fobj.read()

    real_sqlite = "/tmp/verifier-real-sqlite3"
    sqlite_binary = shutil.which("sqlite3")
    assert sqlite_binary, "sqlite3 is not installed."
    sqlite_binary = os.path.realpath(sqlite_binary)
    sql_log = "/tmp/verifier-sqlite.log"

    try:
        with open(USERS, "w", newline="") as fobj:
            writer = csv.writer(fobj, lineterminator="\n")
            writer.writerow(["id", "name"])
            writer.writerows(users)
        with open(TRANSACTIONS, "w", newline="") as fobj:
            writer = csv.writer(fobj, lineterminator="\n")
            writer.writerow(["tx_id", "sender_id", "receiver_id", "amount"])
            writer.writerows(transactions)

        for path in (DB, OUTPUT, sql_log):
            if os.path.exists(path):
                os.remove(path)

        # Instrument sqlite3 during execution to verify that the requested CLI is
        # actually invoked, while forwarding all arguments and SQL unchanged.
        shutil.copy2(sqlite_binary, real_sqlite)
        with open(sqlite_binary, "w") as fobj:
            fobj.write("""#!/bin/bash
printf 'ARGS:' >> /tmp/verifier-sqlite.log
printf ' %q' "$@" >> /tmp/verifier-sqlite.log
printf '\\nSTDIN:\\n' >> /tmp/verifier-sqlite.log
tmp=$(mktemp)
cat > "$tmp"
cat "$tmp" >> /tmp/verifier-sqlite.log
printf '\\nEND\\n' >> /tmp/verifier-sqlite.log
/tmp/verifier-real-sqlite3 "$@" < "$tmp"
status=$?
rm -f "$tmp"
exit $status
""")
        os.chmod(sqlite_binary, 0o755)

        result = subprocess.run([SCRIPT], capture_output=True, text=True, timeout=30)

        shutil.copy2(real_sqlite, sqlite_binary)
        os.chmod(sqlite_binary, 0o755)

        assert result.returncode == 0, (
            f"Script failed on a fresh valid input. stderr: {result.stderr}"
        )
        assert os.path.isfile(sql_log), "The script did not execute the sqlite3 command-line tool."
        with open(sql_log, "r", errors="replace") as fobj:
            sql_activity = fobj.read()
        with open(SCRIPT, "r", errors="replace") as fobj:
            script_text = fobj.read()
        combined_sql_evidence = sql_activity + "\n" + script_text
        assert re.search(r"\btransactions\b", combined_sql_evidence, re.I), (
            "No SQLite transaction-table query was found."
        )
        assert re.search(r"\b(with|join)\b", combined_sql_evidence, re.I), (
            "No CTE/join-based graph query was found."
        )

        assert_database_imported(users, transactions)
        assert os.path.isfile(OUTPUT), f"Output file {OUTPUT} was not created by the script."
        with open(OUTPUT, newline="") as fobj:
            actual = list(csv.reader(fobj))

        expected = [["name", "total_outgoing_cycle_amount"]]
        expected.extend([[name, str(total)] for name, total in expected_summary(users, transactions)])
        assert actual == expected, f"Fresh-input result mismatch. Expected {expected}, got {actual}"
    finally:
        if os.path.exists(real_sqlite):
            shutil.copy2(real_sqlite, sqlite_binary)
            os.chmod(sqlite_binary, 0o755)
            os.remove(real_sqlite)
        with open(USERS, "wb") as fobj:
            fobj.write(old_users)
        with open(TRANSACTIONS, "wb") as fobj:
            fobj.write(old_transactions)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

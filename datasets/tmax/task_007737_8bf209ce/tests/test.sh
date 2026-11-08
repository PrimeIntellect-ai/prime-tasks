#!/bin/bash
set +e
mkdir -p /logs/verifier

SQLITE_REAL="/tmp/verifier_sqlite3_real_$$"
SQLITE_LOG="/tmp/verifier_sqlite_calls.jsonl"
rm -f "$SQLITE_LOG"

if ! mv /usr/bin/sqlite3 "$SQLITE_REAL"; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

restore_sqlite() {
    rm -f /usr/bin/sqlite3
    mv "$SQLITE_REAL" /usr/bin/sqlite3 2>/dev/null || true
}
trap restore_sqlite EXIT

cat > /usr/bin/sqlite3 <<EOF
#!/usr/bin/python3
import json
import subprocess
import sys

real = ${SQLITE_REAL@Q}
log_path = ${SQLITE_LOG@Q}
data = sys.stdin.buffer.read()
with open(log_path, "a", encoding="utf-8") as log:
    log.write(json.dumps({
        "argv": sys.argv[1:],
        "stdin": data.decode("utf-8", errors="replace")
    }) + "\\n")
result = subprocess.run([real] + sys.argv[1:], input=data)
sys.exit(result.returncode)
EOF
chmod 755 /usr/bin/sqlite3
touch "$SQLITE_LOG"
chmod 666 "$SQLITE_LOG"

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import sqlite3
import subprocess
import time
from collections import defaultdict

import pytest

SCRIPT = "/home/user/analyze.sh"
DB = "/home/user/finance.db"
ALERTS = "/home/user/alerts.csv"
PLAN = "/home/user/query_plan.txt"
ACCOUNTS = "/home/user/accounts.csv"
TRANSACTIONS = "/home/user/transactions.csv"
CALL_LOG = "/tmp/verifier_sqlite_calls.jsonl"

HIDDEN_ACCOUNTS = """account_id,account_name
1,Alice_Corp
2,Bob_LLC
3,Charlie_Inc
4,Delta_Co
5,Echo_Group
"""

HIDDEN_TRANSACTIONS = """tx_id,src_id,dst_id,amount,tx_date
201,1,2,1000,2024-01-01
202,1,3,2000,2024-01-02
203,1,4,2501,2024-01-03
204,2,3,2000,2024-01-01
205,2,4,2000,2024-01-05
206,2,1,2000,2024-01-06
207,3,1,5001,2024-01-02
208,4,1,3000,2024-01-01
209,5,1,3000,2024-02-01
210,5,2,2500,2024-02-02
"""


@pytest.fixture(scope="session", autouse=True)
def run_submission():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."

    originals = {}
    for path in (ACCOUNTS, TRANSACTIONS):
        with open(path, "rb") as f:
            originals[path] = f.read()

    try:
        with open(ACCOUNTS, "w", encoding="utf-8", newline="") as f:
            f.write(HIDDEN_ACCOUNTS)
        with open(TRANSACTIONS, "w", encoding="utf-8", newline="") as f:
            f.write(HIDDEN_TRANSACTIONS)

        for path in (DB, ALERTS, PLAN):
            try:
                os.remove(path)
            except FileNotFoundError:
                pass
        open(CALL_LOG, "w").close()
        started = time.time_ns()

        result = subprocess.run(
            [SCRIPT],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=45,
        )
        assert result.returncode == 0, (
            f"analyze.sh exited with status {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        yield started
    finally:
        for path, content in originals.items():
            with open(path, "wb") as f:
                f.write(content)


def expected_alert_lines():
    accounts = {}
    with open(ACCOUNTS, "r", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            accounts[row["account_id"]] = row["account_name"]

    transactions = defaultdict(list)
    with open(TRANSACTIONS, "r", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            transactions[row["src_id"]].append(
                {"amount": float(row["amount"]), "tx_date": row["tx_date"]}
            )

    expected = []
    for src_id, txs in transactions.items():
        txs.sort(key=lambda item: item["tx_date"])
        running_total = 0.0
        for tx in txs:
            running_total += tx["amount"]
            if running_total > 5000:
                value = int(running_total) if running_total.is_integer() else running_total
                expected.append((accounts[src_id], tx["tx_date"], value))
                break
    expected.sort(key=lambda row: row[0])
    return [f"{name},{date},{total}" for name, date, total in expected]


def normalize_sql(text):
    text = re.sub(r"--[^\n]*", " ", text)
    text = re.sub(r"/\*.*?\*/", " ", text, flags=re.S)
    return re.sub(r"\s+", " ", text).strip().rstrip(";").lower()


def captured_sql_chunks():
    chunks = []
    with open(CALL_LOG, "r", encoding="utf-8") as f:
        for line in f:
            if not line.strip():
                continue
            call = json.loads(line)
            chunks.extend(str(arg) for arg in call.get("argv", []))
            chunks.append(call.get("stdin", ""))
    return chunks


def test_analyze_script_executable():
    assert os.path.isfile(SCRIPT), f"Script {SCRIPT} does not exist."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."


def test_outputs_were_created_by_execution(run_submission):
    for path in (DB, ALERTS, PLAN):
        assert os.path.isfile(path), f"Required artifact {path} does not exist."
        assert os.stat(path).st_mtime_ns >= run_submission, (
            f"{path} was not freshly produced by analyze.sh."
        )


def test_finance_db_exists_and_index():
    assert os.path.isfile(DB), f"Database {DB} does not exist."
    conn = sqlite3.connect(DB)
    try:
        row = conn.execute(
            "SELECT name, tbl_name FROM sqlite_master "
            "WHERE type='index' AND name='idx_src_date'"
        ).fetchone()
        assert row is not None, "Index 'idx_src_date' was not created in the database."
        assert row[1] == "transactions", "idx_src_date is not on transactions."
        columns = [r[2] for r in conn.execute("PRAGMA index_info('idx_src_date')")]
        assert columns == ["src_id", "tx_date"], (
            f"idx_src_date must cover src_id and tx_date in that order; got {columns}."
        )

        account_count = conn.execute("SELECT COUNT(*) FROM accounts").fetchone()[0]
        transaction_count = conn.execute("SELECT COUNT(*) FROM transactions").fetchone()[0]
        assert account_count == 5, "accounts.csv was not imported completely."
        assert transaction_count == 10, "transactions.csv was not imported completely."
    finally:
        conn.close()


def test_alerts_csv_content():
    assert os.path.isfile(ALERTS), f"Output file {ALERTS} does not exist."
    with open(ALERTS, "r", encoding="utf-8") as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    expected_lines = expected_alert_lines()
    assert actual_lines == expected_lines, (
        f"Content of {ALERTS} does not match expected.\n"
        f"Expected: {expected_lines}\nActual: {actual_lines}"
    )


def test_query_plan_contains_index_and_came_from_matching_explain():
    assert os.path.isfile(PLAN), f"Query plan file {PLAN} does not exist."
    with open(PLAN, "r", encoding="utf-8") as f:
        content = f.read()
    lowered = content.lower()
    assert "idx_src_date" in lowered, (
        f"Query plan in {PLAN} does not indicate usage of 'idx_src_date'."
    )
    assert any(token in lowered for token in ("scan", "search", "co-routine", "coroutine")), (
        f"{PLAN} does not look like SQLite EXPLAIN QUERY PLAN output."
    )

    chunks = captured_sql_chunks()
    assert chunks, "analyze.sh never executed the sqlite3 program."
    corpus = "\n".join(chunks)
    normalized_corpus = normalize_sql(corpus)
    assert " over " in f" {normalized_corpus} ", "No SQLite window function was executed."
    assert "accounts" in normalized_corpus and "transactions" in normalized_corpus, (
        "The captured SQLite work did not query both required tables."
    )

    found_matching_pair = False
    explain_re = re.compile(r"\bEXPLAIN\s+QUERY\s+PLAN\s+(.+?)(?:;|$)", re.I | re.S)
    for chunk_index, chunk in enumerate(chunks):
        for match in explain_re.finditer(chunk):
            explained = normalize_sql(match.group(1))
            if not explained or "select" not in explained:
                continue
            remainder = chunk[:match.start()] + " " + chunk[match.end():]
            other_text = remainder + "\n" + "\n".join(
                value for index, value in enumerate(chunks) if index != chunk_index
            )
            if explained in normalize_sql(other_text):
                found_matching_pair = True
                break
        if found_matching_pair:
            break

    assert found_matching_pair, (
        "sqlite3 was not given EXPLAIN QUERY PLAN for the same SELECT that it also executed."
    )
TEST_EOF

python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
exit 0

#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import json
import os
import re
import secrets
import subprocess

SCRIPT_PATH = "/home/user/etl.sh"
USERS_PATH = "/home/user/users.json"
TRANSACTIONS_PATH = "/home/user/transactions.json"
CSV_PATH = "/home/user/high_value_users.csv"
INDEX_PATH = "/home/user/mongo_index.js"


def write_inputs(users, transactions):
    with open(USERS_PATH, "w") as f:
        json.dump(users, f)
    with open(TRANSACTIONS_PATH, "w") as f:
        json.dump(transactions, f)


def run_etl():
    if os.path.exists(CSV_PATH):
        os.remove(CSV_PATH)
    result = subprocess.run(
        [SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"etl.sh failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(CSV_PATH), f"{CSV_PATH} was not produced by etl.sh."
    with open(CSV_PATH, "r", newline="") as f:
        return f.read().strip().replace("\r", "")


def derive_expected(users, transactions):
    totals = {}
    for tx in transactions:
        if tx.get("status") == "COMPLETED":
            uid = tx.get("user_id")
            totals[uid] = totals.get(uid, 0) + tx.get("amount", 0)

    rows = []
    for user in users:
        total = totals.get(user.get("id"))
        if total is not None and total >= 150:
            rows.append((user.get("id"), user.get("name"), total))
    rows.sort(key=lambda row: row[2], reverse=True)

    out = io.StringIO(newline="")
    writer = csv.writer(out, lineterminator="\n")
    writer.writerow(["user_id", "name", "total_spent"])
    writer.writerows(rows)
    return out.getvalue().strip().replace("\r", "")


def test_01_etl_script_exists_and_executable():
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} does not exist."
    assert os.access(SCRIPT_PATH, os.X_OK), f"{SCRIPT_PATH} is not executable."


def test_02_etl_produces_original_expected_csv():
    users = [
        {"id": 1, "name": "Alice"},
        {"id": 2, "name": "Bob"},
        {"id": 3, "name": "Charlie"},
        {"id": 4, "name": "Diana"},
    ]
    transactions = [
        {"tx_id": 101, "user_id": 1, "amount": 100, "status": "COMPLETED"},
        {"tx_id": 102, "user_id": 1, "amount": 60, "status": "COMPLETED"},
        {"tx_id": 103, "user_id": 2, "amount": 200, "status": "COMPLETED"},
        {"tx_id": 104, "user_id": 2, "amount": 50, "status": "PENDING"},
        {"tx_id": 105, "user_id": 3, "amount": 120, "status": "COMPLETED"},
        {"tx_id": 106, "user_id": 4, "amount": 300, "status": "FAILED"},
    ]
    write_inputs(users, transactions)
    actual_csv = run_etl()
    expected_csv = "user_id,name,total_spent\n2,Bob,200\n1,Alice,160"
    assert actual_csv == expected_csv, (
        f"CSV content does not match expected output.\n"
        f"Expected:\n{expected_csv}\nActual:\n{actual_csv}"
    )


def test_03_etl_uses_current_json_inputs():
    seed = secrets.randbelow(1000000)
    first_id = 1000 + secrets.randbelow(1000)
    ids = [first_id + i for i in range(4)]
    users = [
        {"id": ids[0], "name": f"North_{seed}"},
        {"id": ids[1], "name": f"South_{seed}"},
        {"id": ids[2], "name": f"East_{seed}"},
        {"id": ids[3], "name": f"West_{seed}"},
    ]
    transactions = [
        {"tx_id": seed + 1, "user_id": ids[0], "amount": 91, "status": "COMPLETED"},
        {"tx_id": seed + 2, "user_id": ids[0], "amount": 84, "status": "COMPLETED"},
        {"tx_id": seed + 3, "user_id": ids[0], "amount": 900, "status": "PENDING"},
        {"tx_id": seed + 4, "user_id": ids[1], "amount": 149, "status": "COMPLETED"},
        {"tx_id": seed + 5, "user_id": ids[2], "amount": 320, "status": "COMPLETED"},
        {"tx_id": seed + 6, "user_id": ids[2], "amount": 25, "status": "FAILED"},
        {"tx_id": seed + 7, "user_id": ids[3], "amount": 150, "status": "COMPLETED"},
        {"tx_id": seed + 8, "user_id": ids[3] + 5000, "amount": 999, "status": "COMPLETED"},
        {"tx_id": seed + 9, "user_id": ids[1], "amount": 1000, "status": "completed"},
    ]
    write_inputs(users, transactions)
    actual_csv = run_etl()
    expected_csv = derive_expected(users, transactions)
    assert actual_csv == expected_csv, (
        "etl.sh did not derive the CSV from the current JSON inputs.\n"
        f"Expected:\n{expected_csv}\nActual:\n{actual_csv}"
    )


def test_04_mongo_index_is_one_valid_transactions_command():
    assert os.path.isfile(INDEX_PATH), f"{INDEX_PATH} does not exist."
    with open(INDEX_PATH, "r") as f:
        content = f.read()

    # Accept the standard Mongo shell forms for selecting the transactions
    # collection, but require one complete command and the optimal compound key
    # order: equality-match field first, then grouping field.
    collection = r'''db\s*(?:\.\s*transactions|\[\s*["']transactions["']\s*\]|\.\s*getCollection\s*\(\s*["']transactions["']\s*\))'''
    key_doc = r'''\{\s*(?:"status"|'status'|status)\s*:\s*[+-]?1\s*,\s*(?:"user_id"|'user_id'|user_id)\s*:\s*[+-]?1\s*\}'''
    pattern = re.compile(
        r'''\A\s*''' + collection +
        r'''\s*\.\s*createIndex\s*\(\s*''' + key_doc +
        r'''\s*\)\s*;?\s*\Z''',
        re.DOTALL,
    )
    assert pattern.fullmatch(content), (
        "mongo_index.js must contain exactly one valid createIndex command for "
        "the transactions collection with the compound key {status: 1, user_id: 1} "
        "(either index direction is accepted)."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

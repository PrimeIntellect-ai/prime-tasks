#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import subprocess
import uuid
from decimal import Decimal

import pytest

SCRIPT_PATH = "/home/user/audit_graph.py"
ACCOUNTS_PATH = "/home/user/accounts.csv"
TRANSACTIONS_PATH = "/home/user/transactions.csv"
OUTPUT_PATH = "/home/user/suspicious_cycle.json"


def derive_expected(accounts_path, transactions_path):
    with open(accounts_path, newline="") as f:
        risks = {row["account_id"]: row["risk_level"] for row in csv.DictReader(f)}

    with open(transactions_path, newline="") as f:
        transactions = list(csv.DictReader(f))

    adjacency = {}
    for tx in transactions:
        adjacency.setdefault(tx["source"], []).append(
            (tx["target"], Decimal(tx["amount"]))
        )

    qualifying = set()
    allowed_risks = {"high_risk", "offshore"}

    def walk(start, current, path, total):
        if len(path) == 4:
            for target, amount in adjacency.get(current, []):
                if target == start and total + amount > Decimal("10000"):
                    accounts = tuple(sorted(path))
                    if all(risks.get(account) in allowed_risks for account in accounts):
                        qualifying.add(accounts)
            return

        for target, amount in adjacency.get(current, []):
            if target not in path:
                walk(start, target, path + [target], total + amount)

    for account in risks:
        walk(account, account, [account], Decimal("0"))

    assert len(qualifying) == 1, (
        f"Verifier fixture must contain exactly one qualifying cycle; found {qualifying}"
    )
    return list(next(iter(qualifying)))


def execute_and_check(expected):
    if os.path.lexists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"{SCRIPT_PATH} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT_PATH), f"Expected output file {OUTPUT_PATH} does not exist."

    try:
        with open(OUTPUT_PATH) as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"File {OUTPUT_PATH} is not a valid JSON file: {exc}")

    assert isinstance(data, list), f"Expected JSON root to be a list, got {type(data).__name__}."
    assert data == expected, f"JSON content is incorrect. Expected {expected}, got {data}."


def test_script_executes_and_analyzes_csv_inputs():
    assert os.path.isfile(SCRIPT_PATH), f"Expected Python script {SCRIPT_PATH} does not exist."

    with open(ACCOUNTS_PATH, "rb") as f:
        original_accounts = f.read()
    with open(TRANSACTIONS_PATH, "rb") as f:
        original_transactions = f.read()

    try:
        original_expected = derive_expected(ACCOUNTS_PATH, TRANSACTIONS_PATH)
        assert original_expected == ["ACC_101", "ACC_102", "ACC_103", "ACC_104"]
        execute_and_check(original_expected)

        token = uuid.uuid4().hex[:10].upper()
        valid = [f"ACC_{token}_{suffix}" for suffix in ("K", "B", "Q", "D")]
        under = [f"ACC_{token}_UNDER_{i}" for i in range(4)]
        low = [f"ACC_{token}_LOW_{i}" for i in range(4)]

        account_rows = []
        for i, account in enumerate(valid):
            account_rows.append((account, "high_risk" if i % 2 == 0 else "offshore"))
        for i, account in enumerate(under):
            account_rows.append((account, "offshore" if i % 2 == 0 else "high_risk"))
        for i, account in enumerate(low):
            account_rows.append((account, "low_risk" if i == 2 else "high_risk"))

        transaction_rows = []
        tx_number = 1
        for accounts, amounts in (
            (valid, [2700, 2600, 2500, 2401]),
            (under, [2000, 2000, 2000, 2000]),
            (low, [5000, 5000, 5000, 5000]),
        ):
            for i in range(4):
                transaction_rows.append(
                    (f"TX_{token}_{tx_number}", accounts[i], accounts[(i + 1) % 4], amounts[i])
                )
                tx_number += 1

        with open(ACCOUNTS_PATH, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["account_id", "risk_level"])
            writer.writerows(account_rows)

        with open(TRANSACTIONS_PATH, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["tx_id", "source", "target", "amount"])
            writer.writerows(transaction_rows)

        synthetic_expected = derive_expected(ACCOUNTS_PATH, TRANSACTIONS_PATH)
        execute_and_check(synthetic_expected)
    finally:
        with open(ACCOUNTS_PATH, "wb") as f:
            f.write(original_accounts)
        with open(TRANSACTIONS_PATH, "wb") as f:
            f.write(original_transactions)

    # Leave the required output in its correct state for the original assertions.
    execute_and_check(derive_expected(ACCOUNTS_PATH, TRANSACTIONS_PATH))


def test_suspicious_cycle_json_exists():
    """Test that the output JSON file exists."""
    file_path = "/home/user/suspicious_cycle.json"
    assert os.path.isfile(file_path), f"Expected output file {file_path} does not exist."


def test_suspicious_cycle_json_content():
    """Test that the output JSON file contains the correct sorted account IDs."""
    file_path = "/home/user/suspicious_cycle.json"

    assert os.path.isfile(file_path), f"Expected output file {file_path} does not exist."

    with open(file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} is not a valid JSON file.")

    expected_data = ["ACC_101", "ACC_102", "ACC_103", "ACC_104"]

    assert isinstance(data, list), f"Expected JSON root to be a list, got {type(data).__name__}."
    assert data == expected_data, f"JSON content is incorrect. Expected {expected_data}, got {data}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

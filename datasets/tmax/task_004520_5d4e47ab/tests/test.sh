#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import secrets
import stat
import subprocess

import pytest

USERS_PATH = "/home/user/users.csv"
TX_PATH = "/home/user/transactions.csv"
PROCESS_PATH = "/home/user/process.go"
OUT_PATH = "/home/user/output.json"
REQUIRED_KEYS = {"user_id", "name", "total_spent", "max_transaction"}


def get_expected_data():
    assert os.path.isfile(USERS_PATH), f"Missing {USERS_PATH}"
    assert os.path.isfile(TX_PATH), f"Missing {TX_PATH}"

    users = {}
    with open(USERS_PATH, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            uid = row["user_id"]
            users[uid] = {
                "user_id": uid,
                "name": row["name"],
                "total_spent": 0.0,
                "max_transaction": 0.0,
            }

    with open(TX_PATH, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            uid = row["user_id"]
            if uid in users:
                amount = float(row["amount"])
                users[uid]["total_spent"] += amount
                if amount > users[uid]["max_transaction"]:
                    users[uid]["max_transaction"] = amount

    return sorted(users.values(), key=lambda x: x["user_id"])


def run_process():
    assert os.path.exists(PROCESS_PATH), f"Missing {PROCESS_PATH}"
    mode = os.stat(PROCESS_PATH).st_mode
    assert stat.S_ISREG(mode), f"{PROCESS_PATH} must be a regular Go source file"

    if os.path.lexists(OUT_PATH):
        os.remove(OUT_PATH)

    result = subprocess.run(
        ["go", "run", PROCESS_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"go run {PROCESS_PATH} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def validate_output(expected_data):
    assert os.path.isfile(OUT_PATH), f"Output file {OUT_PATH} was not created."

    with open(OUT_PATH, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUT_PATH} is not valid JSON.")

    assert isinstance(data, list), (
        f"Expected a JSON array in {OUT_PATH}, but got {type(data).__name__}."
    )
    assert len(data) == len(expected_data), (
        f"Expected {len(expected_data)} items in output JSON, got {len(data)}."
    )

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert isinstance(actual, dict), f"Item at index {i} must be a JSON object"
        assert "user_id" in actual, f"Item at index {i} missing 'user_id'"
        assert "name" in actual, f"Item at index {i} missing 'name'"
        assert "total_spent" in actual, f"Item at index {i} missing 'total_spent'"
        assert "max_transaction" in actual, f"Item at index {i} missing 'max_transaction'"
        assert set(actual.keys()) == REQUIRED_KEYS, (
            f"Item at index {i} must have exactly the keys {sorted(REQUIRED_KEYS)}"
        )

        assert type(actual["user_id"]) is str, "user_id must be a JSON string"
        assert type(actual["name"]) is str, "name must be a JSON string"
        assert type(actual["total_spent"]) in (int, float), (
            "total_spent must be a JSON number, not a string or boolean"
        )
        assert type(actual["max_transaction"]) in (int, float), (
            "max_transaction must be a JSON number, not a string or boolean"
        )
        assert math.isfinite(actual["total_spent"]), "total_spent must be finite"
        assert math.isfinite(actual["max_transaction"]), "max_transaction must be finite"

        assert actual["user_id"] == expected["user_id"], (
            f"Expected user_id '{expected['user_id']}' at index {i}, got "
            f"'{actual['user_id']}'. (Ensure the array is sorted by user_id)"
        )
        assert actual["name"] == expected["name"], (
            f"Expected name '{expected['name']}' for user_id "
            f"'{expected['user_id']}', got '{actual['name']}'"
        )

        actual_total = float(actual["total_spent"])
        expected_total = expected["total_spent"]
        assert math.isclose(actual_total, expected_total, rel_tol=1e-5, abs_tol=1e-2), (
            f"Expected total_spent {expected_total} for user "
            f"{expected['user_id']}, got {actual_total}"
        )

        actual_max = float(actual["max_transaction"])
        expected_max = expected["max_transaction"]
        assert math.isclose(actual_max, expected_max, rel_tol=1e-5, abs_tol=1e-2), (
            f"Expected max_transaction {expected_max} for user "
            f"{expected['user_id']}, got {actual_max}"
        )

        assert math.isclose(actual_total, round(expected_total, 2), abs_tol=1e-7), (
            f"total_spent for {expected['user_id']} is not correct to two decimals"
        )
        assert math.isclose(actual_max, round(expected_max, 2), abs_tol=1e-7), (
            f"max_transaction for {expected['user_id']} is not correct to two decimals"
        )


def write_dynamic_fixtures():
    token = secrets.token_hex(5)
    user_ids = [f"{token}_{suffix}" for suffix in ("20", "03", "11", "01", "99")]
    users = [
        {"user_id": uid, "name": f"name_{secrets.token_hex(3)}"}
        for uid in user_ids
    ]
    random.SystemRandom().shuffle(users)

    active_ids = user_ids[:4]
    transactions = []
    tx_number = 1
    for uid in active_ids:
        for _ in range(2):
            cents = 101 + secrets.randbelow(200000)
            transactions.append({
                "tx_id": f"R{tx_number}_{token}",
                "user_id": uid,
                "amount": f"{cents // 100}.{cents % 100:02d}",
                "date": "2026-01-01",
            })
            tx_number += 1

    for _ in range(5):
        uid = active_ids[secrets.randbelow(len(active_ids))]
        cents = 101 + secrets.randbelow(200000)
        transactions.append({
            "tx_id": f"R{tx_number}_{token}",
            "user_id": uid,
            "amount": f"{cents // 100}.{cents % 100:02d}",
            "date": "2026-01-02",
        })
        tx_number += 1

    random.SystemRandom().shuffle(transactions)

    with open(USERS_PATH, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=["user_id", "name"])
        writer.writeheader()
        writer.writerows(users)

    with open(TX_PATH, "w", encoding="utf-8", newline="") as f:
        writer = csv.DictWriter(
            f, fieldnames=["tx_id", "user_id", "amount", "date"]
        )
        writer.writeheader()
        writer.writerows(transactions)

    expected = {
        row["user_id"]: {
            "user_id": row["user_id"],
            "name": row["name"],
            "total_spent": 0.0,
            "max_transaction": 0.0,
        }
        for row in users
    }
    for tx in transactions:
        amount = float(tx["amount"])
        record = expected[tx["user_id"]]
        record["total_spent"] += amount
        record["max_transaction"] = max(record["max_transaction"], amount)

    for record in expected.values():
        record["total_spent"] = round(record["total_spent"], 2)
        record["max_transaction"] = round(record["max_transaction"], 2)
    return sorted(expected.values(), key=lambda x: x["user_id"])


def test_process_go_generates_correct_output():
    original_users = open(USERS_PATH, "rb").read()
    original_transactions = open(TX_PATH, "rb").read()
    prior_output = open(OUT_PATH, "rb").read() if os.path.isfile(OUT_PATH) else None
    verified_original_output = None

    try:
        expected_original = get_expected_data()
        run_process()
        validate_output(expected_original)
        with open(OUT_PATH, "rb") as f:
            verified_original_output = f.read()

        expected_dynamic = write_dynamic_fixtures()
        run_process()
        validate_output(expected_dynamic)
    finally:
        with open(USERS_PATH, "wb") as f:
            f.write(original_users)
        with open(TX_PATH, "wb") as f:
            f.write(original_transactions)

        output_to_restore = verified_original_output
        if output_to_restore is None:
            output_to_restore = prior_output
        if output_to_restore is None:
            if os.path.lexists(OUT_PATH):
                os.remove(OUT_PATH)
        else:
            with open(OUT_PATH, "wb") as f:
                f.write(output_to_restore)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

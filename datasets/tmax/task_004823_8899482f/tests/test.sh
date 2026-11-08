#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import subprocess

import pytest

REPORT = "/home/user/report.sh"
USERS = "/home/user/users.csv"
PURCHASES = "/home/user/purchases.csv"
SUMMARY = "/home/user/summary.json"


def run_report():
    assert os.path.isfile(REPORT), f"Required script {REPORT} does not exist"
    assert os.access(REPORT, os.X_OK), f"Required script {REPORT} is not executable"
    if os.path.exists(SUMMARY):
        os.remove(SUMMARY)
    result = subprocess.run(
        [REPORT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"{REPORT} failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(SUMMARY), f"Output file {SUMMARY} does not exist. Did you run the script?"
    with open(SUMMARY, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"File {SUMMARY} does not contain valid JSON: {exc}")


def write_csv(path, fieldnames, rows):
    with open(path, "w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fieldnames)
        writer.writeheader()
        writer.writerows(rows)


def assert_exact_output(data, expected):
    assert isinstance(data, list), f"Expected a JSON array, but got {type(data).__name__}"
    assert len(data) == len(expected), f"Expected {len(expected)} records, but got {len(data)}"
    assert data == expected, f"Data in {SUMMARY} does not match expected output.\nExpected: {expected}\nGot: {data}"
    for item in data:
        assert isinstance(item, dict) and set(item) == {"name", "total_spent"}, \
            f"Output objects must contain exactly name and total_spent: {item!r}"
        assert isinstance(item["name"], str), f"name must be a string: {item!r}"
        assert isinstance(item["total_spent"], (int, float)) and not isinstance(item["total_spent"], bool), \
            f"total_spent must be numeric: {item!r}"


def test_report_recomputes_join_filter_and_aggregation():
    with open(USERS, "rb") as f:
        original_users = f.read()
    with open(PURCHASES, "rb") as f:
        original_purchases = f.read()

    try:
        # Preserve the original verifier's exact assertion, but require report.sh
        # itself to generate the output.
        expected_original = [
            {"name": "Alice", "total_spent": 135},
            {"name": "Charlie", "total_spent": 20},
            {"name": "David", "total_spent": 210},
        ]
        assert_exact_output(run_report(), expected_original)

        # Use unpredictable fixture values so a prewritten summary.json or a
        # solution hardcoded to the image's original data cannot pass.
        for _ in range(2):
            token = secrets.token_hex(5)
            ids = [str(secrets.randbelow(800000) + 1000000 + i * 1000000) for i in range(5)]
            amounts = [secrets.randbelow(90) + 1 for _ in range(7)]
            users = [
                {"user_id": ids[0], "name": f"Zulu_{token}", "status": "active"},
                {"user_id": ids[1], "name": f"Beta_{token}", "status": "inactive"},
                {"user_id": ids[2], "name": f"Alpha_{token}", "status": "active"},
                {"user_id": ids[3], "name": f"Mike_{token}", "status": "active"},
                {"user_id": ids[4], "name": f"Gamma_{token}", "status": "inactive"},
            ]
            purchases = [
                {"purchase_id": "p1", "user_id": ids[0], "amount": amounts[0]},
                {"purchase_id": "p2", "user_id": ids[2], "amount": amounts[1]},
                {"purchase_id": "p3", "user_id": ids[1], "amount": amounts[2]},
                {"purchase_id": "p4", "user_id": ids[0], "amount": amounts[3]},
                {"purchase_id": "p5", "user_id": ids[3], "amount": amounts[4]},
                {"purchase_id": "p6", "user_id": ids[4], "amount": amounts[5]},
                {"purchase_id": "p7", "user_id": "999999999", "amount": amounts[6]},
            ]
            write_csv(USERS, ["user_id", "name", "status"], users)
            write_csv(PURCHASES, ["purchase_id", "user_id", "amount"], purchases)

            expected = [
                {"name": f"Alpha_{token}", "total_spent": amounts[1]},
                {"name": f"Mike_{token}", "total_spent": amounts[4]},
                {"name": f"Zulu_{token}", "total_spent": amounts[0] + amounts[3]},
            ]
            assert_exact_output(run_report(), expected)
    finally:
        with open(USERS, "wb") as f:
            f.write(original_users)
        with open(PURCHASES, "wb") as f:
            f.write(original_purchases)
        try:
            subprocess.run([REPORT], cwd="/home/user", timeout=20,
                           stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        except Exception:
            pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

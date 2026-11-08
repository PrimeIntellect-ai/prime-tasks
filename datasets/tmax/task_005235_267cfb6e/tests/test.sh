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

SCRIPT_PATH = "/home/user/process_sales.py"
PRODUCTS_PATH = "/home/user/products.csv"
TRANSACTIONS_PATH = "/home/user/transactions.csv"
OUTPUT_PATH = "/home/user/high_value_active_sales.jsonl"


def run_script():
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"process_sales.py exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def read_jsonl(path):
    with open(path, "r", encoding="utf-8") as f:
        lines = [line for line in f.read().strip().split("\n") if line.strip()]

    parsed = []
    for i, line in enumerate(lines):
        try:
            parsed.append(json.loads(line))
        except json.JSONDecodeError:
            pytest.fail(f"Line {i + 1} is not valid JSON: {line}")
    return lines, parsed


def test_process_sales_script_exists():
    assert os.path.isfile(SCRIPT_PATH), f"Expected script {SCRIPT_PATH} is missing."


def test_script_executes_on_provided_inputs():
    run_script()


def test_output_file_exists():
    assert os.path.isfile(OUTPUT_PATH), f"Expected output file {OUTPUT_PATH} is missing."


def test_output_file_content():
    assert os.path.isfile(OUTPUT_PATH), f"Cannot check content, {OUTPUT_PATH} is missing."

    expected = [
        {"transaction_id": "T1001", "user": "U99", "category": "Electronics", "total_value": 150.0},
        {"transaction_id": "T1004", "user": "U45", "category": "Home", "total_value": 120.5},
        {"transaction_id": "T1006", "user": "U88", "category": "Home", "total_value": 130.0},
    ]

    lines, parsed = read_jsonl(OUTPUT_PATH)
    assert len(lines) == len(expected), f"Expected {len(expected)} lines in the output, but got {len(lines)}."

    for i, (p, e) in enumerate(zip(parsed, expected)):
        assert p == e, f"Mismatch at line {i + 1}:\nExpected: {e}\nGot: {p}"


def test_script_processes_unseen_inputs_and_exact_filter_rules():
    token = secrets.token_hex(8)
    product_rows = [
        [f"{token}-P1", f"Dynamic-{token}-A", "1.00", "true"],
        [f"{token}-P2", f"Dynamic-{token}-B", "2.00", "false"],
        [f"{token}-P3", f"Dynamic-{token}-C", "3.00", "True"],
        [f"{token}-P4", f"Dynamic-{token}-D", "4.00", "true"],
        [f"{token}-P5", f"Dynamic-{token}-E", "5.00", "true "],
    ]
    transaction_rows = [
        [f"{token}-T1", f"{token}-P1", f"{token}-U1", "100.00", "2026-01-01T00:00:00Z"],
        [f"{token}-T2", f"{token}-P1", f"{token}-U2", "100.01", "2026-01-01T00:00:01Z"],
        [f"{token}-T3", f"{token}-P2", f"{token}-U3", "999.50", "2026-01-01T00:00:02Z"],
        [f"{token}-T4", f"{token}-P3", f"{token}-U4", "150.25", "2026-01-01T00:00:03Z"],
        [f"{token}-T5", f"{token}-P4", f"{token}-U5", "275.75", "2026-01-01T00:00:04Z"],
        [f"{token}-T6", f"{token}-UNKNOWN", f"{token}-U6", "800.00", "2026-01-01T00:00:05Z"],
        [f"{token}-T7", f"{token}-P5", f"{token}-U7", "500.00", "2026-01-01T00:00:06Z"],
        [f"{token}-T8", f"{token}-P4", f"{token}-U8", "101.125", "2026-01-01T00:00:07Z"],
    ]

    product_index = {row[0]: {"category": row[1], "is_active": row[3]} for row in product_rows}
    expected = []
    for tx_id, product_id, user_id, amount, _timestamp in transaction_rows:
        product = product_index.get(product_id)
        numeric_amount = float(amount)
        if product is not None and product["is_active"] == "true" and numeric_amount > 100.0:
            expected.append({
                "transaction_id": tx_id,
                "user": user_id,
                "category": product["category"],
                "total_value": numeric_amount,
            })

    products_backup = open(PRODUCTS_PATH, "rb").read()
    transactions_backup = open(TRANSACTIONS_PATH, "rb").read()

    try:
        with open(PRODUCTS_PATH, "w", encoding="utf-8", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["product_id", "category", "price", "is_active"])
            writer.writerows(product_rows)

        with open(TRANSACTIONS_PATH, "w", encoding="utf-8", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["tx_id", "product_id", "user_id", "amount", "timestamp"])
            writer.writerows(transaction_rows)

        if os.path.exists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)
        run_script()

        assert os.path.isfile(OUTPUT_PATH), f"Expected script to create {OUTPUT_PATH}."
        lines, parsed = read_jsonl(OUTPUT_PATH)
        assert len(lines) == len(expected), f"Expected {len(expected)} dynamic output lines, got {len(lines)}."
        assert parsed == expected, f"Dynamic output mismatch.\nExpected: {expected}\nGot: {parsed}"

        for i, record in enumerate(parsed, 1):
            assert set(record) == {"transaction_id", "user", "category", "total_value"}, (
                f"Line {i} has an incorrect schema: {record}"
            )
            assert type(record["transaction_id"]) is str
            assert type(record["user"]) is str
            assert type(record["category"]) is str
            assert type(record["total_value"]) is float
    finally:
        with open(PRODUCTS_PATH, "wb") as f:
            f.write(products_backup)
        with open(TRANSACTIONS_PATH, "wb") as f:
            f.write(transactions_backup)
        subprocess.run(
            ["python3", SCRIPT_PATH],
            cwd="/home/user",
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

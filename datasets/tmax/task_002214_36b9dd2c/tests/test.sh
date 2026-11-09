#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import random
import re
import secrets
import subprocess
import pytest

SCRIPT_PATH = "/home/user/process_products.py"
INPUT_PATH = "/home/user/raw_products.jsonl"
OUTPUT_PATH = "/home/user/cleaned_products.csv"
EXPECTED_HEADER = ["product_id", "price", "category", "discounted", "price_bucket"]


def run_pipeline():
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"process_products.py exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.isfile(OUTPUT_PATH), "The script did not create cleaned_products.csv."


def test_process_products_script_exists_and_runs():
    assert os.path.exists(SCRIPT_PATH), f"Required script {SCRIPT_PATH} is missing."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a file."
    assert os.path.getsize(SCRIPT_PATH) > 0, f"{SCRIPT_PATH} is empty."
    run_pipeline()


def test_cleaned_products_exists():
    path = "/home/user/cleaned_products.csv"
    assert os.path.exists(path), f"Output file {path} is missing."
    assert os.path.isfile(path), f"{path} is not a file."


def test_cleaned_products_content():
    path = "/home/user/cleaned_products.csv"
    assert os.path.exists(path), f"Output file {path} is missing."

    with open(path, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "The CSV file is empty."

    header = rows[0]
    expected_header = ["product_id", "price", "category", "discounted", "price_bucket"]
    assert header == expected_header, f"Expected header {expected_header}, but got {header}."

    # Parse data rows
    data_rows = rows[1:]

    # Expected data
    expected_data = [
        ("A1B2C3D4", 15.5, "electronics", "True", "low"),
        ("C3D4E5F6", 45.0, "other", "False", "medium"),
        ("D4E5F6G7", 120.0, "clothing", "False", "high"),
        ("F6G7H8I9", 20.0, "toys", "False", "medium"),
        ("G7H8I9J0", 19.99, "other", "False", "low"),
        ("H8I9J0K1", 50.0, "home", "True", "high"),
    ]

    assert len(data_rows) == len(expected_data), f"Expected {len(expected_data)} rows, but got {len(data_rows)}."

    for i, (actual, expected) in enumerate(zip(data_rows, expected_data)):
        assert len(actual) == 5, f"Row {i+1} does not have exactly 5 columns."

        # product_id
        assert actual[0] == expected[0], f"Row {i+1}: expected product_id '{expected[0]}', got '{actual[0]}'."

        # price (allow formatting differences like 15.5 vs 15.50)
        try:
            actual_price = float(actual[1])
        except ValueError:
            pytest.fail(f"Row {i+1}: price '{actual[1]}' is not a valid float.")
        assert abs(actual_price - expected[1]) < 1e-5, f"Row {i+1}: expected price {expected[1]}, got {actual_price}."

        # category
        assert actual[2] == expected[2], f"Row {i+1}: expected category '{expected[2]}', got '{actual[2]}'."

        # discounted
        assert actual[3] == expected[3], f"Row {i+1}: expected discounted '{expected[3]}', got '{actual[3]}'."

        # price_bucket
        assert actual[4] == expected[4], f"Row {i+1}: expected price_bucket '{expected[4]}', got '{actual[4]}'."


def test_sorted_order():
    path = "/home/user/cleaned_products.csv"
    assert os.path.exists(path), f"Output file {path} is missing."

    with open(path, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        rows = list(reader)

    if len(rows) <= 1:
        return

    product_ids = [row[0] for row in rows[1:]]
    assert product_ids == sorted(product_ids), "The CSV rows are not sorted by product_id in ascending alphabetical order."


def parse_number(value):
    if isinstance(value, bool) or value is None:
        return None
    if isinstance(value, (int, float)):
        return float(value)
    if isinstance(value, str):
        match = re.search(r"[-+]?(?:\d+(?:\.\d*)?|\.\d+)", value)
        if match:
            return float(match.group(0))
    return None


def derive_expected(records):
    expected = []
    allowed = {"electronics", "clothing", "home", "toys"}
    for record in records:
        product_id = record.get("product_id")
        if not isinstance(product_id, str) or len(product_id) != 8 or not product_id.isascii() or not product_id.isalnum():
            continue
        price = parse_number(record.get("price"))
        if price is None or price <= 0:
            continue
        category = record.get("category")
        if category not in allowed:
            category = "other"
        original = parse_number(record.get("original_price")) if "original_price" in record else None
        discounted = original is not None and original > price
        bucket = "low" if price < 20.0 else ("medium" if price < 50.0 else "high")
        expected.append((product_id, price, category, str(discounted), bucket))
    return sorted(expected, key=lambda row: row[0])


def test_pipeline_on_fresh_unseen_input():
    rng = random.SystemRandom()
    ids = set()
    while len(ids) < 12:
        ids.add(secrets.token_hex(4).upper())
    ids = list(ids)

    low = rng.randint(101, 1999) / 100.0
    medium = rng.randint(2001, 4999) / 100.0
    high = rng.randint(5001, 25000) / 100.0

    records = [
        {"product_id": ids[0], "price": f"${low:.2f}", "category": "electronics", "original_price": low + 7.25},
        {"product_id": ids[1], "price": f"{medium:.2f} USD", "category": "unknown", "original_price": medium},
        {"product_id": ids[2], "price": high, "category": "clothing"},
        {"product_id": ids[3], "price": "20.00", "category": "toys", "original_price": "invalid"},
        {"product_id": ids[4], "price": 50, "category": "home", "original_price": 75},
        {"product_id": ids[5], "price": 11, "original_price": 5},
        {"product_id": ids[6][:7], "price": 30, "category": "toys"},
        {"product_id": ids[7] + "Z", "price": 30, "category": "home"},
        {"product_id": "BAD-ID!!", "price": 30, "category": "home"},
        {"product_id": ids[8], "price": "free", "category": "home"},
        {"product_id": ids[9], "price": 0, "category": "electronics"},
        {"product_id": ids[10], "price": "-4.25", "category": "toys"},
        {"product_id": ids[11], "category": "clothing"},
        {"product_id": 12345678, "price": 25, "category": "home"},
    ]
    rng.shuffle(records)
    expected = derive_expected(records)

    with open(INPUT_PATH, "rb") as f:
        original_input = f.read()
    original_output = None
    if os.path.isfile(OUTPUT_PATH):
        with open(OUTPUT_PATH, "rb") as f:
            original_output = f.read()

    try:
        with open(INPUT_PATH, "w", encoding="utf-8") as f:
            for record in records:
                f.write(json.dumps(record) + "\n")

        run_pipeline()

        with open(OUTPUT_PATH, "r", encoding="utf-8", newline="") as f:
            rows = list(csv.reader(f))

        assert rows, "The CSV produced for fresh input is empty."
        assert rows[0] == EXPECTED_HEADER, f"Expected header {EXPECTED_HEADER}, but got {rows[0]}."
        actual_rows = rows[1:]
        assert len(actual_rows) == len(expected), f"Expected {len(expected)} rows for fresh input, got {len(actual_rows)}."

        for index, (actual, wanted) in enumerate(zip(actual_rows, expected), start=1):
            assert len(actual) == 5, f"Fresh-input row {index} does not have exactly 5 columns."
            assert actual[0] == wanted[0]
            try:
                actual_price = float(actual[1])
            except ValueError:
                pytest.fail(f"Fresh-input row {index} has invalid price {actual[1]!r}.")
            assert abs(actual_price - wanted[1]) < 1e-5
            assert actual[2] == wanted[2]
            assert actual[3] == wanted[3]
            assert actual[4] == wanted[4]
    finally:
        with open(INPUT_PATH, "wb") as f:
            f.write(original_input)
        if original_output is None:
            if os.path.exists(OUTPUT_PATH):
                os.remove(OUTPUT_PATH)
        else:
            with open(OUTPUT_PATH, "wb") as f:
                f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

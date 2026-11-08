#!/bin/bash
mkdir -p /logs/verifier
reward=0
trap 'printf "%s\n" "$reward" > /logs/verifier/reward.txt' EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import os
import secrets
import subprocess
from collections import Counter, defaultdict
from decimal import Decimal
from pathlib import Path

import pytest

SCRIPT_PATH = Path("/home/user/etl_pipeline.py")
OUTPUT_PATH = Path("/home/user/user_spend.jsonl")
USERS_PATH = Path("/home/user/data/users.jsonl")
ORDERS_PATH = Path("/home/user/data/orders.jsonl")


def run_pipeline():
    assert SCRIPT_PATH.is_file(), f"Pipeline script {SCRIPT_PATH} does not exist."
    if OUTPUT_PATH.exists():
        OUTPUT_PATH.unlink()
    result = subprocess.run(
        ["python3", str(SCRIPT_PATH)],
        cwd="/home/user",
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"Pipeline exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


@pytest.fixture(scope="session", autouse=True)
def execute_submission():
    run_pipeline()


def read_output():
    assert OUTPUT_PATH.is_file(), (
        f"Output file {OUTPUT_PATH} does not exist. Did the script run successfully?"
    )
    with OUTPUT_PATH.open("r") as f:
        lines = [line.strip() for line in f if line.strip()]

    parsed_lines = []
    for i, line in enumerate(lines):
        try:
            parsed_lines.append(json.loads(line))
        except json.JSONDecodeError:
            assert False, f"Line {i + 1} is not valid JSON: {line}"
    return lines, parsed_lines


def test_output_file_exists():
    assert OUTPUT_PATH.is_file(), (
        f"Output file {OUTPUT_PATH} does not exist. Did the script run successfully?"
    )


def test_output_file_content_and_schema():
    lines, parsed_lines = read_output()
    assert len(lines) == 3, (
        f"Expected exactly 3 lines in the output file, but got {len(lines)}."
    )

    user_ids = [row.get("user_id") for row in parsed_lines]
    assert user_ids == sorted(user_ids), (
        "The output file is not sorted alphabetically by user_id."
    )

    expected_data = {
        "u1": {
            "email": "alice@example.com",
            "total_spent": 1231.5,
            "order_count": 2,
            "top_category": "electronics",
        },
        "u2": {
            "email": "bob@example.com",
            "total_spent": 75.0,
            "order_count": 1,
            "top_category": "electronics",
        },
        "u3": {
            "email": "charlie@example.com",
            "total_spent": 400.0,
            "order_count": 2,
            "top_category": "furniture",
        },
    }

    assert len(user_ids) == len(set(user_ids)), "Duplicate user_id rows found."
    assert set(user_ids) == set(expected_data), (
        "Output must contain exactly one row for every expected user."
    )

    for row in parsed_lines:
        uid = row.get("user_id")
        assert uid in expected_data, f"Unexpected user_id found: {uid}"

        expected = expected_data[uid]
        assert row.get("email") == expected["email"], f"Incorrect email for user {uid}"
        assert row.get("order_count") == expected["order_count"], (
            f"Incorrect order_count for user {uid}"
        )
        assert row.get("top_category") == expected["top_category"], (
            f"Incorrect top_category for user {uid}"
        )

        actual_spent = row.get("total_spent")
        assert isinstance(actual_spent, (int, float)), (
            f"total_spent for user {uid} must be a number"
        )
        assert math.isclose(
            actual_spent, expected["total_spent"], rel_tol=1e-5
        ), (
            f"Incorrect total_spent for user {uid}: expected "
            f"{expected['total_spent']}, got {actual_spent}"
        )


def flatten_items(value):
    for item in value:
        if isinstance(item, list):
            yield from flatten_items(item)
        else:
            yield item


def derive_expected(users, orders):
    user_map = {user["_id"]: user for user in users}
    totals = defaultdict(Decimal)
    order_ids = defaultdict(set)
    categories = defaultdict(Counter)

    for order in orders:
        uid = order["u_id"]
        assert uid in user_map
        order_ids[uid].add(order["order_id"])
        for item in flatten_items(order["items"]):
            if "price_cents" in item:
                price = Decimal(str(item["price_cents"])) / Decimal("100")
            elif "price" in item:
                price = Decimal(str(item["price"]))
            else:
                price = Decimal(item["cost"].replace("$", ""))
            totals[uid] += price
            categories[uid][item["category"]] += 1

    expected = {}
    for uid in order_ids:
        max_count = max(categories[uid].values())
        top_category = min(
            category
            for category, count in categories[uid].items()
            if count == max_count
        )
        expected[uid] = {
            "email": user_map[uid]["email"],
            "total_spent": float(totals[uid].quantize(Decimal("0.01"))),
            "order_count": len(order_ids[uid]),
            "top_category": top_category,
        }
    return expected


def write_jsonl(path, documents):
    path.write_text("".join(json.dumps(doc) + "\n" for doc in documents))


def test_pipeline_uses_input_data():
    token = secrets.token_hex(6)
    amount = secrets.randbelow(700) + 101
    user_ids = [f"a-{token}", f"m-{token}", f"z-{token}"]
    users = [
        {"_id": user_ids[0], "email": f"alpha-{token}@example.com", "name": "Alpha"},
        {"_id": user_ids[1], "email": f"middle-{token}@example.com", "name": "Middle"},
        {"_id": user_ids[2], "email": f"zeta-{token}@example.com", "name": "Zeta"},
    ]
    orders = [
        {
            "order_id": f"one-{token}",
            "u_id": user_ids[0],
            "items": [
                {"name": "A", "category": "electronics", "price": (amount + 1000) / 100},
                {"name": "B", "category": "electronics", "price_cents": amount + 200},
            ],
        },
        {
            "order_id": f"two-{token}",
            "u_id": user_ids[0],
            "items": [[
                {"name": "C", "category": "office", "cost": f"${(amount + 300) / 100:.2f}"},
                {"name": "D", "category": "office", "cost": f"${(amount + 400) / 100:.2f}"},
            ]],
        },
        {
            "order_id": f"three-{token}",
            "u_id": user_ids[1],
            "items": [
                {"name": "E", "category": "electronics", "price_cents": amount + 500}
            ],
        },
        {
            "order_id": f"four-{token}",
            "u_id": user_ids[2],
            "items": [
                {"name": "F", "category": "furniture", "price": (amount + 600) / 100},
                {"name": "G", "category": "furniture", "price": (amount + 700) / 100},
            ],
        },
        {
            "order_id": f"five-{token}",
            "u_id": user_ids[2],
            "items": [
                {"name": "H", "category": "furniture", "price_cents": amount + 800},
                {"name": "I", "category": "electronics", "cost": f"${(amount + 900) / 100:.2f}"},
            ],
        },
    ]
    expected = derive_expected(users, orders)

    original_users = USERS_PATH.read_bytes()
    original_orders = ORDERS_PATH.read_bytes()
    canonical_output = OUTPUT_PATH.read_bytes()
    try:
        write_jsonl(USERS_PATH, users)
        write_jsonl(ORDERS_PATH, orders)
        run_pipeline()
        lines, rows = read_output()

        assert len(lines) == len(expected)
        actual_ids = [row.get("user_id") for row in rows]
        assert actual_ids == sorted(actual_ids), (
            "The output file is not sorted alphabetically by user_id."
        )
        assert len(actual_ids) == len(set(actual_ids)), "Duplicate user_id rows found."
        assert set(actual_ids) == set(expected), (
            "Output must contain exactly one row for every input user with orders."
        )

        for row in rows:
            uid = row.get("user_id")
            wanted = expected[uid]
            assert row.get("email") == wanted["email"]
            assert row.get("order_count") == wanted["order_count"]
            assert row.get("top_category") == wanted["top_category"]
            actual_spent = row.get("total_spent")
            assert isinstance(actual_spent, (int, float))
            assert math.isclose(actual_spent, wanted["total_spent"], rel_tol=1e-5)
    finally:
        USERS_PATH.write_bytes(original_users)
        ORDERS_PATH.write_bytes(original_orders)
        OUTPUT_PATH.write_bytes(canonical_output)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    reward=1
fi

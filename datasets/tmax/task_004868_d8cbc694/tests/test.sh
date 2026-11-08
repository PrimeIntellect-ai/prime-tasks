#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import pwd
import shutil
import subprocess
import time
import pytest

EXECUTABLE = "/home/user/join_to_json"
SOURCE = "/home/user/join_to_json.cpp"
OUTPUT = "/home/user/result.json"
USERS = "/app/users.csv"
ORDERS = "/app/orders.csv"
ITEMS = "/app/items.csv"


def run_as_user(executable, timeout):
    account = pwd.getpwnam("user")

    def demote():
        os.setgroups([])
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    return subprocess.run(
        [executable], capture_output=True, timeout=timeout, preexec_fn=demote
    )


def lock_inputs():
    for path in (USERS, ORDERS, ITEMS):
        os.chmod(path, 0o444)
    os.chmod("/app", 0o555)


def unlock_inputs():
    os.chmod("/app", 0o777)
    for path in (USERS, ORDERS, ITEMS):
        os.chmod(path, 0o777)


def row_count(path):
    with open(path, "r", encoding="utf-8", newline="") as f:
        return sum(1 for _ in csv.reader(f)) - 1


def load_json_output():
    assert os.path.exists(OUTPUT), f"Output JSON file {OUTPUT} was not created."
    with open(OUTPUT, "r", encoding="utf-8") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Output in {OUTPUT} is not valid JSON: {e}")


def validate_against_csv(data, users_path, orders_path, items_path):
    users = {}
    with open(users_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["user_id", "user_name"]
        for row in reader:
            uid = row["user_id"]
            assert uid not in users, f"Duplicate user_id in test input: {uid}"
            users[uid] = row["user_name"]

    orders = {}
    with open(orders_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["order_id", "user_id", "order_date"]
        for row in reader:
            oid = row["order_id"]
            assert oid not in orders, f"Duplicate order_id in test input: {oid}"
            assert row["user_id"] in users, f"Order {oid} references an unknown user"
            orders[oid] = (row["user_id"], row["order_date"])

    expected_items = {}
    eligible_orders = set()
    with open(items_path, newline="", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["item_id", "order_id", "item_name", "price"]
        for row in reader:
            iid = row["item_id"]
            oid = row["order_id"]
            assert iid not in expected_items, f"Duplicate item_id in test input: {iid}"
            assert oid in orders, f"Item {iid} references an unknown order"
            expected_items[iid] = (oid, row["item_name"], row["price"])
            eligible_orders.add(oid)

    expected_users = {orders[oid][0] for oid in eligible_orders}
    assert isinstance(data, list), "Root of the output JSON must be an array."
    assert len(data) == len(expected_users), "Output has missing or extra users."

    seen_users = set()
    seen_orders = set()
    for user in data:
        assert isinstance(user, dict), "Each user entry must be an object."
        assert "user_id" in user, "User object is missing 'user_id' key."
        assert "user_name" in user, "User object is missing 'user_name' key."
        assert "orders" in user, "User object is missing 'orders' key."
        assert isinstance(user["orders"], list), "'orders' value must be an array."
        uid = user["user_id"]
        assert isinstance(uid, str), "user_id must be a JSON string."
        assert uid in expected_users, f"Unexpected user {uid} in output."
        assert uid not in seen_users, f"User {uid} appears more than once."
        assert user["user_name"] == users[uid], f"Wrong user_name for user {uid}."
        assert len(user["orders"]) > 0, f"User {uid} has no orders, but should have been skipped."
        seen_users.add(uid)

        for order in user["orders"]:
            assert isinstance(order, dict), "Each order entry must be an object."
            assert "order_id" in order, "Order object is missing 'order_id' key."
            assert "order_date" in order, "Order object is missing 'order_date' key."
            assert "items" in order, "Order object is missing 'items' key."
            assert isinstance(order["items"], list), "'items' value must be an array."
            oid = order["order_id"]
            assert isinstance(oid, str), "order_id must be a JSON string."
            assert oid in eligible_orders, f"Unexpected or itemless order {oid} in output."
            assert oid not in seen_orders, f"Order {oid} appears more than once."
            assert orders[oid][0] == uid, f"Order {oid} is attached to the wrong user."
            assert order["order_date"] == orders[oid][1], f"Wrong order_date for order {oid}."
            assert len(order["items"]) > 0, f"Order {oid} has no items, but should have been skipped."
            seen_orders.add(oid)

            for item in order["items"]:
                assert isinstance(item, dict), "Each item entry must be an object."
                for key in ("item_id", "item_name", "price"):
                    assert key in item, f"Item object is missing '{key}' key."
                iid = item["item_id"]
                assert isinstance(iid, str), "item_id must be a JSON string."
                assert iid in expected_items, f"Unexpected or duplicate item {iid}."
                expected_oid, expected_name, expected_price = expected_items.pop(iid)
                assert expected_oid == oid, f"Item {iid} is attached to the wrong order."
                assert item["item_name"] == expected_name, f"Wrong item_name for item {iid}."
                assert item["price"] == expected_price, f"Wrong price for item {iid}."

    assert seen_users == expected_users, "Output has missing users."
    assert seen_orders == eligible_orders, "Output has missing orders or includes itemless orders."
    assert not expected_items, "Output has missing items."


def test_executable_exists():
    assert os.path.exists(EXECUTABLE), f"Executable {EXECUTABLE} does not exist. Did you compile the C++ program?"
    assert os.access(EXECUTABLE, os.X_OK), f"File {EXECUTABLE} is not executable."
    assert os.path.isfile(SOURCE), f"C++ source file {SOURCE} does not exist."
    assert os.path.getsize(SOURCE) > 0, f"C++ source file {SOURCE} is empty."
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "join_to_json must be a compiled executable."


def test_execution_time_and_output():
    lock_inputs()
    assert row_count(USERS) == 50000, "users.csv was modified or truncated."
    assert row_count(ORDERS) == 150000, "orders.csv was modified or truncated."
    assert row_count(ITEMS) == 500000, "items.csv was modified or truncated."

    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)

    start_time = time.time()
    try:
        result = run_as_user(EXECUTABLE, 10)
    except subprocess.TimeoutExpired:
        pytest.fail("Execution timed out after 10 seconds. The program is far too slow.")
    end_time = time.time()

    assert result.returncode == 0, f"Executable failed with return code {result.returncode}. Stderr: {result.stderr.decode('utf-8', errors='replace')}"
    execution_time = end_time - start_time
    assert execution_time <= 1.5, f"Execution time {execution_time:.3f}s exceeded threshold of 1.5s. Your indexing strategy might be inefficient."

    data = load_json_output()
    assert isinstance(data, list), "Root of the output JSON must be an array."

    # Preserve the original structural assertions.
    if len(data) > 0:
        first_user = data[0]
        assert "user_id" in first_user, "User object is missing 'user_id' key."
        assert "orders" in first_user, "User object is missing 'orders' key."
        assert isinstance(first_user["orders"], list), "'orders' value must be an array."
        for user in data:
            assert len(user.get("orders", [])) > 0, f"User {user.get('user_id')} has no orders, but should have been skipped."
            for order in user["orders"]:
                assert len(order.get("items", [])) > 0, f"Order {order.get('order_id')} has no items, but should have been skipped."
        if len(first_user["orders"]) > 0:
            first_order = first_user["orders"][0]
            assert "order_id" in first_order, "Order object is missing 'order_id' key."
            assert "items" in first_order, "Order object is missing 'items' key."
            assert isinstance(first_order["items"], list), "'items' value must be an array."
            if len(first_order["items"]) > 0:
                first_item = first_order["items"][0]
                assert "item_id" in first_item, "Item object is missing 'item_id' key."

    validate_against_csv(data, USERS, ORDERS, ITEMS)


def test_controlled_join_fixture():
    backups = {}
    unlock_inputs()
    try:
        for path in (USERS, ORDERS, ITEMS):
            backup = "/tmp/original_" + os.path.basename(path)
            shutil.copy2(path, backup)
            backups[path] = backup

        fixtures = {
            USERS: [
                ["user_id", "user_name"],
                ["u3", "Carol"],
                ["u1", "Alice, A."],
                ["u4", "No Orders"],
                ["u2", "Bob \"B\""],
            ],
            ORDERS: [
                ["order_id", "user_id", "order_date"],
                ["o20", "u2", "2024-02-02"],
                ["o11", "u1", "2024-01-11"],
                ["o30", "u3", "2024-03-03"],
                ["o10", "u1", "2024-01-10"],
            ],
            ITEMS: [
                ["item_id", "order_id", "item_name", "price"],
                ["i4", "o30", "Fourth", "0.99"],
                ["i2", "o10", "Comma, Item", "10.50"],
                ["i5", "o30", "Fifth", "12.00"],
                ["i1", "o10", "First", "1.25"],
                ["i3", "o20", "Quoted \"item\"", "7.00"],
            ],
        }
        for path, rows in fixtures.items():
            with open(path, "w", newline="", encoding="utf-8") as f:
                csv.writer(f).writerows(rows)

        lock_inputs()
        if os.path.exists(OUTPUT):
            os.remove(OUTPUT)
        try:
            result = run_as_user(EXECUTABLE, 10)
        except subprocess.TimeoutExpired:
            pytest.fail("Execution timed out on the controlled join fixture.")
        assert result.returncode == 0, f"Executable failed on controlled input. Stderr: {result.stderr.decode('utf-8', errors='replace')}"
        data = load_json_output()
        validate_against_csv(data, USERS, ORDERS, ITEMS)
    finally:
        unlock_inputs()
        for path, backup in backups.items():
            if os.path.exists(backup):
                shutil.copy2(backup, path)
        unlock_inputs()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

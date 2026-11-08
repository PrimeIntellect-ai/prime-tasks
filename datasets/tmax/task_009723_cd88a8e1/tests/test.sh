#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import json
import os
import py_compile
import secrets
import stat
import subprocess
import sys

import pytest

SCRIPT = "/home/user/aggregate.py"
REPORT = "/home/user/report.json"
SCHEMA = "/home/user/schema.json"
DATA_FILES = [
    "/home/user/data/users.jsonl",
    "/home/user/data/products.jsonl",
    "/home/user/data/orders.jsonl",
]
EXPECTED_KEYS = {
    "user_id", "name", "email", "total_spent", "electronics_purchased"
}


def get_expected_report():
    """Derive the expected report directly from the source JSONL files."""
    users_file = "/home/user/data/users.jsonl"
    products_file = "/home/user/data/products.jsonl"
    orders_file = "/home/user/data/orders.jsonl"

    users = {}
    with open(users_file, "r") as f:
        for line in f:
            if not line.strip(): continue
            u = json.loads(line)
            users[u["_id"]] = {
                "user_id": u["_id"],
                "name": u["profile"]["name"],
                "email": u["profile"]["email"],
                "total_spent": 0.0,
                "electronics_purchased": set(),
                "has_electronics": False
            }

    products = {}
    with open(products_file, "r") as f:
        for line in f:
            if not line.strip(): continue
            p = json.loads(line)
            products[p["prod_id"]] = p

    with open(orders_file, "r") as f:
        for line in f:
            if not line.strip(): continue
            o = json.loads(line)
            if o.get("status") != "completed":
                continue

            uid = o["u_id"]
            if uid not in users:
                continue

            for item in o.get("items", []):
                pid = item["p_id"]
                qty = item["qty"]
                if pid not in products:
                    continue

                prod = products[pid]
                users[uid]["total_spent"] += prod["details"]["price"] * qty

                if prod["details"]["category"] == "Electronics":
                    users[uid]["has_electronics"] = True
                    users[uid]["electronics_purchased"].add(prod["name"])

    report = []
    for uid, udata in users.items():
        if udata["has_electronics"]:
            report.append({
                "user_id": udata["user_id"],
                "name": udata["name"],
                "email": udata["email"],
                "total_spent": float(udata["total_spent"]),
                "electronics_purchased": sorted(list(udata["electronics_purchased"]))
            })

    # Sort by total_spent descending, then name ascending
    report.sort(key=lambda x: (-x["total_spent"], x["name"]))
    return report


def validate_against_schema(value, schema, path="$"):
    """Validate the draft-07 features used by the supplied schema."""
    expected_type = schema.get("type")
    if expected_type == "array":
        assert isinstance(value, list), f"{path} must be an array"
    elif expected_type == "object":
        assert isinstance(value, dict), f"{path} must be an object"
    elif expected_type == "string":
        assert isinstance(value, str), f"{path} must be a string"
    elif expected_type == "number":
        assert isinstance(value, (int, float)) and not isinstance(value, bool), \
            f"{path} must be a number"

    if expected_type == "array" and "items" in schema:
        for i, item in enumerate(value):
            validate_against_schema(item, schema["items"], f"{path}[{i}]")

    if expected_type == "object":
        properties = schema.get("properties", {})
        for required in schema.get("required", []):
            assert required in value, f"{path} is missing required property {required}"
        if schema.get("additionalProperties") is False:
            extras = set(value) - set(properties)
            assert not extras, f"{path} has additional properties: {sorted(extras)}"
        for key, item in value.items():
            if key in properties:
                validate_against_schema(item, properties[key], f"{path}.{key}")

    if expected_type == "string" and schema.get("format") == "email":
        assert "@" in value and value.split("@", 1)[0] and value.split("@", 1)[1], \
            f"{path} is not a valid email address"


def run_submission():
    if os.path.lexists(REPORT):
        os.remove(REPORT)
    before = {path: open(path, "rb").read() for path in DATA_FILES}
    result = subprocess.run(
        [sys.executable, SCRIPT],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, \
        f"aggregate.py exited with {result.returncode}: {result.stderr}"
    assert os.path.isfile(REPORT), "aggregate.py did not generate /home/user/report.json"
    after = {path: open(path, "rb").read() for path in DATA_FILES}
    assert after == before, "aggregate.py must not modify the source JSONL files"


@pytest.fixture(scope="session", autouse=True)
def execute_aggregate_script():
    assert os.path.exists(SCRIPT), "The file /home/user/aggregate.py does not exist."
    assert not os.path.islink(SCRIPT), "/home/user/aggregate.py must be a regular Python file."
    assert stat.S_ISREG(os.stat(SCRIPT).st_mode), "/home/user/aggregate.py must be a regular file."
    py_compile.compile(SCRIPT, doraise=True)
    run_submission()


def test_report_exists():
    """Check if the report.json file exists."""
    assert os.path.isfile("/home/user/report.json"), "The file /home/user/report.json does not exist."


def test_report_valid_json():
    """Check if the report.json file contains valid JSON."""
    with open("/home/user/report.json", "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("/home/user/report.json is not valid JSON.")
    assert isinstance(data, list), "The root of /home/user/report.json must be a JSON array."


def test_report_content_and_ordering():
    """Validate that the report matches the expected derived state and ordering."""
    expected = get_expected_report()

    with open("/home/user/report.json", "r") as f:
        actual = json.load(f)

    assert len(actual) == len(expected), f"Expected {len(expected)} users in report, got {len(actual)}."

    for i, (exp, act) in enumerate(zip(expected, actual)):
        assert act.get("user_id") == exp["user_id"], f"Mismatch in user_id at index {i}. Expected {exp['user_id']}, got {act.get('user_id')}."
        assert act.get("name") == exp["name"], f"Mismatch in name at index {i}. Expected {exp['name']}, got {act.get('name')}."
        assert act.get("email") == exp["email"], f"Mismatch in email at index {i}. Expected {exp['email']}, got {act.get('email')}."

        actual_spent = act.get("total_spent")
        assert actual_spent is not None, f"Missing total_spent at index {i}."
        assert isinstance(actual_spent, (int, float)), f"total_spent at index {i} must be a number."
        assert abs(actual_spent - exp["total_spent"]) < 1e-5, f"Mismatch in total_spent at index {i}. Expected {exp['total_spent']}, got {actual_spent}."

        actual_electronics = act.get("electronics_purchased")
        assert actual_electronics is not None, f"Missing electronics_purchased at index {i}."
        assert isinstance(actual_electronics, list), f"electronics_purchased at index {i} must be an array."
        assert actual_electronics == exp["electronics_purchased"], f"Mismatch in electronics_purchased at index {i}. Expected {exp['electronics_purchased']}, got {actual_electronics}."


def test_report_strictly_matches_schema():
    with open(SCHEMA, "r") as f:
        schema = json.load(f)
    with open(REPORT, "r") as f:
        actual = json.load(f)
    validate_against_schema(actual, schema)
    for i, item in enumerate(actual):
        assert set(item) == EXPECTED_KEYS, \
            f"Report item {i} must contain exactly {sorted(EXPECTED_KEYS)}"


def test_aggregate_extracts_from_changed_inputs():
    backups = {path: open(path, "rb").read() for path in DATA_FILES}
    token = secrets.token_hex(8)
    base = secrets.randbelow(150) + 100
    home_price = secrets.randbelow(40) + 10
    second_price = secrets.randbelow(80) + 20
    tied_total = base * 2 + home_price + second_price

    users = [
        {"_id": f"ua-{token}", "profile": {"name": f"Ava-{token}", "email": f"ava-{token}@example.test"}},
        {"_id": f"ub-{token}", "profile": {"name": f"Zoe-{token}", "email": f"zoe-{token}@example.test"}},
        {"_id": f"uc-{token}", "profile": {"name": f"Home-{token}", "email": f"home-{token}@example.test"}},
        {"_id": f"ud-{token}", "profile": {"name": f"Canceled-{token}", "email": f"cancel-{token}@example.test"}},
    ]
    products = [
        {"prod_id": f"pe1-{token}", "details": {"category": "Electronics", "price": base}, "name": f"Camera-{token}"},
        {"prod_id": f"pe2-{token}", "details": {"category": "Electronics", "price": second_price}, "name": f"Adapter-{token}"},
        {"prod_id": f"ph-{token}", "details": {"category": "Home", "price": home_price}, "name": f"Desk-{token}"},
        {"prod_id": f"pt-{token}", "details": {"category": "Electronics", "price": tied_total}, "name": f"Console-{token}"},
    ]
    orders = [
        {"order_id": f"o1-{token}", "u_id": f"ua-{token}", "status": "completed", "items": [{"p_id": f"pe1-{token}", "qty": 2}, {"p_id": f"ph-{token}", "qty": 1}]},
        {"order_id": f"o2-{token}", "u_id": f"ua-{token}", "status": "completed", "items": [{"p_id": f"pe2-{token}", "qty": 1}, {"p_id": f"pe1-{token}", "qty": 0}]},
        {"order_id": f"o3-{token}", "u_id": f"ua-{token}", "status": "canceled", "items": [{"p_id": f"pt-{token}", "qty": 9}]},
        {"order_id": f"o4-{token}", "u_id": f"ub-{token}", "status": "completed", "items": [{"p_id": f"pt-{token}", "qty": 1}]},
        {"order_id": f"o5-{token}", "u_id": f"uc-{token}", "status": "completed", "items": [{"p_id": f"ph-{token}", "qty": 3}]},
        {"order_id": f"o6-{token}", "u_id": f"ud-{token}", "status": "canceled", "items": [{"p_id": f"pe1-{token}", "qty": 1}]},
    ]

    try:
        for path, rows in zip(DATA_FILES, [users, products, orders]):
            with open(path, "w") as f:
                for row in rows:
                    f.write(json.dumps(row) + "\n")

        expected = get_expected_report()
        run_submission()
        with open(REPORT, "r") as f:
            actual = json.load(f)
        assert actual == expected, "aggregate.py did not derive the report from changed JSONL inputs"

        with open(SCHEMA, "r") as f:
            schema = json.load(f)
        validate_against_schema(actual, schema)
        for i, item in enumerate(actual):
            assert set(item) == EXPECTED_KEYS, \
                f"Dynamic report item {i} contains missing or additional properties"
    finally:
        for path, content in backups.items():
            with open(path, "wb") as f:
                f.write(content)
        run_submission()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

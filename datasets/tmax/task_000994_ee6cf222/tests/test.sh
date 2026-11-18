#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import datetime
import json
import math
import os
import pytest


def test_customers_export_jsonl():
    export_path = "/home/user/customers_export.jsonl"
    assert os.path.isfile(export_path), f"Missing output file: {export_path}"

    reference_scores = {
        1: 221.075,
        2: 307.25,
        3: 41.0
    }

    with open("/home/user/data/customers.csv", newline="") as f:
        customer_ids = [int(row["customer_id"]) for row in csv.DictReader(f)]

    orders_by_customer = {cid: [] for cid in customer_ids}
    with open("/home/user/data/orders.csv", newline="") as f:
        for row in csv.DictReader(f):
            cid = int(row["customer_id"])
            orders_by_customer.setdefault(cid, []).append(row)

    reference_date = datetime.date(2023, 12, 31)
    expected_aggregates = {}
    for cid in customer_ids:
        orders = orders_by_customer[cid]
        assert orders, f"Test data has no orders for customer_id {cid}"
        last_order = max(datetime.date.fromisoformat(row["order_date"]) for row in orders)
        expected_aggregates[cid] = {
            "total_spent": sum(float(row["total_amount"]) for row in orders),
            "order_count": len(orders),
            "days_since_last_order": (reference_date - last_order).days,
        }

    actual_scores = {}
    seen_ids = set()
    object_count = 0
    with open(export_path, "r") as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            object_count += 1
            try:
                data = json.loads(line)
            except json.JSONDecodeError:
                pytest.fail(f"Invalid JSON on line {line_num}: {line}")

            assert isinstance(data, dict), f"JSON value on line {line_num} is not an object"
            for field in (
                "_id",
                "total_spent",
                "order_count",
                "days_since_last_order",
                "customer_value_score",
            ):
                assert field in data, f"Missing '{field}' in JSON object on line {line_num}"

            assert type(data["_id"]) is int, f"'_id' must be an integer on line {line_num}"
            assert type(data["total_spent"]) is float, f"'total_spent' must be a float on line {line_num}"
            assert type(data["order_count"]) is int, f"'order_count' must be an integer on line {line_num}"
            assert type(data["days_since_last_order"]) is int, f"'days_since_last_order' must be an integer on line {line_num}"
            assert type(data["customer_value_score"]) is float, f"'customer_value_score' must be a float on line {line_num}"
            assert math.isfinite(data["total_spent"]), f"Non-finite total_spent on line {line_num}"
            assert math.isfinite(data["customer_value_score"]), f"Non-finite customer_value_score on line {line_num}"

            customer_id = data["_id"]
            assert customer_id in expected_aggregates, f"Unexpected customer_id {customer_id} in output"
            assert customer_id not in seen_ids, f"Duplicate customer_id {customer_id} in output"
            seen_ids.add(customer_id)

            expected = expected_aggregates[customer_id]
            assert data["total_spent"] == pytest.approx(expected["total_spent"], abs=1e-9), \
                f"Incorrect total_spent for customer_id {customer_id}"
            assert data["order_count"] == expected["order_count"], \
                f"Incorrect order_count for customer_id {customer_id}"
            assert data["days_since_last_order"] == expected["days_since_last_order"], \
                f"Incorrect days_since_last_order for customer_id {customer_id}"

            score = data["customer_value_score"]
            actual_scores[customer_id] = score

    assert object_count == len(reference_scores), f"Expected {len(reference_scores)} JSON objects, but found {object_count}"
    assert len(actual_scores) == len(reference_scores), f"Expected {len(reference_scores)} customers, but found {len(actual_scores)}"

    mse = 0.0
    for cid, ref_score in reference_scores.items():
        assert cid in actual_scores, f"Missing customer_id {cid} in output"
        actual_score = actual_scores[cid]
        mse += (actual_score - ref_score) ** 2

    mse /= len(reference_scores)

    threshold = 0.1
    assert mse <= threshold, f"MSE of customer_value_score is {mse}, which is greater than the threshold {threshold}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

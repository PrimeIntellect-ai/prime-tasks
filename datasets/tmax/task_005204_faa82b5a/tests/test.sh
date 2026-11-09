#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import time
import json
import sqlite3
import subprocess
from collections import defaultdict
import pytest


def test_pypika_installed():
    try:
        import pypika
    except ImportError:
        pytest.fail("pypika is not installed or cannot be imported. Did you fix and install /app/pypika?")


def test_report_generator_fixed():
    script_path = "/home/user/report_generator.py"
    assert os.path.exists(script_path), f"Script {script_path} is missing."
    with open(script_path, "r") as f:
        content = f.read()
    assert "cross_join" not in content, "The script still contains 'cross_join' instead of a proper join."
    assert "join" in content.lower(), "The script does not seem to contain a 'join' method call."


def test_db_indices_created():
    db_path = "/home/user/ecommerce.db"
    assert os.path.exists(db_path), f"Database {db_path} is missing."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT name, tbl_name FROM sqlite_master WHERE type='index';")
    indices = cursor.fetchall()
    conn.close()

    indexed_tables = {row[1] for row in indices}
    assert "orders" in indexed_tables, "Missing index on the 'orders' table to optimize the query."
    assert "order_items" in indexed_tables, "Missing index on the 'order_items' table to optimize the query."


def expected_report(db_path):
    conn = sqlite3.connect(db_path)
    try:
        rows = conn.execute("""
            WITH order_totals AS (
                SELECT o.customer_id AS customer_id,
                       o.id AS order_id,
                       SUM(oi.price) AS total
                FROM orders AS o
                INNER JOIN order_items AS oi ON oi.order_id = o.id
                GROUP BY o.customer_id, o.id
            ), ranked AS (
                SELECT customer_id, order_id, total,
                       ROW_NUMBER() OVER (
                           PARTITION BY customer_id
                           ORDER BY total DESC, order_id ASC
                       ) AS rn
                FROM order_totals
            )
            SELECT customer_id, order_id, total
            FROM ranked
            WHERE rn <= 3
            ORDER BY customer_id, rn
        """).fetchall()
    finally:
        conn.close()

    result = defaultdict(list)
    for customer_id, order_id, total in rows:
        result[int(customer_id)].append((int(order_id), float(total)))
    return dict(result)


def numeric_id(value):
    if isinstance(value, bool):
        raise ValueError("boolean is not an ID")
    if isinstance(value, int):
        return value
    if isinstance(value, float) and value.is_integer():
        return int(value)
    if isinstance(value, str):
        text = value.strip()
        if re.fullmatch(r"[+-]?\d+", text):
            return int(text)
        match = re.fullmatch(r"Customer\s+([0-9]+)", text, re.IGNORECASE)
        if match:
            return int(match.group(1))
    raise ValueError(f"invalid numeric ID: {value!r}")


def order_entry(value):
    if isinstance(value, dict):
        if "order_id" in value:
            order_id = numeric_id(value["order_id"])
        elif "orderId" in value:
            order_id = numeric_id(value["orderId"])
        elif "id" in value:
            order_id = numeric_id(value["id"])
        else:
            raise ValueError(f"order object has no order ID: {value!r}")

        amount = None
        for key in ("total", "total_price", "totalPrice", "amount"):
            if key in value:
                amount = float(value[key])
                break
        return order_id, amount
    return numeric_id(value), None


def extract_report(data):
    result = defaultdict(list)

    def add_orders(customer_id, orders):
        customer_id = numeric_id(customer_id)
        if orders is None:
            orders = []
        if not isinstance(orders, list):
            orders = [orders]
        for order in orders:
            result[customer_id].append(order_entry(order))
        result.setdefault(customer_id, result[customer_id])

    def parse(node):
        if isinstance(node, dict):
            for wrapper in ("customers", "report", "data", "results"):
                if wrapper in node and len(node) == 1:
                    parse(node[wrapper])
                    return

            direct = True
            converted = []
            for key, value in node.items():
                try:
                    converted.append((numeric_id(key), value))
                except ValueError:
                    direct = False
                    break
            if direct:
                for customer_id, value in converted:
                    if isinstance(value, dict):
                        for key in ("orders", "top_orders", "topOrders"):
                            if key in value:
                                value = value[key]
                                break
                    add_orders(customer_id, value)
                return

            if any(key in node for key in ("orders", "top_orders", "topOrders")):
                if "customer_id" in node:
                    customer_id = node["customer_id"]
                elif "customerId" in node:
                    customer_id = node["customerId"]
                elif "id" in node:
                    customer_id = node["id"]
                else:
                    raise ValueError("customer object has no customer ID")
                orders = node.get("orders", node.get("top_orders", node.get("topOrders")))
                add_orders(customer_id, orders)
                return

            if ("customer_id" in node or "customerId" in node) and ("order_id" in node or "orderId" in node):
                customer_id = node.get("customer_id", node.get("customerId"))
                add_orders(customer_id, [node])
                return

            for wrapper in ("customers", "report", "data", "results"):
                if wrapper in node:
                    parse(node[wrapper])
                    return
            raise ValueError("unrecognized report object structure")

        if isinstance(node, list):
            for item in node:
                parse(item)
            return

        raise ValueError("report root must contain customer or order records")

    parse(data)
    return dict(result)


def test_execution_time_and_output():
    script_path = "/home/user/report_generator.py"
    output_path = "/home/user/output.json"
    db_path = "/home/user/ecommerce.db"

    # Derive the answers before executing the submitted script, so the output is
    # checked against the actual relational data rather than trusted.
    expected = expected_report(db_path)
    assert expected, "The database contains no joined order data to verify."

    if os.path.exists(output_path):
        os.remove(output_path)

    start_time = time.time()
    result = subprocess.run(["python3", script_path], capture_output=True, text=True)
    end_time = time.time()
    runtime = end_time - start_time

    assert result.returncode == 0, f"Script failed to execute. stderr: {result.stderr}"
    assert runtime <= 0.5, f"Execution time {runtime:.4f}s exceeded the threshold of 0.5s. Query is likely unoptimized."
    assert os.path.exists(output_path), f"Output file {output_path} was not generated."

    with open(output_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Output file is not valid JSON.")

    assert isinstance(data, (dict, list)), "Output JSON should contain a valid dictionary or list structure."
    assert len(data) > 0, "Output JSON is empty."

    try:
        actual = extract_report(data)
    except (TypeError, ValueError) as exc:
        pytest.fail(f"Output JSON does not have a recognizable customer/order report structure: {exc}")

    expected_customers = set(expected)
    actual_nonempty_customers = {cid for cid, orders in actual.items() if orders}
    assert actual_nonempty_customers == expected_customers, "Output does not contain exactly the customers having qualifying orders."

    for customer_id, expected_orders in expected.items():
        actual_orders = actual.get(customer_id, [])
        actual_ids = [order_id for order_id, _ in actual_orders]
        expected_ids = [order_id for order_id, _ in expected_orders]

        assert len(actual_ids) == len(set(actual_ids)), f"Customer {customer_id} contains duplicated orders."
        assert len(actual_ids) == len(expected_ids) and set(actual_ids) == set(expected_ids), \
            f"Customer {customer_id} does not contain the correct top three orders."

        expected_totals = dict(expected_orders)
        for order_id, amount in actual_orders:
            if amount is not None:
                assert abs(amount - expected_totals[order_id]) <= max(1e-6, abs(expected_totals[order_id]) * 1e-9), \
                    f"Incorrect total for order {order_id} belonging to customer {customer_id}."

    # The report generator must not obtain a match by rewriting the source data.
    assert expected_report(db_path) == expected, "The report generator modified the order data while running."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

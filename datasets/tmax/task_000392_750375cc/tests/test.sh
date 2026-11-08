#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import os
import sqlite3
import time
import uuid

import pytest
import requests

DB_PATH = "/home/user/ecommerce.db"
BASE_URL = "http://127.0.0.1:8080/api/top_customers"


def get_api(category, limit):
    response = None
    last_error = None
    for _ in range(50):
        try:
            response = requests.get(
                BASE_URL,
                params={"category": category, "limit": limit},
                timeout=1,
            )
            break
        except requests.RequestException as exc:
            last_error = exc
            time.sleep(0.1)

    assert response is not None, f"Failed to connect to {BASE_URL}: {last_error}"
    assert response.status_code == 200, f"Expected HTTP 200, got {response.status_code}: {response.text}"
    assert "application/json" in response.headers.get("Content-Type", ""), "Expected Content-Type to be application/json"
    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response is not valid JSON")
    assert isinstance(data, list), "Expected JSON response to be a list"
    return data


def expected_results(category, limit):
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute(
            """
            SELECT c.name, ROUND(SUM(p.price * oi.quantity), 2) AS total_spend
            FROM customers AS c
            JOIN orders AS o ON o.customer_id = c.id
            JOIN order_items AS oi ON oi.order_id = o.id
            JOIN products AS p ON p.id = oi.product_id
            WHERE p.category = ?
            GROUP BY c.id, c.name
            ORDER BY total_spend DESC
            LIMIT ?
            """,
            (category, limit),
        ).fetchall()
    finally:
        conn.close()
    return [
        {"customer_name": name, "total_spend": round(float(total), 2)}
        for name, total in rows
    ]


def assert_api_matches_database(category, limit):
    data = get_api(category, limit)
    expected = expected_results(category, limit)
    assert len(data) <= limit, f"Expected at most {limit} items, got {len(data)}"
    for item in data:
        assert "customer_name" in item, "Missing 'customer_name' in response item"
        assert "total_spend" in item, "Missing 'total_spend' in response item"
        assert isinstance(item["total_spend"], (int, float)), "Expected 'total_spend' to be a number"
        assert set(item) == {"customer_name", "total_spend"}, f"Unexpected response keys: {set(item)}"
    assert data == expected, f"API result does not match database totals. Expected {expected}, got {data}"


def test_server_ready_file():
    ready_file = "/home/user/server_ready"
    for _ in range(50):
        if os.path.exists(ready_file):
            break
        time.sleep(0.1)

    assert os.path.isfile(ready_file), f"Server ready file missing at {ready_file}"
    with open(ready_file, "r") as f:
        content = f.read().strip()
    assert "READY" in content.upper(), f"Server ready file does not contain 'READY', got: {content}"


def test_vendored_framework_fixed():
    server_file = "/app/vendored_microframe/server.py"
    assert os.path.isfile(server_file), f"Server file missing at {server_file}"
    with open(server_file, "r") as f:
        content = f.read()

    assert "split('&')" in content or 'split("&")' in content, f"The bug in {server_file} does not appear to be fixed (should split on '&')."
    assert "split(';')" not in content and 'split(";")' not in content, f"The bug in {server_file} is still present (splitting on ';')."

    spec = importlib.util.spec_from_file_location("audited_microframe_server", server_file)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    handler = object.__new__(module.MicroframeHandler)
    parsed = handler.parse_query("category=Home%20%26%20Garden&limit=7")
    assert parsed == {"category": "Home & Garden", "limit": "7"}, f"Framework parsed '&'-separated parameters incorrectly: {parsed}"


def test_database_indexes_and_query_plans():
    assert os.path.isfile(DB_PATH), f"Database file missing at {DB_PATH}"
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute(
            "SELECT name, tbl_name FROM sqlite_master WHERE type='index' AND name IN ('idx_product_category', 'idx_order_items_product')"
        ).fetchall()
        indexes = {name: table for name, table in rows}

        assert 'idx_product_category' in indexes, "Index 'idx_product_category' is missing."
        assert 'idx_order_items_product' in indexes, "Index 'idx_order_items_product' is missing."
        assert indexes['idx_product_category'] == 'products', "idx_product_category is not an index on products"
        assert indexes['idx_order_items_product'] == 'order_items', "idx_order_items_product is not an index on order_items"

        product_columns = [row[2] for row in conn.execute("PRAGMA index_info('idx_product_category')")]
        item_columns = [row[2] for row in conn.execute("PRAGMA index_info('idx_order_items_product')")]
        assert product_columns == ['category'], f"idx_product_category must index products.category, got {product_columns}"
        assert item_columns == ['product_id'], f"idx_order_items_product must index order_items.product_id, got {item_columns}"

        product_plan = " ".join(
            row[3] for row in conn.execute(
                "EXPLAIN QUERY PLAN SELECT id FROM products WHERE category = ?", ("Electronics",)
            )
        )
        item_plan = " ".join(
            row[3] for row in conn.execute(
                "EXPLAIN QUERY PLAN SELECT id FROM order_items WHERE product_id = ?", (1,)
            )
        )
        assert "idx_product_category" in product_plan and "SCAN products" not in product_plan, f"Category lookup does not use idx_product_category: {product_plan}"
        assert "idx_order_items_product" in item_plan and "SCAN order_items" not in item_plan, f"Product join lookup does not use idx_order_items_product: {item_plan}"
    finally:
        conn.close()


def test_api_endpoint_matches_live_database():
    # Add unpredictable data after the agent has started its server. This prevents
    # a hard-coded response for the setup fixture from satisfying the API checks.
    token = uuid.uuid4().hex
    category = f"Audit'{token}&Segment"
    conn = sqlite3.connect(DB_PATH, timeout=5)
    try:
        next_customer = conn.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM customers").fetchone()[0]
        next_product = conn.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM products").fetchone()[0]
        next_order = conn.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM orders").fetchone()[0]
        next_item = conn.execute("SELECT COALESCE(MAX(id), 0) + 1 FROM order_items").fetchone()[0]

        customers = [
            (next_customer + i, f"AuditCustomer_{token}_{i}", f"audit_{token}_{i}@example.com")
            for i in range(3)
        ]
        products = [
            (next_product, f"AuditProduct_{token}_0", category, 13.37),
            (next_product + 1, f"AuditProduct_{token}_1", category, 2.25),
        ]
        orders = [
            (next_order + i, next_customer + i, "2026-01-01") for i in range(3)
        ]
        items = [
            (next_item, next_order, next_product, 3),
            (next_item + 1, next_order, next_product + 1, 2),
            (next_item + 2, next_order + 1, next_product, 2),
            (next_item + 3, next_order + 2, next_product + 1, 1),
        ]
        conn.executemany("INSERT INTO customers VALUES (?, ?, ?)", customers)
        conn.executemany("INSERT INTO products VALUES (?, ?, ?, ?)", products)
        conn.executemany("INSERT INTO orders VALUES (?, ?, ?)", orders)
        conn.executemany("INSERT INTO order_items VALUES (?, ?, ?, ?)", items)
        conn.commit()
    finally:
        conn.close()

    assert_api_matches_database("Electronics", 2)
    assert_api_matches_database("Furniture", 2)
    assert_api_matches_database(category, 2)
    assert_api_matches_database(category, 1)

    # A category containing SQL syntax must be treated as data, not alter the query.
    injection_category = "Electronics' OR 1=1 --"
    assert get_api(injection_category, 10) == expected_results(injection_category, 10) == []
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

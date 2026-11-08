#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import sqlite3
import pytest

DB_PATH = '/home/user/ecommerce.db'
OUTPUT_PATH = '/home/user/output.json'

def get_expected_data():
    if not os.path.exists(DB_PATH):
        pytest.fail(f"Database file {DB_PATH} is missing.")

    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    # Query customers: region 'Europe', order by id ASC, LIMIT 2 OFFSET 2
    cursor.execute("""
        SELECT id, name 
        FROM customers 
        WHERE region = 'Europe' 
        ORDER BY id ASC 
        LIMIT 2 OFFSET 2
    """)
    customers = cursor.fetchall()

    expected_data = []

    for c in customers:
        customer_id = c['id']
        customer_name = c['name']

        cursor.execute("""
            SELECT id, total 
            FROM orders 
            WHERE customer_id = ?
        """, (customer_id,))
        orders = cursor.fetchall()

        orders_list = []
        for o in orders:
            order_id = o['id']
            total = o['total']

            cursor.execute("""
                SELECT product_name 
                FROM order_items 
                WHERE order_id = ?
            """, (order_id,))
            items = [row['product_name'] for row in cursor.fetchall()]

            # Sort items to allow order-independent comparison
            items.sort()

            orders_list.append({
                "order_id": order_id,
                "total": float(total),
                "items": items
            })

        # Sort orders to allow order-independent comparison
        orders_list.sort(key=lambda x: x['order_id'])

        expected_data.append({
            "customer_id": customer_id,
            "name": customer_name,
            "orders": orders_list
        })

    conn.close()

    # Sort customers by id (already sorted from DB, but just in case)
    expected_data.sort(key=lambda x: x['customer_id'])
    return expected_data

def normalize_actual_data(data):
    # Ensure data is a list
    if not isinstance(data, list):
        return data

    for customer in data:
        if 'orders' in customer and isinstance(customer['orders'], list):
            for order in customer['orders']:
                if 'items' in order and isinstance(order['items'], list):
                    order['items'].sort()
            customer['orders'].sort(key=lambda x: x.get('order_id', 0))

    data.sort(key=lambda x: x.get('customer_id', 0))
    return data

def test_output_json_exists():
    assert os.path.isfile(OUTPUT_PATH), f"Output file not found at {OUTPUT_PATH}"

def test_output_json_content():
    assert os.path.isfile(OUTPUT_PATH), f"Output file not found at {OUTPUT_PATH}"

    try:
        with open(OUTPUT_PATH, 'r') as f:
            actual_data = json.load(f)
    except json.JSONDecodeError as e:
        pytest.fail(f"Failed to parse {OUTPUT_PATH} as JSON: {e}")

    expected_data = get_expected_data()

    actual_normalized = normalize_actual_data(actual_data)

    assert actual_normalized == expected_data, (
        f"JSON output does not match expected structure.\n"
        f"Expected: {json.dumps(expected_data, indent=2)}\n"
        f"Actual: {json.dumps(actual_normalized, indent=2)}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

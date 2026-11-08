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
REPORT_PATH = '/home/user/final_report.json'

def get_expected_data():
    """Derive the expected output from the actual database state."""
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    # Correct query with explicit join on products
    query = """
    SELECT c.name, p.category, SUM(oi.quantity * oi.price) as total_revenue
    FROM customers c
    JOIN orders o ON c.id = o.customer_id
    JOIN order_items oi ON o.id = oi.order_id
    JOIN products p ON oi.product_id = p.id
    WHERE c.region = 'North America'
    GROUP BY c.name, p.category
    """

    c.execute(query)
    results = c.fetchall()
    conn.close()

    # Filter: total_revenue > 100
    filtered = [r for r in results if r[2] > 100]

    # Sort: primarily by total_revenue DESC, secondarily by customer_name ASC
    sorted_results = sorted(filtered, key=lambda x: (-x[2], x[0]))

    # Pagination: Page 2, size 2 (skip 2, take 2)
    paginated = sorted_results[2:4]

    # Format as list of dicts
    expected_json = [
        {
            "customer_name": row[0],
            "product_category": row[1],
            "total_revenue": float(row[2])
        }
        for row in paginated
    ]

    return expected_json

def test_final_report_exists():
    """Test that the final JSON report has been created."""
    assert os.path.exists(REPORT_PATH), f"Final report missing at {REPORT_PATH}"
    assert os.path.isfile(REPORT_PATH), f"Path {REPORT_PATH} is not a file"

def test_final_report_content():
    """Test that the final JSON report contains the correct paginated data."""
    expected = get_expected_data()

    with open(REPORT_PATH, 'r') as f:
        try:
            actual = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {REPORT_PATH} does not contain valid JSON.")

    assert isinstance(actual, list), "The JSON output must be a list of objects."
    assert len(actual) == len(expected), f"Expected {len(expected)} items in the JSON array, but found {len(actual)}."

    for i, (act, exp) in enumerate(zip(actual, expected)):
        assert isinstance(act, dict), f"Item at index {i} is not a JSON object."

        assert "customer_name" in act, f"Item at index {i} is missing 'customer_name'."
        assert act["customer_name"] == exp["customer_name"], \
            f"Item at index {i} expected customer_name '{exp['customer_name']}', got '{act['customer_name']}'."

        assert "product_category" in act, f"Item at index {i} is missing 'product_category'."
        assert act["product_category"] == exp["product_category"], \
            f"Item at index {i} expected product_category '{exp['product_category']}', got '{act['product_category']}'."

        assert "total_revenue" in act, f"Item at index {i} is missing 'total_revenue'."
        assert act["total_revenue"] == exp["total_revenue"], \
            f"Item at index {i} expected total_revenue {exp['total_revenue']}, got {act['total_revenue']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

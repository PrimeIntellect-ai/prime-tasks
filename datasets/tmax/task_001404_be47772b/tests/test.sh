#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sqlite3
import pytest
import requests

API_URL = "http://127.0.0.1:8181/api/rolling"
AUTH_HEADER = {"X-Auth": "Secret77"}

def get_expected_data():
    db_path = "/app/sales.db"
    assert os.path.exists(db_path), f"Database file {db_path} is missing."

    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    query = """
    SELECT store_id, date, 
           SUM(revenue) OVER (PARTITION BY store_id ORDER BY date ROWS BETWEEN 2 PRECEDING AND CURRENT ROW) as rolling_sum
    FROM daily_sales
    ORDER BY store_id, date;
    """
    cursor.execute(query)
    rows = cursor.fetchall()
    conn.close()

    # Convert to list of dicts
    return [dict(row) for row in rows]

def test_unauthenticated_request():
    """Test that a request without the proper auth header returns 401."""
    try:
        response = requests.get(API_URL, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service at {API_URL}: {e}")

    assert response.status_code == 401, f"Expected 401 Unauthorized, got {response.status_code}. Response: {response.text}"

def test_wrong_auth_request():
    """Test that a request with an incorrect auth header returns 401."""
    try:
        response = requests.get(API_URL, headers={"X-Auth": "WrongSecret"}, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service at {API_URL}: {e}")

    assert response.status_code == 401, f"Expected 401 Unauthorized for wrong auth, got {response.status_code}. Response: {response.text}"

def test_authenticated_request():
    """Test that a request with the correct auth header returns 200 and the correct JSON data."""
    try:
        response = requests.get(API_URL, headers=AUTH_HEADER, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the service at {API_URL}: {e}")

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")

    expected_data = get_expected_data()

    assert isinstance(data, list), "Expected JSON response to be a list."
    assert len(data) == len(expected_data), f"Expected {len(expected_data)} items, got {len(data)}."

    # Compare each item
    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert actual.get("store_id") == expected["store_id"], f"Item {i}: expected store_id {expected['store_id']}, got {actual.get('store_id')}"
        assert actual.get("date") == expected["date"], f"Item {i}: expected date {expected['date']}, got {actual.get('date')}"
        assert actual.get("rolling_sum") == expected["rolling_sum"], f"Item {i}: expected rolling_sum {expected['rolling_sum']}, got {actual.get('rolling_sum')}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import random
import secrets
import sqlite3

import pytest
import requests

DB_PATH = "/app/data/analytics.db"
URL = "http://127.0.0.1:8080/api/revenue_summary"


def install_random_fixture():
    rng = random.SystemRandom()
    base = secrets.randbelow(800000) + 10000
    users = [base, base + 17, base + 43, base + 91]
    month = secrets.randbelow(9) + 1

    timestamps = [
        f"2025-{month:02d}-03 09:15:00",
        f"2025-{month:02d}-03 13:40:00",
        f"2025-{month:02d}-04 08:05:00",
    ]

    # First user is above 500, second below 500, third exactly 500,
    # and fourth above 500 with a negative adjustment.
    d1, d2, d3 = (secrets.randbelow(35) for _ in range(3))
    rows = [
        (users[0], "purchase", timestamps[2], float(180 + d3)),
        (users[0], "purchase", timestamps[0], float(175 + d1)),
        (users[0], "adjustment", timestamps[1], float(210 + d2)),
        (users[1], "purchase", timestamps[0], float(100 + secrets.randbelow(20))),
        (users[1], "purchase", timestamps[1], float(200 + secrets.randbelow(20))),
        (users[2], "purchase", timestamps[0], 125.0),
        (users[2], "purchase", timestamps[1], 375.0),
        (users[3], "purchase", timestamps[0], float(650 + d1)),
        (users[3], "refund", timestamps[2], float(-100 - d1)),
    ]
    rng.shuffle(rows)

    conn = sqlite3.connect(DB_PATH, timeout=10)
    try:
        cursor = conn.cursor()
        cursor.execute("DROP TABLE IF EXISTS events")
        cursor.execute("""
            CREATE TABLE events (
                event_id INTEGER PRIMARY KEY,
                user_id INTEGER,
                event_type TEXT,
                event_timestamp DATETIME,
                revenue REAL
            )
        """)
        cursor.executemany(
            "INSERT INTO events (user_id, event_type, event_timestamp, revenue) VALUES (?, ?, ?, ?)",
            rows,
        )
        conn.commit()
    finally:
        conn.close()

    # Compute the oracle from the verifier-owned fixture, not from the writable DB.
    totals = {}
    for user_id, _event_type, _timestamp, revenue in rows:
        totals[user_id] = totals.get(user_id, 0.0) + revenue

    expected = []
    for user_id in sorted(totals):
        if totals[user_id] <= 500:
            continue
        cumulative = 0.0
        user_rows = sorted(
            (row for row in rows if row[0] == user_id),
            key=lambda row: row[2],
        )
        for _uid, _event_type, timestamp, revenue in user_rows:
            cumulative += revenue
            expected.append({
                "user_id": user_id,
                "event_timestamp": timestamp,
                "cumulative_revenue": cumulative,
            })
    return expected


def check_api(expected_data):
    try:
        response = requests.get(URL, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API at {URL}. Ensure the server is running. Error: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}. Response: {response.text}"
    assert "application/json" in response.headers.get("Content-Type", ""), f"Expected Content-Type to be application/json, got {response.headers.get('Content-Type')}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response body is not valid JSON. Response: {response.text}")

    assert isinstance(data, list), f"Expected response to be a JSON array, got {type(data).__name__}"

    # Sort both lists by user_id and event_timestamp to compare robustly.
    data_sorted = sorted(data, key=lambda x: (x.get("user_id", 0), x.get("event_timestamp", "")))
    expected_sorted = sorted(expected_data, key=lambda x: (x["user_id"], x["event_timestamp"]))

    assert len(data_sorted) == len(expected_sorted), f"Expected {len(expected_sorted)} records, got {len(data_sorted)}"

    for actual, expected in zip(data_sorted, expected_sorted):
        assert actual.get("user_id") == expected["user_id"], f"Expected user_id {expected['user_id']}, got {actual.get('user_id')}"
        assert actual.get("event_timestamp") == expected["event_timestamp"], f"Expected event_timestamp {expected['event_timestamp']}, got {actual.get('event_timestamp')}"

        actual_rev = actual.get("cumulative_revenue")
        expected_rev = expected["cumulative_revenue"]
        assert actual_rev is not None, f"Missing cumulative_revenue in response object: {actual}"

        try:
            actual_rev_float = float(actual_rev)
            expected_rev_float = float(expected_rev)
        except (ValueError, TypeError):
            pytest.fail(f"Invalid cumulative_revenue format: expected number, got {actual_rev}")

        assert abs(actual_rev_float - expected_rev_float) < 0.01, f"Expected cumulative_revenue {expected_rev_float} for user {expected['user_id']} at {expected['event_timestamp']}, got {actual_rev_float}"


def test_api_revenue_summary():
    """Test that the API processes changing, verifier-controlled event data."""
    # Two independent fixtures reject empty responses, fixed fixture answers, and
    # services that return a result cached from only the first request.
    for _ in range(2):
        expected = install_random_fixture()
        assert expected, "Verifier fixture unexpectedly produced no eligible users"
        check_api(expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

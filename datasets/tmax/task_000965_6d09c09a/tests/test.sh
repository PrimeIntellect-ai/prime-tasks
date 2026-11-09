#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import secrets
import sqlite3

import pytest
import requests

URL = "http://127.0.0.1:8000/centrality"
DB = "/app/data.db"


def get_centrality():
    try:
        response = requests.get(URL, timeout=5, headers={"Cache-Control": "no-cache"})
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API at {URL}. Error: {e}")

    assert response.status_code == 200, (
        f"Expected status code 200, got {response.status_code}. "
        f"Response: {response.text}"
    )

    try:
        return response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON. Response text: {response.text}")


def unused_ids(conn, table, count):
    result = []
    while len(result) < count:
        candidate = 1_000_000_000 + secrets.randbelow(1_000_000_000)
        if candidate in result:
            continue
        row = conn.execute(f"SELECT 1 FROM {table} WHERE id = ?", (candidate,)).fetchone()
        if row is None:
            result.append(candidate)
    return result


def expected_from_database(conn):
    rows = conn.execute(
        """
        SELECT v.id, COUNT(DISTINCT s.client_id)
        FROM vendors AS v
        LEFT JOIN sales AS s
          ON s.vendor_id = v.id AND s.status = 'SUCCESS'
        GROUP BY v.id
        ORDER BY v.id
        """
    ).fetchall()
    return {str(vendor_id): int(score) for vendor_id, score in rows}


def test_api_centrality():
    # Preserve the original fixture assertion.
    data = get_centrality()
    expected_data = {"10": 2, "20": 1}
    assert data == expected_data, f"Expected JSON response {expected_data}, but got {data}"

    # Add unpredictable records after the server has started. This requires the
    # endpoint to query the live database and apply failed-sale and uniqueness rules.
    conn = sqlite3.connect(DB, timeout=10)
    try:
        client_ids = unused_ids(conn, "clients", 3)
        vendor_ids = unused_ids(conn, "vendors", 2)
        sale_ids = unused_ids(conn, "sales", 8)
        c1, c2, c3 = client_ids
        v1, v2 = vendor_ids

        conn.executemany(
            "INSERT INTO clients(id, name) VALUES (?, ?)",
            [(c1, "Verifier Client A"), (c2, "Verifier Client B"), (c3, "Verifier Client C")],
        )
        conn.executemany(
            "INSERT INTO vendors(id, name) VALUES (?, ?)",
            [(v1, "Verifier Vendor A"), (v2, "Verifier Vendor B")],
        )
        conn.executemany(
            "INSERT INTO sales(id, client_id, vendor_id, status) VALUES (?, ?, ?, ?)",
            [
                (sale_ids[0], c1, v1, "SUCCESS"),
                (sale_ids[1], c1, v1, "SUCCESS"),  # duplicate client must count once
                (sale_ids[2], c2, v1, "SUCCESS"),
                (sale_ids[3], c3, v1, "FAILED"),   # failed sale must be excluded
                (sale_ids[4], c2, v2, "SUCCESS"),
                (sale_ids[5], c1, v2, "FAILED"),
                (sale_ids[6], c3, 10, "SUCCESS"),  # alter an existing vendor too
                (sale_ids[7], c3, 10, "SUCCESS"),  # duplicate must count once
            ],
        )
        conn.commit()
        dynamic_expected = expected_from_database(conn)
    finally:
        conn.close()

    dynamic_data = get_centrality()
    assert dynamic_data == dynamic_expected, (
        "The endpoint did not reflect the live database using unique successful "
        f"clients per vendor. Expected {dynamic_expected}, got {dynamic_data}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

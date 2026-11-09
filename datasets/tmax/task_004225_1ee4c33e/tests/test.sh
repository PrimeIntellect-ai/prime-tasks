#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import secrets
import re

import psycopg2
import pytest
import requests
from pymongo import MongoClient

BASE_URL = "http://127.0.0.1:8080/api/v1/user-activity"
AUTH_HEADER = {"Authorization": "Bearer etl-secret-token"}
REQUIRED_FIELDS = ("user_id", "username", "department", "total_duration", "department_rank")


def authorized_get():
    try:
        return requests.get(BASE_URL, headers=AUTH_HEADER, timeout=10)
    except requests.exceptions.ConnectionError:
        pytest.fail("Flask service is not running or not listening on 127.0.0.1:8080.")


def test_required_database_queries_are_present():
    """Require the submitted service to contain the requested Mongo and SQL operations."""
    path = "/app/etl_service.py"
    with open(path, "r", encoding="utf-8") as handle:
        source = handle.read()
    tree = ast.parse(source, filename=path)

    calls = [node for node in ast.walk(tree) if isinstance(node, ast.Call)]
    assert any(isinstance(call.func, ast.Attribute) and call.func.attr == "aggregate" for call in calls), \
        "The MongoDB events collection must be queried with aggregate()."

    string_literals = [node.value for node in ast.walk(tree)
                       if isinstance(node, ast.Constant) and isinstance(node.value, str)]
    literal_text = "\n".join(string_literals)
    for token in ("$match", "$group", "$sum", "completed"):
        assert token in literal_text, f"MongoDB aggregation pipeline is missing {token}."

    sql_strings = [value for value in string_literals
                   if re.search(r"dense_rank\s*\(\s*\)", value, re.IGNORECASE)]
    assert sql_strings, "The PostgreSQL query must use DENSE_RANK()."
    ranking_sql = "\n".join(sql_strings)
    assert re.search(r"\bover\s*\(", ranking_sql, re.IGNORECASE), \
        "DENSE_RANK() must be used as a window function."
    assert re.search(r"\bpartition\s+by\b", ranking_sql, re.IGNORECASE), \
        "The ranking window must partition by department."
    assert re.search(r"\border\s+by\b", ranking_sql, re.IGNORECASE), \
        "The ranking window must order by total duration."
    assert re.search(r"\bjoin\b", ranking_sql, re.IGNORECASE), \
        "The ranking query must join the aggregated activity data with users."


def test_unauthorized_request():
    """Verify that a request without the auth header returns 401."""
    try:
        response = requests.get(BASE_URL, timeout=5)
    except requests.exceptions.ConnectionError:
        pytest.fail("Flask service is not running or not listening on 127.0.0.1:8080.")

    assert response.status_code == 401, f"Expected 401 Unauthorized, got {response.status_code}. Response: {response.text}"


def test_invalid_authorization_request():
    response = requests.get(BASE_URL, headers={"Authorization": "Bearer wrong-token"}, timeout=5)
    assert response.status_code == 401, \
        f"Expected 401 for an invalid token, got {response.status_code}. Response: {response.text}"


def test_authorized_request():
    """Verify that a request with the valid auth header returns 200 and correct JSON."""
    response = authorized_get()
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"

    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response is not valid JSON.")

    assert isinstance(data, list), "Expected response to be a JSON array (list)."

    bob = next((u for u in data if u.get("user_id") == 2), None)
    alice = next((u for u in data if u.get("user_id") == 1), None)

    assert bob is not None, "User 'bob' (user_id: 2) is missing from the response."
    assert alice is not None, "User 'alice' (user_id: 1) is missing from the response."

    assert bob.get("username") == "bob", "Incorrect username for user_id 2."
    assert bob.get("department") == "engineering", "Incorrect department for user_id 2."
    assert bob.get("total_duration") == 300, f"Expected total_duration 300 for bob, got {bob.get('total_duration')}."
    assert bob.get("department_rank") == 1, f"Expected department_rank 1 for bob, got {bob.get('department_rank')}."

    assert alice.get("username") == "alice", "Incorrect username for user_id 1."
    assert alice.get("department") == "engineering", "Incorrect department for user_id 1."
    assert alice.get("total_duration") == 120, f"Expected total_duration 120 for alice, got {alice.get('total_duration')}."
    assert alice.get("department_rank") == 2, f"Expected department_rank 2 for alice, got {alice.get('department_rank')}."


def test_live_database_integration_and_full_recomputed_result():
    """Insert unpredictable records, then derive the complete expected response from both databases."""
    mongo = MongoClient("mongodb://127.0.0.1:27017", serverSelectionTimeoutMS=5000)
    pg = psycopg2.connect(host="127.0.0.1", port=5432, dbname="etl_db",
                          user="etl_user", password="etl_pass")
    events = mongo["activity"]["events"]

    base = 100000000 + secrets.randbelow(900000000)
    ids = [base + i for i in range(5)]
    department = "verify_" + secrets.token_hex(8)
    names = ["verify_" + secrets.token_hex(6) for _ in ids]
    high = 700 + secrets.randbelow(200)
    low = 200 + secrets.randbelow(100)

    try:
        with pg.cursor() as cur:
            cur.executemany(
                "INSERT INTO users (user_id, username, department) VALUES (%s, %s, %s)",
                [(ids[i], names[i], department) for i in range(4)]
            )
        pg.commit()

        events.insert_many([
            {"user_id": ids[0], "status": "completed", "duration": high - 17},
            {"user_id": ids[0], "status": "completed", "duration": 17},
            {"user_id": ids[0], "status": "failed", "duration": 99999},
            {"user_id": ids[1], "status": "completed", "duration": high},
            {"user_id": ids[2], "status": "completed", "duration": low - 11},
            {"user_id": ids[2], "status": "completed", "duration": 11},
            {"user_id": ids[3], "status": "failed", "duration": 50000},
            # This activity has no matching PostgreSQL user and must not survive the join.
            {"user_id": ids[4], "status": "completed", "duration": high + 1000},
        ])

        # Independently recompute the expected inner join from the live databases.
        totals = {
            row["_id"]: row["total_duration"]
            for row in events.aggregate([
                {"$match": {"status": "completed"}},
                {"$group": {"_id": "$user_id", "total_duration": {"$sum": "$duration"}}},
            ])
        }
        with pg.cursor() as cur:
            cur.execute("SELECT user_id, username, department FROM users")
            users = cur.fetchall()

        joined = []
        for user_id, username, dept in users:
            if user_id in totals:
                joined.append({
                    "user_id": user_id,
                    "username": username,
                    "department": dept,
                    "total_duration": totals[user_id],
                })

        by_department = {}
        for row in joined:
            by_department.setdefault(row["department"], set()).add(row["total_duration"])
        for row in joined:
            descending = sorted(by_department[row["department"]], reverse=True)
            row["department_rank"] = descending.index(row["total_duration"]) + 1

        response = authorized_get()
        assert response.status_code == 200, \
            f"Expected 200 OK after live database updates, got {response.status_code}: {response.text}"
        try:
            actual = response.json()
        except ValueError:
            pytest.fail("Response is not valid JSON.")
        assert isinstance(actual, list), "Expected response to be a JSON array (list)."
        assert all(isinstance(row, dict) for row in actual), "Every array item must be a JSON object."

        normalized = [{field: row.get(field) for field in REQUIRED_FIELDS} for row in actual]
        actual_by_id = {row["user_id"]: row for row in normalized}
        expected_by_id = {row["user_id"]: row for row in joined}
        assert len(actual_by_id) == len(normalized), "Response contains duplicate user_id values."
        assert actual_by_id == expected_by_id, \
            f"Response does not match results recomputed from MongoDB and PostgreSQL. Expected {expected_by_id}, got {actual_by_id}"

        assert actual_by_id[ids[0]]["department_rank"] == 1
        assert actual_by_id[ids[1]]["department_rank"] == 1, \
            "Equal totals must receive the same DENSE_RANK()."
        assert actual_by_id[ids[2]]["department_rank"] == 2, \
            "The rank after a tie must be 2 for DENSE_RANK(), not 3."
        assert ids[3] not in actual_by_id, "Failed-only activity must be excluded."
        assert ids[4] not in actual_by_id, "Activity without a matching PostgreSQL user must be excluded by the join."
    finally:
        try:
            events.delete_many({"user_id": {"$in": ids}})
        finally:
            try:
                pg.rollback()
                with pg.cursor() as cur:
                    cur.execute("DELETE FROM users WHERE user_id = ANY(%s)", (ids,))
                pg.commit()
            finally:
                pg.close()
                mongo.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

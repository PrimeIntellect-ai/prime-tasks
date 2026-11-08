#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import sqlite3
import ctypes
import pytest
import requests

def test_c_library_built_and_loadable():
    lib_path = '/home/user/auth-lib/libauth.so'
    assert os.path.exists(lib_path), f"Shared library {lib_path} was not built."

    try:
        lib = ctypes.CDLL(lib_path)
    except Exception as e:
        pytest.fail(f"Failed to load {lib_path}. Error: {e}")

    assert hasattr(lib, 'compute_auth_hash'), "compute_auth_hash function not found in libauth.so"
    assert lib.compute_auth_hash() == 8, "compute_auth_hash did not return the expected value."

def test_database_migration():
    db_path = '/home/user/db/audit.db'
    assert os.path.exists(db_path), f"Database {db_path} is missing."

    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    # Check users table
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='users';")
    assert cursor.fetchone() is not None, "Table 'users' was not created."

    cursor.execute("SELECT * FROM users")
    users = cursor.fetchall()
    assert len(users) == 1, "Expected exactly 1 user in 'users' table."
    assert users[0]['user_id'] == 1, "User ID should be 1."
    assert users[0]['username'] == 'admin', "Username should be 'admin'."

    # Check log_entries table
    cursor.execute("PRAGMA table_info(log_entries);")
    columns = {row['name']: row['type'] for row in cursor.fetchall()}
    assert 'client_ip' in columns, "Column 'client_ip' is missing from 'log_entries'."
    assert 'user_id' in columns, "Column 'user_id' is missing from 'log_entries'."

    # Check foreign keys
    cursor.execute("PRAGMA foreign_key_list(log_entries);")
    fks = cursor.fetchall()
    fk_found = False
    for fk in fks:
        if fk['table'] == 'users' and fk['from'] == 'user_id' and fk['to'] == 'user_id':
            fk_found = True
            break
    assert fk_found, "Foreign key constraint from log_entries(user_id) to users(user_id) is missing."

    # Check log_entries data
    cursor.execute("SELECT * FROM log_entries ORDER BY id;")
    logs = cursor.fetchall()
    assert len(logs) == 2, "Expected exactly 2 rows in 'log_entries'."

    for log in logs:
        assert log['client_ip'] == '0.0.0.0', f"Expected client_ip '0.0.0.0', got {log['client_ip']}"
        assert log['user_id'] == 1, f"Expected user_id 1, got {log['user_id']}"

    conn.close()

def test_api_service():
    base_url = "http://127.0.0.1:8000"

    # Test health endpoint
    try:
        resp = requests.get(f"{base_url}/health", timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API service: {e}")

    assert resp.status_code == 200, f"Expected 200 OK from /health, got {resp.status_code}"
    assert resp.json() == {"status": "ok"}, "Unexpected response from /health"

    # Test unauthorized access
    resp = requests.get(f"{base_url}/api/v1/audit/logs", timeout=2)
    assert resp.status_code == 401, f"Expected 401 Unauthorized without token, got {resp.status_code}"

    # Test authorized access
    token = "CI_TOKEN_8847A29F"
    headers = {"Authorization": f"Bearer {token}"}
    resp = requests.get(f"{base_url}/api/v1/audit/logs", headers=headers, timeout=2)
    assert resp.status_code == 200, f"Expected 200 OK with valid token, got {resp.status_code}"

    data = resp.json()
    assert isinstance(data, list), "Expected a JSON array"
    assert len(data) == 2, "Expected 2 log entries"

    expected_data = [
        {
            "id": 1,
            "action": "login_attempt",
            "timestamp": 1625097600,
            "client_ip": "0.0.0.0",
            "user_id": 1
        },
        {
            "id": 2,
            "action": "password_change",
            "timestamp": 1625097660,
            "client_ip": "0.0.0.0",
            "user_id": 1
        }
    ]

    assert data == expected_data, f"API response data mismatch. Got: {data}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

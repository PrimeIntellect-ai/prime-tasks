#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sqlite3
import pytest

AUTH_SERVICE_DIR = "/home/user/auth_service"
AUTH_C_PATH = os.path.join(AUTH_SERVICE_DIR, "auth.c")
AUTH_FIXED_PATH = os.path.join(AUTH_SERVICE_DIR, "auth_fixed")
USERS_DB_PATH = os.path.join(AUTH_SERVICE_DIR, "users.db")
XOR_KEY_PATH = "/home/user/xor_key.txt"
OLD_PASSWORD_PATH = "/home/user/old_password.txt"

def test_xor_key_extracted():
    assert os.path.isfile(XOR_KEY_PATH), f"File {XOR_KEY_PATH} does not exist."
    with open(XOR_KEY_PATH, 'r') as f:
        content = f.read().strip().lower()

    assert content in ['0x4b', '4b'], f"Incorrect XOR key in {XOR_KEY_PATH}. Found: {content}"

def test_old_password_extracted():
    assert os.path.isfile(OLD_PASSWORD_PATH), f"File {OLD_PASSWORD_PATH} does not exist."
    with open(OLD_PASSWORD_PATH, 'r') as f:
        content = f.read().strip()

    assert content == "legacy_pwd_99", f"Incorrect old password in {OLD_PASSWORD_PATH}. Found: {content}"

def test_database_credential_rotated():
    assert os.path.isfile(USERS_DB_PATH), f"Database {USERS_DB_PATH} does not exist."

    conn = sqlite3.connect(USERS_DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT password FROM users WHERE username='admin';")
    row = cursor.fetchone()
    conn.close()

    assert row is not None, "Admin user missing from database."
    # The expected hash is "Secure_Rotated_2024" XORed with 0x4B and hex encoded
    expected_hash = "182e283e392e1419243f2a3f2e2f14797b797f"
    assert row[0].lower() == expected_hash, f"Admin password hash was not correctly updated. Found: {row[0]}"

def test_auth_fixed_executable_exists():
    assert os.path.isfile(AUTH_FIXED_PATH), f"Compiled executable {AUTH_FIXED_PATH} does not exist."
    assert os.access(AUTH_FIXED_PATH, os.X_OK), f"File {AUTH_FIXED_PATH} is not executable."

def test_auth_c_vulnerability_fixed():
    assert os.path.isfile(AUTH_C_PATH), f"Source code {AUTH_C_PATH} does not exist."
    with open(AUTH_C_PATH, 'r') as f:
        content = f.read()

    # Check that the vulnerable pattern is removed
    assert 'sprintf(query, "SELECT' not in content, f"Vulnerable sprintf pattern still found in {AUTH_C_PATH}."

    # Check that parameterized queries are used
    assert 'sqlite3_bind_text' in content, f"sqlite3_bind_text not found in {AUTH_C_PATH}. Parameterized queries must be used."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

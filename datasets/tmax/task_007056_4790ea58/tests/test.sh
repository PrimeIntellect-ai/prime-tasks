#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_attacker_session_extracted():
    session_file = "/home/user/attacker_session.txt"
    assert os.path.isfile(session_file), f"The file {session_file} does not exist."

    with open(session_file, "r") as f:
        content = f.read().strip()

    assert content == "malicious_xyz_7734", f"Expected session ID 'malicious_xyz_7734', but found '{content}' in {session_file}."

def test_db_password_rotated():
    conf_file = "/home/user/config/db.conf"
    assert os.path.isfile(conf_file), f"The file {conf_file} does not exist."

    with open(conf_file, "r") as f:
        lines = f.read().splitlines()

    expected_lines = [
        "# Database Configuration",
        "DB_HOST=127.0.0.1",
        "DB_PORT=5432",
        "DB_USER=admin",
        "DB_PASSWORD=SECURE_DB_PASS_2024",
        "DB_NAME=production_db"
    ]

    assert "DB_PASSWORD=SECURE_DB_PASS_2024" in lines, "The DB_PASSWORD was not rotated to SECURE_DB_PASS_2024."
    assert "DB_PASSWORD=old_compromised_pass_123" not in lines, "The old compromised password is still present in db.conf."

    # Check that other lines remain unchanged
    for expected_line in expected_lines:
        assert expected_line in lines, f"Expected line '{expected_line}' is missing from {conf_file}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

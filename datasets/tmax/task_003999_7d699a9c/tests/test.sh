#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sqlite3
import json
import pytest

DB_PATH = '/home/user/audit.db'
FLAGGED_PATH = '/home/user/flagged.txt'

def get_expected_flagged_users():
    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()

    # 1. Get users with exactly 2 hops to 'Customer_Data'
    c.execute("""
        SELECT a.source 
        FROM system_graph a
        JOIN system_graph b ON a.target = b.source
        WHERE b.target = 'Customer_Data'
    """)
    valid_users = {row[0] for row in c.fetchall()}

    # 2. Get successful logs for these users to 'Customer_Data'
    c.execute("""
        SELECT user_id, timestamp, details_json
        FROM access_logs
        WHERE resource = 'Customer_Data'
    """)

    logs_by_user = {}
    for user_id, ts, details in c.fetchall():
        if user_id not in valid_users:
            continue
        try:
            status = json.loads(details).get("status")
        except json.JSONDecodeError:
            continue
        if status == "SUCCESS":
            logs_by_user.setdefault(user_id, []).append(ts)

    conn.close()

    # 3. Calculate rolling count > 3 in any 3600-second window
    flagged = set()
    for user, timestamps in logs_by_user.items():
        timestamps.sort()
        for i in range(len(timestamps)):
            count = 0
            for j in range(i, len(timestamps)):
                if timestamps[j] - timestamps[i] <= 3600:
                    count += 1
            if count > 3:
                flagged.add(user)
                break

    return sorted(list(flagged))

def test_flagged_file_exists():
    assert os.path.isfile(FLAGGED_PATH), f"The output file {FLAGGED_PATH} does not exist."

def test_flagged_file_contents():
    expected_users = get_expected_flagged_users()

    with open(FLAGGED_PATH, 'r') as f:
        content = f.read().strip()

    if not content:
        actual_users = []
    else:
        actual_users = [line.strip() for line in content.splitlines()]

    assert actual_users == expected_users, (
        f"The contents of {FLAGGED_PATH} do not match the expected flagged users.\n"
        f"Expected: {expected_users}\n"
        f"Found: {actual_users}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

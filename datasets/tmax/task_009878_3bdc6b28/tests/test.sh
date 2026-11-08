#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import pytest

def test_role_summary_exists_and_correct():
    users_file = "/home/user/users.csv"
    logs_file = "/home/user/access_logs.jsonl"
    summary_file = "/home/user/role_summary.json"

    assert os.path.exists(summary_file), f"The output file {summary_file} does not exist."
    assert os.path.isfile(summary_file), f"{summary_file} is not a file."

    # Derive expected state from the input files
    user_roles = {}
    with open(users_file, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            username = row["username"].strip().lower()
            user_roles[username] = row["role"].strip()

    unique_requests = set()
    with open(logs_file, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            log = json.loads(line)
            username = log["username"].strip().lower()

            # Ignore users not in the CSV
            if username not in user_roles:
                continue

            endpoint = log["endpoint"]
            timestamp = log["timestamp"]
            # Truncate to the minute (e.g., "2023-10-01T14:32:45Z" -> "2023-10-01T14:32")
            truncated_timestamp = timestamp[:16]

            unique_requests.add((username, endpoint, truncated_timestamp))

    expected_summary = {}
    for req in unique_requests:
        username = req[0]
        role = user_roles[username]
        expected_summary[role] = expected_summary.get(role, 0) + 1

    # Read the actual output
    with open(summary_file, "r", encoding="utf-8") as f:
        try:
            actual_summary = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {summary_file} does not contain valid JSON.")

    assert actual_summary == expected_summary, (
        f"The role summary is incorrect.\n"
        f"Expected: {expected_summary}\n"
        f"Actual:   {actual_summary}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

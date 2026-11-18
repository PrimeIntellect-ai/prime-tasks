#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_summary_csv():
    file_path = "/home/user/summary.csv"

    assert os.path.isfile(file_path), f"Expected file {file_path} is missing."

    expected_csv = """hour,user,action,count
2023-10-01T10,alice,login,1
2023-10-01T10,alice,view,1
2023-10-01T10,bob,login,1
2023-10-01T11,alice,login,1
2023-10-01T11,alice,logout,1
2023-10-01T11,bob,view,2"""

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content == expected_csv, f"Content of {file_path} does not match the expected aggregated CSV format and data."

def test_insert_sql():
    file_path = "/home/user/insert.sql"

    assert os.path.isfile(file_path), f"Expected file {file_path} is missing."

    expected_sql = """INSERT INTO hourly_stats (hour, username, action, event_count) VALUES ('2023-10-01T10', 'alice', 'login', 1);
INSERT INTO hourly_stats (hour, username, action, event_count) VALUES ('2023-10-01T10', 'alice', 'view', 1);
INSERT INTO hourly_stats (hour, username, action, event_count) VALUES ('2023-10-01T10', 'bob', 'login', 1);
INSERT INTO hourly_stats (hour, username, action, event_count) VALUES ('2023-10-01T11', 'alice', 'login', 1);
INSERT INTO hourly_stats (hour, username, action, event_count) VALUES ('2023-10-01T11', 'alice', 'logout', 1);
INSERT INTO hourly_stats (hour, username, action, event_count) VALUES ('2023-10-01T11', 'bob', 'view', 2);"""

    with open(file_path, "r") as f:
        content = f.read().strip()

    assert content == expected_sql, f"Content of {file_path} does not match the expected SQL INSERT statements."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

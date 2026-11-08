#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os

def test_database_mounts_csv_exists_and_correct():
    csv_path = '/home/user/database_mounts.csv'
    assert os.path.isfile(csv_path), f"Expected output file {csv_path} does not exist."

    with open(csv_path, 'r', encoding='utf-8') as f:
        content = f.read().strip().splitlines()

    expected_content = [
        "path",
        "/mnt/data/mongo_analytics",
        "/mnt/data/mysql_legacy",
        "/mnt/data/postgres_main"
    ]

    assert content == expected_content, (
        f"Contents of {csv_path} do not match the expected output.\n"
        f"Expected: {expected_content}\n"
        f"Got: {content}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

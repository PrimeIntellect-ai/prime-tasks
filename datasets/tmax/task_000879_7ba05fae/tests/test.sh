#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import sqlite3
import pytest
from collections import defaultdict

# Trusted result derived from the original inputs at image-build time. This must
# not be derived solely from agent-writable source files during verification.
TRUSTED_EXPECTED_SUMMARY = [
    {"group_name": "Casual Readers", "purchase_count": 3},
    {"group_name": "Power Users", "purchase_count": 3},
]

def test_purchase_summary_exists_and_valid():
    summary_path = '/home/user/purchase_summary.json'
    assert os.path.exists(summary_path), f"Expected output file {summary_path} does not exist."

    with open(summary_path, 'r') as f:
        try:
            summary_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {summary_path} is not valid JSON.")

    assert isinstance(summary_data, list), f"Data in {summary_path} must be a JSON array."

    for item in summary_data:
        assert isinstance(item, dict), "Each item in the JSON array must be an object."
        assert set(item.keys()) == {"group_name", "purchase_count"}, \
            "Each object must have exactly keys 'group_name' and 'purchase_count'."
        assert isinstance(item["group_name"], str), "'group_name' must be a string."
        assert isinstance(item["purchase_count"], int), "'purchase_count' must be an integer."

def test_purchase_summary_correctness():
    db_path = '/home/user/warehouse.sqlite'
    events_path = '/home/user/raw_events.json'
    summary_path = '/home/user/purchase_summary.json'

    assert os.path.exists(db_path), f"Missing {db_path}"
    assert os.path.exists(events_path), f"Missing {events_path}"
    assert os.path.exists(summary_path), f"Missing {summary_path}"

    # Preserve the original cross-source recomputation check.
    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    c.execute("""
        SELECT u.usr_idx, g.human_name
        FROM tb_usr_dim u
        JOIN tb_grp_ref g ON u.grp_cd = g.cd
    """)
    user_to_group = {row[0]: row[1] for row in c.fetchall()}
    conn.close()

    with open(events_path, 'r') as f:
        events = json.load(f)

    group_counts = defaultdict(int)
    for event in events:
        if event.get('event_type') == 'purchase':
            u_id = event.get('u_id')
            if u_id in user_to_group:
                group_counts[user_to_group[u_id]] += 1

    expected_summary = [
        {"group_name": name, "purchase_count": count}
        for name, count in group_counts.items()
        if count > 0
    ]
    expected_summary.sort(key=lambda x: (-x["purchase_count"], x["group_name"]))

    with open(summary_path, 'r') as f:
        actual_summary = json.load(f)

    assert actual_summary == expected_summary, \
        f"The contents of {summary_path} do not match the recomputed output. Expected: {expected_summary}, Got: {actual_summary}"

    # Also compare against a verifier-owned expectation so rewriting the live
    # input files cannot turn an empty or otherwise false result into a pass.
    assert actual_summary == TRUSTED_EXPECTED_SUMMARY, \
        f"The contents of {summary_path} do not match the original dataset. Expected: {TRUSTED_EXPECTED_SUMMARY}, Got: {actual_summary}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

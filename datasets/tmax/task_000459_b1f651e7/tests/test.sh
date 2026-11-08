#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import sqlite3
import pytest
from collections import defaultdict

def test_top_influencers_output():
    output_path = '/home/user/top_influencers.json'
    db_path = '/home/user/users.db'
    jsonl_path = '/home/user/interactions.jsonl'

    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."

    # 1. Read users from SQLite
    assert os.path.isfile(db_path), f"Database file {db_path} is missing."
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT id, name, department FROM users")
    users = {row[0]: {"name": row[1], "department": row[2]} for row in cursor.fetchall()}
    conn.close()

    # 2. Read interactions and compute in-degrees
    assert os.path.isfile(jsonl_path), f"Interactions file {jsonl_path} is missing."
    in_degrees = defaultdict(int)
    with open(jsonl_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            data = json.loads(line)
            target_id = data.get("target_id")
            weight = data.get("weight", 0)
            if target_id is not None:
                in_degrees[target_id] += weight

    # Include all users in the graph (even those with 0 in-degree)
    for user_id in users:
        if user_id not in in_degrees:
            in_degrees[user_id] = 0

    # 3. Sort by weighted in-degree (descending), then user id (ascending)
    sorted_users = sorted(in_degrees.items(), key=lambda x: (-x[1], x[0]))
    top_3 = sorted_users[:3]

    # 4. Construct expected output
    expected_output = []
    for user_id, weight in top_3:
        expected_output.append({
            "user_id": user_id,
            "name": users[user_id]["name"],
            "department": users[user_id]["department"],
            "weighted_in_degree": weight
        })

    # 5. Read and validate student output
    with open(output_path, 'r') as f:
        try:
            student_output = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {output_path} does not contain valid JSON.")

    assert isinstance(student_output, list), f"Expected the output to be a list of dictionaries, got {type(student_output).__name__}."
    assert len(student_output) == len(expected_output), f"Expected {len(expected_output)} items in the output, got {len(student_output)}."

    for i, (expected, student) in enumerate(zip(expected_output, student_output)):
        assert student == expected, f"Mismatch at rank {i+1}. Expected {expected}, got {student}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

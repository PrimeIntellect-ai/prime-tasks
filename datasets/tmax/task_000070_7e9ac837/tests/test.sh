#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import re
from collections import defaultdict

def test_user_stats_csv_exists_and_format():
    """Verify that the user_stats.csv file exists and has the correct header."""
    output_path = "/home/user/user_stats.csv"
    assert os.path.exists(output_path), f"Output file {output_path} does not exist."
    assert os.path.isfile(output_path), f"Path {output_path} is not a file."

    with open(output_path, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            assert False, f"{output_path} is empty."

        expected_header = ["user_id", "total_queries", "total_tokens", "max_tokens"]
        # Allow slight variations in spacing but require exact column names
        header_stripped = [col.strip() for col in header]
        assert header_stripped == expected_header, f"Header mismatch. Expected {expected_header}, got {header_stripped}."

def test_user_stats_content():
    """Verify that the content of user_stats.csv matches the expected computed statistics."""
    input_path = "/home/user/search_logs.txt"
    output_path = "/home/user/user_stats.csv"

    assert os.path.exists(input_path), f"Input file {input_path} is missing."
    assert os.path.exists(output_path), f"Output file {output_path} is missing."

    # Compute expected stats
    user_stats = defaultdict(lambda: {"total_queries": 0, "total_tokens": 0, "max_tokens": 0})

    with open(input_path, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip('\n')
            if not line:
                continue
            parts = line.split("|")
            if len(parts) < 3:
                continue

            user_id = parts[1].strip()
            raw_query = parts[2]

            # Normalize query
            normalized = raw_query.lower()
            normalized = re.sub(r'[^a-z0-9\s]', ' ', normalized)
            normalized = re.sub(r'\s+', ' ', normalized).strip()

            tokens = normalized.split() if normalized else []
            token_count = len(tokens)

            user_stats[user_id]["total_queries"] += 1
            user_stats[user_id]["total_tokens"] += token_count
            if token_count > user_stats[user_id]["max_tokens"]:
                user_stats[user_id]["max_tokens"] = token_count

    # Sort expected stats
    expected_rows = []
    for uid, stats in user_stats.items():
        expected_rows.append({
            "user_id": uid,
            "total_queries": stats["total_queries"],
            "total_tokens": stats["total_tokens"],
            "max_tokens": stats["max_tokens"]
        })

    expected_rows.sort(key=lambda x: (-x["total_queries"], x["user_id"]))

    # Read actual stats
    actual_rows = []
    with open(output_path, "r", encoding="utf-8") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        for row in reader:
            if not row or not any(row):
                continue
            assert len(row) == 4, f"Row does not have exactly 4 columns: {row}"
            actual_rows.append({
                "user_id": row[0].strip(),
                "total_queries": int(row[1].strip()),
                "total_tokens": int(row[2].strip()),
                "max_tokens": int(row[3].strip())
            })

    # Check total number of users
    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} users, but found {len(actual_rows)} in the output."

    # Check sorting and values
    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual["user_id"] == expected["user_id"], f"Row {i+1} user_id mismatch or incorrect sorting. Expected '{expected['user_id']}', got '{actual['user_id']}'."
        assert actual["total_queries"] == expected["total_queries"], f"Row {i+1} for user {actual['user_id']} total_queries mismatch. Expected {expected['total_queries']}, got {actual['total_queries']}."
        assert actual["total_tokens"] == expected["total_tokens"], f"Row {i+1} for user {actual['user_id']} total_tokens mismatch. Expected {expected['total_tokens']}, got {actual['total_tokens']}."
        assert actual["max_tokens"] == expected["max_tokens"], f"Row {i+1} for user {actual['user_id']} max_tokens mismatch. Expected {expected['max_tokens']}, got {actual['max_tokens']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

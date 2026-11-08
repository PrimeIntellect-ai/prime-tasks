#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest
from collections import defaultdict

def test_suspicious_users_json_exists():
    """Test that the output file suspicious_users.json exists."""
    file_path = "/home/user/suspicious_users.json"
    assert os.path.exists(file_path), f"Output file {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} is not a regular file."

def test_suspicious_users_json_schema_and_content():
    """Test that the output file contains the correct results based on the audit logs."""
    input_file = "/home/user/audit_logs.jsonl"
    output_file = "/home/user/suspicious_users.json"

    assert os.path.exists(input_file), f"Input file {input_file} is missing, cannot verify."

    # Recompute expected results
    access_counts = defaultdict(int)
    granted_by_admin_007 = defaultdict(bool)

    with open(input_file, 'r') as f:
        for line in f:
            if not line.strip():
                continue
            event = json.loads(line)

            user_id = event.get("user_id")
            if not user_id:
                continue

            action = event.get("action")
            resource = event.get("resource", {})
            metadata = event.get("metadata", {})

            if action == "ACCESS" and resource.get("type") == "financial_record":
                access_counts[user_id] += 1

            if action == "GRANT" and metadata.get("granted_by") == "admin_007":
                granted_by_admin_007[user_id] = True

    expected_results = []
    for user_id, count in access_counts.items():
        if count >= 3:
            expected_results.append({
                "user_id": user_id,
                "access_count": count,
                "granted_by_admin_007": granted_by_admin_007[user_id]
            })

    # Sort: access_count descending, user_id ascending
    expected_results.sort(key=lambda x: (-x["access_count"], x["user_id"]))

    expected_output = {"results": expected_results}

    # Read the actual output
    with open(output_file, 'r') as f:
        try:
            actual_output = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse {output_file} as JSON: {e}")

    # Validate structure
    assert isinstance(actual_output, dict), f"Output JSON must be a dictionary, got {type(actual_output).__name__}."
    assert "results" in actual_output, "Output JSON is missing the 'results' key."
    assert isinstance(actual_output["results"], list), f"'results' should be a list, got {type(actual_output['results']).__name__}."

    # Validate content and order
    actual_results = actual_output["results"]
    assert len(actual_results) == len(expected_results), (
        f"Expected {len(expected_results)} users in results, got {len(actual_results)}."
    )

    for i, (actual, expected) in enumerate(zip(actual_results, expected_results)):
        assert actual.get("user_id") == expected["user_id"], (
            f"Result at index {i}: Expected user_id '{expected['user_id']}', got '{actual.get('user_id')}'."
        )
        assert actual.get("access_count") == expected["access_count"], (
            f"Result at index {i} for user {expected['user_id']}: Expected access_count {expected['access_count']}, got {actual.get('access_count')}."
        )
        assert actual.get("granted_by_admin_007") == expected["granted_by_admin_007"], (
            f"Result at index {i} for user {expected['user_id']}: Expected granted_by_admin_007 {expected['granted_by_admin_007']}, got {actual.get('granted_by_admin_007')}."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

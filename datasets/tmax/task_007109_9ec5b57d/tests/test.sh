#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_exploit_file_exists():
    """
    Validates that the student created the Go exploit program at the required path.
    """
    exploit_file = "/home/user/exploit.go"
    assert os.path.isfile(exploit_file), f"The exploit Go program is missing at {exploit_file}."

def test_redacted_dump_exists():
    """
    Validates that the output JSON file was generated at the correct path.
    """
    dump_file = "/home/user/redacted_dump.json"
    assert os.path.isfile(dump_file), f"The expected output file is missing at {dump_file}."

def test_redacted_dump_content():
    """
    Validates the parsed content of the redacted dump JSON file.
    It checks if the JWT exploit succeeded in extracting the data and if
    the redaction logic was correctly applied to the credit card fields.
    """
    dump_file = "/home/user/redacted_dump.json"

    with open(dump_file, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {dump_file} does not contain valid JSON.")

    assert isinstance(data, list), f"The JSON root in {dump_file} must be an array."
    assert len(data) == 3, f"Expected 3 user records in {dump_file}, but found {len(data)}."

    # Expected data derived from the mock server setup
    expected_users = {
        1: {"name": "Alice Smith", "email": "alice@example.com", "cc_last4": "4444"},
        2: {"name": "Bob Jones", "email": "bob@example.com", "cc_last4": "1234"},
        3: {"name": "Charlie Brown", "email": "charlie@example.com", "cc_last4": "5678"},
    }

    found_ids = set()

    for record in data:
        assert "id" in record, "A user record is missing the 'id' field."
        user_id = record["id"]
        assert user_id in expected_users, f"Found unexpected user ID {user_id} in the output."

        expected = expected_users[user_id]

        assert record.get("name") == expected["name"], f"Name mismatch for user ID {user_id}."
        assert record.get("email") == expected["email"], f"Email mismatch for user ID {user_id}."

        cc = record.get("credit_card", "")
        assert cc.startswith("************"), f"Credit card for user ID {user_id} is not properly redacted (missing asterisks)."
        assert cc.endswith(expected["cc_last4"]), f"Credit card for user ID {user_id} does not end with the correct last 4 digits."
        assert len(cc) == 16, f"Redacted credit card for user ID {user_id} should be exactly 16 characters long."

        found_ids.add(user_id)

    assert len(found_ids) == 3, "Not all expected user records were present in the output."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import pytest

OUTPUT_PATH = "/home/user/migrated_api.json"

# Derived from the immutable database contents created by setup. Do not recompute
# this value from the agent-writable database during verification.
EXPECTED_JSON = [
    {
        "id": 4,
        "path": "/api/comments",
        "js_validator": "req => req.param.length > 0 && req.param.length < 500",
    },
    {
        "id": 1,
        "path": "/api/users",
        "js_validator": 'req => req.header.auth === "valid"',
    },
    {
        "id": 2,
        "path": "/api/users/admin",
        "js_validator": 'req => req.param.role === "admin" && req.header.auth === "valid"',
    },
    {
        "id": 3,
        "path": "/api/posts",
        "js_validator": 'req => req.param.draft === "false" || req.header.auth === "valid"',
    },
]


def test_migrated_api_json_exists():
    assert os.path.exists(OUTPUT_PATH), f"Output file {OUTPUT_PATH} does not exist."
    assert os.path.isfile(OUTPUT_PATH), f"{OUTPUT_PATH} is not a file."


def test_migrated_api_json_content():
    with open(OUTPUT_PATH, "r") as f:
        try:
            actual_json = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse {OUTPUT_PATH} as JSON: {e}")

    assert isinstance(actual_json, list), "The JSON output must be a list of route objects."
    assert len(actual_json) == len(EXPECTED_JSON), (
        f"Expected {len(EXPECTED_JSON)} routes, but got {len(actual_json)}."
    )

    for i, (actual, expected) in enumerate(zip(actual_json, EXPECTED_JSON)):
        assert isinstance(actual, dict), f"Item at index {i} is not a JSON object."
        assert actual.get("id") == expected["id"], (
            f"Route at index {i} has incorrect id. Expected {expected['id']}, "
            f"got {actual.get('id')}."
        )
        assert actual.get("path") == expected["path"], (
            f"Route at index {i} has incorrect path. Expected {expected['path']}, "
            f"got {actual.get('path')}."
        )
        assert actual.get("js_validator") == expected["js_validator"], (
            f"Route at index {i} has incorrect js_validator. "
            f"Expected {expected['js_validator']}, got {actual.get('js_validator')}."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

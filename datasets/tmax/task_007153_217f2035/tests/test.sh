#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json

def test_output_json_exists():
    file_path = '/home/user/output.json'
    assert os.path.isfile(file_path), f"The file {file_path} does not exist."

def test_output_json_content():
    file_path = '/home/user/output.json'

    with open(file_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{file_path} is not a valid JSON file."

    assert isinstance(data, list), "The JSON root should be an array (list)."
    assert len(data) == 3, f"Expected exactly 3 items in the JSON array, found {len(data)}."

    expected_data = [
        {"username": "aaron", "friend_count": 4},
        {"username": "bob", "friend_count": 4},
        {"username": "charlie", "friend_count": 2}
    ]

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert isinstance(actual, dict), f"Item at index {i} is not a JSON object."
        assert actual.get("username") == expected["username"], f"Expected username '{expected['username']}' at index {i}, got '{actual.get('username')}'."
        assert actual.get("friend_count") == expected["friend_count"], f"Expected friend_count {expected['friend_count']} for user '{expected['username']}', got {actual.get('friend_count')}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

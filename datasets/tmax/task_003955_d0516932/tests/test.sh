#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json

def test_processed_data_exists():
    file_path = '/home/user/processed_data.jsonl'
    assert os.path.isfile(file_path), f"Expected output file {file_path} does not exist."

def test_processed_data_content():
    file_path = '/home/user/processed_data.jsonl'
    assert os.path.isfile(file_path), f"Expected output file {file_path} does not exist."

    expected = [
        {"id": 1, "age": 25, "status": "ACTIVE", "log_tokens": 2},
        {"id": 4, "age": 45, "status": "INACTIVE", "log_tokens": 4},
        {"id": 6, "age": 22, "status": "ACTIVE", "log_tokens": 5},
        {"id": 8, "age": 28, "status": "ACTIVE", "log_tokens": 5}
    ]

    actual = []
    with open(file_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            try:
                actual.append(json.loads(line))
            except json.JSONDecodeError:
                assert False, f"Line in {file_path} is not valid JSON: {line}"

    assert len(actual) == len(expected), f"Expected {len(expected)} lines in {file_path}, but got {len(actual)}."

    for i, (act, exp) in enumerate(zip(actual, expected)):
        assert act == exp, f"Line {i+1} mismatch. Expected {exp}, but got {act}."

def test_processed_data_sorting():
    file_path = '/home/user/processed_data.jsonl'
    if not os.path.isfile(file_path):
        return # Handled by previous test

    ids = []
    with open(file_path, 'r') as f:
        for line in f:
            if line.strip():
                data = json.loads(line)
                ids.append(data.get("id"))

    assert ids == sorted(ids), "The output lines are not sorted by 'id' in ascending order."

def test_processed_data_types():
    file_path = '/home/user/processed_data.jsonl'
    if not os.path.isfile(file_path):
        return # Handled by previous test

    with open(file_path, 'r') as f:
        for line in f:
            if line.strip():
                data = json.loads(line)
                assert isinstance(data.get("id"), int), f"'id' must be an integer, got {type(data.get('id'))}"
                assert isinstance(data.get("age"), int), f"'age' must be an integer, got {type(data.get('age'))}"
                assert isinstance(data.get("status"), str), f"'status' must be a string, got {type(data.get('status'))}"
                assert isinstance(data.get("log_tokens"), int), f"'log_tokens' must be an integer, got {type(data.get('log_tokens'))}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

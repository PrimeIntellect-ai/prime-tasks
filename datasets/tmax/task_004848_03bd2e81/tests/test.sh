#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_shortest_path_file_exists():
    file_path = "/home/user/shortest_path.json"
    assert os.path.exists(file_path), f"Output file does not exist: {file_path}"
    assert os.path.isfile(file_path), f"Output is not a file: {file_path}"

def test_shortest_path_file_content():
    file_path = "/home/user/shortest_path.json"
    assert os.path.exists(file_path), f"Output file does not exist: {file_path}"

    with open(file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} is not valid JSON.")

    assert isinstance(data, dict), f"Expected {file_path} to contain a JSON object."

    expected_keys = {"source", "target", "path", "distance"}
    assert set(data.keys()) == expected_keys, f"Keys in {file_path} do not match exactly. Expected {expected_keys}, got {set(data.keys())}"

    assert data["source"] == "MAPK1", f"Expected source to be 'MAPK1', got '{data['source']}'"
    assert data["target"] == "TP53", f"Expected target to be 'TP53', got '{data['target']}'"

    expected_path = ["MAPK1", "MEK1", "ERK2", "TP53"]
    assert data["path"] == expected_path, f"Expected path to be {expected_path}, got {data['path']}"

    assert data["distance"] == 3, f"Expected distance to be 3, got {data['distance']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

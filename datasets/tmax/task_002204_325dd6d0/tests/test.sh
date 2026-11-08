#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import numpy as np
import pytest


def test_process_go_exists():
    path = "/home/user/process.go"
    assert os.path.isfile(path), f"File {path} does not exist. The Go program was not created."
    assert os.path.getsize(path) > 0, f"File {path} is empty."


def test_recommendations_json_exists():
    path = "/home/user/recommendations.json"
    assert os.path.isfile(path), f"File {path} does not exist. The Go program might not have been run or didn't output the file."
    assert os.path.getsize(path) > 0, f"File {path} is empty."


def test_recommendations_match_expected():
    actual_path = "/home/user/recommendations.json"
    assert os.path.isfile(actual_path), f"Actual output file {actual_path} is missing."

    embeddings = np.loadtxt("/home/user/embeddings.csv", delimiter=",")
    projection = np.loadtxt("/home/user/projection.csv", delimiter=",")
    reduced = np.dot(embeddings, projection)

    expected_data = {}
    for i in range(100):
        dists = np.linalg.norm(reduced - reduced[i], axis=1)
        closest = np.argsort(dists)
        expected_data[str(i)] = [int(x) for x in closest if x != i][:2]

    with open(actual_path, 'r') as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {actual_path} does not contain valid JSON.")

    assert isinstance(actual_data, dict), "The output JSON should be an object (dictionary)."
    assert len(actual_data) == 100, f"Expected 100 keys in the output, got {len(actual_data)}."

    for key, expected_val in expected_data.items():
        assert key in actual_data, f"Key '{key}' is missing from the output."
        actual_val = actual_data[key]
        assert isinstance(actual_val, list), f"Value for key '{key}' should be a list, got {type(actual_val)}."
        assert len(actual_val) == 2, f"Expected 2 recommendations for key '{key}', got {len(actual_val)}."
        assert actual_val == expected_val, f"Recommendations for key '{key}' do not match. Expected {expected_val}, got {actual_val}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

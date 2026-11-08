#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_co_purchase_graph_json():
    json_path = "/home/user/co_purchase_graph.json"

    assert os.path.exists(json_path), f"File {json_path} does not exist. The task is incomplete."
    assert os.path.isfile(json_path), f"Path {json_path} is not a file."

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse {json_path} as valid JSON: {e}")

    expected_data = [
        {"source": "u1", "target": "u2", "weight": 2},
        {"source": "u1", "target": "u4", "weight": 2},
        {"source": "u2", "target": "u4", "weight": 2},
        {"source": "u3", "target": "u4", "weight": 2}
    ]

    assert isinstance(data, list), f"Expected JSON root to be a list, got {type(data).__name__}."
    assert data == expected_data, f"JSON content in {json_path} does not match the expected co-purchase graph."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

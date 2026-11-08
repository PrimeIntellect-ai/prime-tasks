#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_audit_results_exists_and_content():
    file_path = "/home/user/audit_results.json"
    assert os.path.exists(file_path), f"Output file {file_path} was not created."

    with open(file_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} does not contain valid JSON.")

    assert isinstance(data, list), "The output JSON should be a list of objects."
    assert len(data) == 3, f"Expected exactly 3 results, got {len(data)}."

    expected_data = [
        {"system": "AuthService", "centrality": 0.1648},
        {"system": "DatabaseMain", "centrality": 0.1154},
        {"system": "GatewayA", "centrality": 0.0659}
    ]

    for i, expected_item in enumerate(expected_data):
        actual_item = data[i]
        assert "system" in actual_item, f"Result at index {i} is missing 'system' key."
        assert "centrality" in actual_item, f"Result at index {i} is missing 'centrality' key."

        assert actual_item["system"] == expected_item["system"], \
            f"Expected system '{expected_item['system']}' at index {i}, got '{actual_item['system']}'."

        assert isinstance(actual_item["centrality"], (int, float)), \
            f"Centrality at index {i} should be a number."

        assert round(actual_item["centrality"], 4) == expected_item["centrality"], \
            f"Expected centrality {expected_item['centrality']} for system '{expected_item['system']}', got {actual_item['centrality']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

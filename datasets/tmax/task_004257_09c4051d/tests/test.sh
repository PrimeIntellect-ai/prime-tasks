#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_summary_json_exists_and_metric():
    """Verify that the summary.json exists, has the correct schema, and meets the MSE threshold."""
    json_path = "/home/user/summary.json"
    assert os.path.exists(json_path), f"Output file {json_path} is missing."
    assert os.path.isfile(json_path), f"Path {json_path} is not a file."

    with open(json_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse {json_path} as JSON: {e}")

    assert "categories" in data, "The JSON object must contain a 'categories' key."
    assert isinstance(data["categories"], list), "'categories' must be a list."

    agent_data = {}
    for item in data["categories"]:
        assert "category_name" in item, "Each category item must have a 'category_name'."
        assert "total_sales" in item, "Each category item must have a 'total_sales'."
        assert isinstance(item["category_name"], str), "'category_name' must be a string."
        assert isinstance(item["total_sales"], (int, float)), "'total_sales' must be a number."
        agent_data[item["category_name"]] = float(item["total_sales"])

    reference = {
        "Electronics": 15420.50,
        "Apparel": 8390.25,
        "Home": 4500.00
    }

    mse = 0.0
    for cat, ref_val in reference.items():
        agent_val = agent_data.get(cat, 0.0)
        mse += (agent_val - ref_val) ** 2

    mse /= len(reference)

    threshold = 0.01
    assert mse <= threshold, f"MSE of total_sales is {mse:.4f}, which exceeds the threshold of {threshold}. Reference: {reference}, Agent: {agent_data}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

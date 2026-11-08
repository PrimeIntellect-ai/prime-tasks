#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_analyze_go_exists():
    file_path = "/home/user/analyze.go"
    assert os.path.isfile(file_path), f"File {file_path} is missing."

def test_results_json_exists():
    file_path = "/home/user/results.json"
    assert os.path.isfile(file_path), f"File {file_path} is missing. Did you run your Go program?"

def test_results_json_content():
    file_path = "/home/user/results.json"
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    with open(file_path, "r") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} does not contain valid JSON.")

    # Check shortest_path
    assert "shortest_path" in results, "Missing 'shortest_path' key in results.json"
    shortest_path = results["shortest_path"]
    assert "path" in shortest_path, "Missing 'path' key in shortest_path"
    assert "total_cost" in shortest_path, "Missing 'total_cost' key in shortest_path"

    expected_path = ["FactoryA", "WarehouseD", "StoreZ"]
    assert shortest_path["path"] == expected_path, f"Expected path {expected_path}, got {shortest_path['path']}"
    assert shortest_path["total_cost"] == 110, f"Expected total_cost 110, got {shortest_path['total_cost']}"

    # Check top_express_sources
    assert "top_express_sources" in results, "Missing 'top_express_sources' key in results.json"
    top_sources = results["top_express_sources"]
    assert isinstance(top_sources, list), "'top_express_sources' should be a list"
    assert len(top_sources) == 3, f"Expected 3 top express sources, got {len(top_sources)}"

    expected_sources = [
        {"source": "FactoryA", "avg_cost": 110, "total_capacity": 740},
        {"source": "WarehouseC", "avg_cost": 40, "total_capacity": 100},
        {"source": "WarehouseD", "avg_cost": 10, "total_capacity": 200}
    ]

    for i, expected in enumerate(expected_sources):
        actual = top_sources[i]
        assert actual.get("source") == expected["source"], f"Expected source {expected['source']} at index {i}, got {actual.get('source')}"
        assert float(actual.get("avg_cost", 0)) == float(expected["avg_cost"]), f"Expected avg_cost {expected['avg_cost']} for {expected['source']}, got {actual.get('avg_cost')}"
        assert actual.get("total_capacity") == expected["total_capacity"], f"Expected total_capacity {expected['total_capacity']} for {expected['source']}, got {actual.get('total_capacity')}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

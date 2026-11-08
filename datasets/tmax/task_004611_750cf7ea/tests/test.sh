#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import subprocess
import pytest

MANIFEST_PATH = "/home/user/release_manifest.json"
V1_PATH = "/home/user/project_v1/src/main.rs"
V2_PATH = "/home/user/project_v2/src/main.rs"
API_SPECS_PATH = "/home/user/project_v2/api_specs.txt"

def get_expected_data():
    # Calculate Risk Score using diff -u
    proc = subprocess.run(["diff", "-u", V1_PATH, V2_PATH], capture_output=True, text=True)
    diff_lines = proc.stdout.splitlines()

    added = 0
    deleted = 0

    # Skip the first two lines (--- and +++)
    for line in diff_lines[2:]:
        if line.startswith('+'):
            added += 1
        elif line.startswith('-'):
            deleted += 1

    risk_score = (added * 2) + (deleted * 3) + ((added * deleted) % 7)

    # Parse API specs
    rest_endpoints = []
    graphql_types = []

    with open(API_SPECS_PATH, 'r') as f:
        for line in f:
            parts = line.strip().split()
            if not parts:
                continue
            if parts[0] == "REST" and len(parts) >= 3:
                rest_endpoints.append(parts[2])
            elif parts[0] == "GRAPHQL" and len(parts) >= 3 and parts[1] == "type":
                graphql_types.append(parts[2])

    return {
        "risk_score": risk_score,
        "rest_endpoints": rest_endpoints,
        "graphql_types": graphql_types
    }

def test_manifest_exists():
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file {MANIFEST_PATH} is missing."

def test_manifest_is_valid_json():
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file {MANIFEST_PATH} is missing."
    with open(MANIFEST_PATH, 'r') as f:
        try:
            json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Manifest file is not valid JSON: {e}")

def test_manifest_content():
    assert os.path.isfile(MANIFEST_PATH), f"Manifest file {MANIFEST_PATH} is missing."

    with open(MANIFEST_PATH, 'r') as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Cannot parse JSON to check content.")

    expected_data = get_expected_data()

    assert "risk_score" in actual_data, "Missing 'risk_score' in manifest."
    assert actual_data["risk_score"] == expected_data["risk_score"], \
        f"Expected risk_score {expected_data['risk_score']}, but got {actual_data['risk_score']}."

    assert "rest_endpoints" in actual_data, "Missing 'rest_endpoints' in manifest."
    assert actual_data["rest_endpoints"] == expected_data["rest_endpoints"], \
        f"Expected rest_endpoints {expected_data['rest_endpoints']}, but got {actual_data['rest_endpoints']}."

    assert "graphql_types" in actual_data, "Missing 'graphql_types' in manifest."
    assert actual_data["graphql_types"] == expected_data["graphql_types"], \
        f"Expected graphql_types {expected_data['graphql_types']}, but got {actual_data['graphql_types']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

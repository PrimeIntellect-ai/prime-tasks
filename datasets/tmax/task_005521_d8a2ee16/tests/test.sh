#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import re
from collections import defaultdict
import pytest

def get_expected_top_services():
    """
    Parse the architecture.ttl file to compute the expected in-degree centrality.
    """
    file_path = "/home/user/architecture.ttl"
    if not os.path.exists(file_path):
        pytest.fail(f"Missing setup file: {file_path}")

    with open(file_path, 'r') as f:
        content = f.read()

    # Remove prefix declarations
    content = re.sub(r'@prefix.*?\.', '', content)

    in_degrees = defaultdict(int)

    # Simple TTL parser for the given format
    statements = content.split('.')
    for stmt in statements:
        stmt = stmt.strip()
        if not stmt:
            continue

        parts = stmt.split(';')
        subject = None
        for part in parts:
            tokens = part.split()
            if not tokens:
                continue

            if subject is None:
                subject = tokens[0]
                tokens = tokens[1:]

            for i in range(len(tokens) - 1):
                if tokens[i] == 'ex:dependsOn':
                    obj = tokens[i+1]
                    in_degrees[obj] += 1

    def to_uri(ex_name):
        return ex_name.replace('ex:', 'http://example.org/')

    results = [(to_uri(k), v) for k, v in in_degrees.items()]

    # Sort by in_degree (descending), then service_name (descending)
    results.sort(key=lambda x: (x[1], x[0]), reverse=True)

    return results[:3]

def test_critical_services_output():
    """
    Validates that the output JSON exists, is structurally correct, 
    and contains the exact expected top 3 services.
    """
    output_path = "/home/user/critical_services.json"

    assert os.path.exists(output_path), f"The output file {output_path} does not exist."
    assert os.path.isfile(output_path), f"The path {output_path} is not a file."

    with open(output_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {output_path} does not contain valid JSON.")

    assert "top_services" in data, "The JSON object must contain the key 'top_services'."
    top_services = data["top_services"]

    assert isinstance(top_services, list), "'top_services' must be an array."
    assert len(top_services) == 3, f"Expected exactly 3 top services, found {len(top_services)}."

    expected_top = get_expected_top_services()

    for i, (expected_uri, expected_count) in enumerate(expected_top):
        actual_service = top_services[i]

        assert "service_name" in actual_service, f"Service at index {i} is missing 'service_name'."
        assert "in_degree" in actual_service, f"Service at index {i} is missing 'in_degree'."

        actual_uri = actual_service["service_name"]
        actual_count = actual_service["in_degree"]

        assert actual_uri == expected_uri, (
            f"Rank {i+1} service name mismatch. "
            f"Expected '{expected_uri}', got '{actual_uri}'."
        )
        assert actual_count == expected_count, (
            f"Rank {i+1} in-degree mismatch for {expected_uri}. "
            f"Expected {expected_count}, got {actual_count}."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

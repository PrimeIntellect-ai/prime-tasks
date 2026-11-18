#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import urllib.request
import urllib.error
import pytest

def test_api_script_exists():
    assert os.path.isfile("/home/user/api.py"), "The script /home/user/api.py does not exist."

def test_api_manifest_endpoint():
    url = "http://localhost:8123/manifest"
    try:
        req = urllib.request.Request(url, method="GET")
        with urllib.request.urlopen(req, timeout=5) as response:
            assert response.status == 200, f"Expected status 200, got {response.status}"
            data = response.read().decode('utf-8')
    except urllib.error.URLError as e:
        pytest.fail(f"Failed to connect to API at {url}: {e}")

    try:
        json_data = json.loads(data)
    except json.JSONDecodeError:
        pytest.fail("The API response is not valid JSON.")

    assert "dependencies" in json_data, "The response JSON is missing the 'dependencies' key."

    deps = json_data["dependencies"]

    expected_deps = {
        "flask": "1.1.2",
        "numpy": "1.20.1",
        "pandas": "1.2.0",
        "pyyaml": "5.3",
        "requests": "2.26.0"
    }

    assert deps == expected_deps, f"The merged dependencies do not match the expected output. Got: {deps}"

    # Verify that the dictionary is sorted alphabetically by keys (in Python 3.7+ dicts preserve insertion order)
    # The task requires "Sort the final consolidated dependencies alphabetically by package name."
    # Since JSON objects are unordered in theory, but in practice the order of keys in the string matters if we check the raw string,
    # or we can check the order of keys in the loaded dict since json.loads preserves order.
    keys = list(deps.keys())
    assert keys == sorted(keys), "The dependencies in the JSON response are not sorted alphabetically."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

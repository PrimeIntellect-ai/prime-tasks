#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_loop_artifacts_json_exists_and_correct():
    file_path = "/home/user/loop_artifacts.json"

    assert os.path.exists(file_path), f"The file {file_path} is missing. Did you save the output?"
    assert os.path.isfile(file_path), f"The path {file_path} is not a file."

    try:
        with open(file_path, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {file_path} does not contain valid JSON.")

    assert isinstance(data, list), f"The JSON in {file_path} must be an array (list)."

    expected_artifacts = [
        "app-server",
        "core-lib",
        "db-connector",
        "logger-lib",
        "orm-fw",
        "utils-lib",
        "web-lib"
    ]

    assert data == expected_artifacts, (
        f"The contents of {file_path} do not match the expected list of artifacts in a loop. "
        f"Expected: {expected_artifacts}, but got: {data}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

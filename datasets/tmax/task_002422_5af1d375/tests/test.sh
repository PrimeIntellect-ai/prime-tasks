#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import pytest

def test_exported_symbols_json_exists_and_correct():
    json_path = "/home/user/exported_symbols.json"
    assert os.path.exists(json_path), f"File {json_path} is missing. Did you save the output?"

    try:
        with open(json_path, "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {json_path} is not a valid JSON file.")

    assert isinstance(data, list), f"Expected a JSON array, but got {type(data).__name__}."

    expected_symbols = [
        "cleanup_system",
        "init_system",
        "load_config",
        "parse_args",
        "run_worker"
    ]

    assert data == expected_symbols, f"The exported symbols do not match the expected output. Got: {data}"

def test_patch_applied():
    v1_path = "/home/user/v1.sym"
    v2_path = "/home/user/v2.sym"

    # The user might have patched v1.sym in place or created v2.sym.
    # We check if at least one of them contains the patched content.
    patched_content = [
        "DEF init_system",
        "DEF load_config",
        "DEF start_worker",
        "ALIAS run_worker start_worker",
        "DEF cleanup_system",
        "DEF parse_args",
        "DROP start_worker"
    ]

    found_patched = False
    for path in [v1_path, v2_path]:
        if os.path.exists(path):
            with open(path, "r") as f:
                content = [line.strip() for line in f.readlines() if line.strip()]
            if content == patched_content:
                found_patched = True
                break

    assert found_patched, "Neither v1.sym nor v2.sym contains the correctly patched script."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

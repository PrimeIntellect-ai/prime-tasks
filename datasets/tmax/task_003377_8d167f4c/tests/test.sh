#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import pytest

OUTPUT_DIR = "/home/user/output"
OUTPUT_FILE = "/home/user/output/clean_configs.json"

def test_output_directory_exists():
    assert os.path.isdir(OUTPUT_DIR), f"Output directory {OUTPUT_DIR} was not created."

def test_output_file_exists():
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} is missing."

def test_output_json_content_and_structure():
    with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{OUTPUT_FILE} does not contain valid JSON.")

    assert isinstance(data, list), "The JSON output should be a list of objects."

    expected_data = [
        {
            "timestamp": "2023-11-02 08:30:00",
            "server_id": "Srv-Alpha",
            "ip_address": "10.0.0.1",
            "package": "nginx",
            "version": "v1.18.0"
        },
        {
            "timestamp": "2023-11-02 08:45:12",
            "server_id": "Srv-Beta",
            "ip_address": "10.0.0.2",
            "package": "postgresql",
            "version": "v13.4"
        },
        {
            "timestamp": "2023-11-02 08:45:12",
            "server_id": "Srv-Gamma",
            "ip_address": "10.0.1.5",
            "package": "openssl",
            "version": "v1.1.1k"
        },
        {
            "timestamp": "2023-11-02 09:10:00",
            "server_id": "Srv-Alpha",
            "ip_address": "10.0.0.1",
            "package": "python3",
            "version": "v3.9.7"
        },
        {
            "timestamp": "2023-11-02 09:10:00",
            "server_id": "Srv-Gamma",
            "ip_address": "10.0.1.5",
            "package": "openssl",
            "version": "v1.1.1k"
        },
        {
            "timestamp": "2023-11-02 09:20:00",
            "server_id": "Srv-Alpha",
            "ip_address": "10.0.0.1",
            "package": "htop",
            "version": "v3.0.5"
        },
        {
            "timestamp": "2023-11-02 09:20:00",
            "server_id": "Srv-Delta",
            "ip_address": "10.0.2.10",
            "package": "redis",
            "version": "v6.2.5"
        }
    ]

    assert len(data) == len(expected_data), f"Expected {len(expected_data)} records, but got {len(data)}. Ensure duplicates and missing servers are dropped."

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert actual == expected, f"Record at index {i} does not match expected output.\nExpected: {expected}\nGot: {actual}"

def test_output_json_formatting():
    with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
        content = f.read()

    # With indent=2, array elements are indented two spaces and their keys four.
    lines = content.splitlines()
    has_two_space_element_indent = any(
        line.startswith("  {") and not line.startswith("   {") for line in lines
    )
    has_four_space_key_indent = any(
        line.startswith("    \"") and not line.startswith("     \"") for line in lines
    )
    assert has_two_space_element_indent and has_four_space_key_indent, \
        "The JSON file does not appear to be pretty-printed with a 2-space indent."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

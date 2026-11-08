#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import struct
import pytest

def parse_config(filepath):
    data = {}
    with open(filepath, 'rb') as f:
        magic_version = f.read(5)
        if magic_version != b'CONF\x01':
            raise ValueError(f"Invalid magic/version in {filepath}")

        count_bytes = f.read(2)
        if not count_bytes:
            return data
        count = struct.unpack('<H', count_bytes)[0]

        for _ in range(count):
            key_len_bytes = f.read(1)
            if not key_len_bytes:
                break
            key_len = struct.unpack('B', key_len_bytes)[0]
            key = f.read(key_len).decode('ascii')

            val_type = struct.unpack('B', f.read(1))[0]
            if val_type == 1:
                val = struct.unpack('<i', f.read(4))[0]
            elif val_type == 2:
                val_len = struct.unpack('<H', f.read(2))[0]
                val = f.read(val_len).decode('ascii')
            else:
                raise ValueError(f"Invalid value type {val_type} in {filepath}")
            data[key] = val
    return data

def generate_expected_diff(v1_data, v2_data):
    diff = {}
    for k, v in v1_data.items():
        if k in v2_data:
            if v != v2_data[k]:
                diff[k] = {
                    "status": "modified",
                    "old_value": v,
                    "new_value": v2_data[k]
                }
        else:
            diff[k] = {
                "status": "removed",
                "old_value": v,
                "new_value": None
            }

    for k, v in v2_data.items():
        if k not in v1_data:
            diff[k] = {
                "status": "added",
                "old_value": None,
                "new_value": v
            }

    return diff

def test_diff_json_exists():
    diff_path = '/home/user/diff.json'
    assert os.path.isfile(diff_path), f"Expected output file {diff_path} is missing."

def test_diff_json_content():
    diff_path = '/home/user/diff.json'
    assert os.path.isfile(diff_path), f"Cannot verify content because {diff_path} is missing."

    try:
        with open(diff_path, 'r') as f:
            actual_diff = json.load(f)
    except json.JSONDecodeError as e:
        pytest.fail(f"Failed to parse {diff_path} as JSON: {e}")

    v1_data = parse_config('/home/user/config_v1.bin')
    v2_data = parse_config('/home/user/config_v2.bin')

    expected_diff = generate_expected_diff(v1_data, v2_data)

    assert actual_diff == expected_diff, f"The contents of {diff_path} do not match the expected differences. Expected: {expected_diff}, but got: {actual_diff}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

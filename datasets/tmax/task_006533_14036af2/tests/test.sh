#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import re
import pytest

def parse_and_normalize(filepath):
    config = {}
    if not os.path.exists(filepath):
        return config

    with open(filepath, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            # Match: SERVICE[<service>] param:<key> | val:<value> [// notes]
            # The value part might have trailing spaces before the //
            m = re.match(r'^SERVICE\[(.*?)\]\s+param:(.*?)\s+\|\s+val:(.*?)(?:\s*//.*)?$', line)
            if m:
                service = m.group(1)
                key = m.group(2)
                val = m.group(3).strip()

                # 1. Strip surrounding quotes
                if val.startswith('"') and val.endswith('"') and len(val) >= 2:
                    val = val[1:-1]

                # 2. Lowercase
                val = val.lower()

                # 3. Replace hyphens and underscores with spaces
                val = val.replace('-', ' ').replace('_', ' ')

                # 4. Collapse multiple spaces
                val = re.sub(r'\s+', ' ', val)

                # 5. Trim leading and trailing spaces
                val = val.strip()

                if service not in config:
                    config[service] = {}
                config[service][key] = val

    return config

def get_expected_diff(old_config, new_config):
    diff = {}
    all_services = set(old_config.keys()).union(set(new_config.keys()))

    for service in all_services:
        old_keys = old_config.get(service, {})
        new_keys = new_config.get(service, {})
        all_keys = set(old_keys.keys()).union(set(new_keys.keys()))

        for key in all_keys:
            old_val = old_keys.get(key)
            new_val = new_keys.get(key)

            status = None
            if old_val is None and new_val is not None:
                status = "added"
            elif old_val is not None and new_val is None:
                status = "removed"
            elif old_val != new_val:
                status = "modified"

            if status:
                if service not in diff:
                    diff[service] = {}
                diff[service][key] = {
                    "status": status,
                    "old_value": old_val,
                    "new_value": new_val
                }

    return diff

def test_config_diff_json():
    old_state_path = '/home/user/old_state.txt'
    new_state_path = '/home/user/new_state.txt'
    output_path = '/home/user/config_diff.json'

    assert os.path.exists(output_path), f"Output file {output_path} does not exist."

    try:
        with open(output_path, 'r') as f:
            actual_diff = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {output_path} does not contain valid JSON.")

    old_config = parse_and_normalize(old_state_path)
    new_config = parse_and_normalize(new_state_path)
    expected_diff = get_expected_diff(old_config, new_config)

    assert actual_diff == expected_diff, f"The contents of {output_path} do not match the expected configuration differences."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

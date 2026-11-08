#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv

def test_latest_config_exists():
    """Test that the output file exists."""
    output_path = "/home/user/latest_config.csv"
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."

def test_latest_config_content():
    """Test that the output file contains the correct latest configurations."""
    input_path = "/home/user/etl_config_events.csv"
    output_path = "/home/user/latest_config.csv"

    assert os.path.isfile(input_path), f"Input file {input_path} is missing."
    assert os.path.isfile(output_path), f"Output file {output_path} is missing."

    # Compute expected output
    latest_configs = {}
    with open(input_path, 'r', encoding='utf-8') as f:
        reader = csv.reader(f)
        for row in reader:
            if len(row) != 4:
                continue
            timestamp_str, component_name, config_hash, status = row
            if status == "SUCCESS":
                timestamp = int(timestamp_str)
                if component_name not in latest_configs or timestamp > latest_configs[component_name]['timestamp']:
                    latest_configs[component_name] = {
                        'timestamp': timestamp,
                        'config_hash': config_hash
                    }

    expected_lines = []
    for comp in sorted(latest_configs.keys()):
        expected_lines.append(f"{comp},{latest_configs[comp]['config_hash']}")

    # Read actual output
    with open(output_path, 'r', encoding='utf-8') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, (
        f"Output file content does not match expected.\n"
        f"Expected: {expected_lines}\n"
        f"Actual: {actual_lines}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

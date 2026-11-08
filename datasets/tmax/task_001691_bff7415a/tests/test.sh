#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import xml.etree.ElementTree as ET
import csv
from collections import defaultdict

def normalize(key):
    return key.strip().lower().replace('.', '_')

def get_json_keys(data, prefix=''):
    keys = []
    if isinstance(data, dict):
        for k, v in data.items():
            new_prefix = f"{prefix}.{k}" if prefix else k
            keys.extend(get_json_keys(v, new_prefix))
    elif isinstance(data, list):
        for i, v in enumerate(data):
            new_prefix = f"{prefix}.{i}" if prefix else str(i)
            keys.extend(get_json_keys(v, new_prefix))
    else:
        keys.append(prefix)
    return keys

def get_xml_keys(element, prefix=''):
    keys = []
    new_prefix = f"{prefix}.{element.tag}" if prefix else element.tag
    if len(element) == 0:
        keys.append(new_prefix)
    else:
        for child in element:
            keys.extend(get_xml_keys(child, new_prefix))
    return keys

def get_csv_keys(filepath):
    keys = []
    with open(filepath, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            if 'key' in row:
                keys.append(row['key'])
    return keys

def get_active_keys():
    active_keys = set()

    # JSON
    json_path = "/home/user/configs/settings.json"
    if os.path.exists(json_path):
        with open(json_path, 'r') as f:
            data = json.load(f)
            for k in get_json_keys(data):
                active_keys.add(normalize(k))

    # XML
    xml_path = "/home/user/configs/system.xml"
    if os.path.exists(xml_path):
        tree = ET.parse(xml_path)
        # The task example implies the root node is included in the path, e.g. system.network.timeout
        for k in get_xml_keys(tree.getroot()):
            active_keys.add(normalize(k))

    # CSV
    csv_path = "/home/user/configs/env.csv"
    if os.path.exists(csv_path):
        for k in get_csv_keys(csv_path):
            active_keys.add(normalize(k))

    return active_keys

def get_expected_aggregation(active_keys):
    counts = defaultdict(lambda: defaultdict(int))
    log_path = '/home/user/data/history.log'
    if not os.path.exists(log_path):
        return {}

    with open(log_path, 'r') as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) >= 5:
                date = parts[0]
                month = date[:7]
                raw_key = parts[3].strip('[]')
                action = parts[4].strip('[]')

                if action == 'UPDATE':
                    norm_key = normalize(raw_key)
                    if norm_key in active_keys:
                        counts[norm_key][month] += 1

    # Convert to standard dict for comparison
    expected = {}
    for k, v in counts.items():
        if v:
            expected[k] = dict(v)
    return expected

def test_output_file_exists():
    output_path = "/home/user/output/aggregated_changes.json"
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist. Did the script run successfully?"

def test_aggregated_changes_content():
    output_path = "/home/user/output/aggregated_changes.json"
    assert os.path.isfile(output_path), "Output file is missing."

    with open(output_path, 'r') as f:
        try:
            student_data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"{output_path} is not a valid JSON file."

    active_keys = get_active_keys()
    expected_data = get_expected_aggregation(active_keys)

    assert isinstance(student_data, dict), "The top-level JSON structure must be a dictionary."

    # Check if student data matches expected data
    assert student_data == expected_data, f"The aggregated changes do not match the expected output.\nExpected: {expected_data}\nGot: {student_data}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

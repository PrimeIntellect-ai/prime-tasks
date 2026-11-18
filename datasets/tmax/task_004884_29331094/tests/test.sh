#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import xml.etree.ElementTree as ET
import pytest

JSON_PATH = "/home/user/app_config/incoming/v2_update.json"
CSV_PATH = "/home/user/app_config/history/v2_update.csv"
SYMLINK_PATH = "/home/user/app_config/active/current.csv"
XML_PATH = "/home/user/app_config/deploy_log.xml"

def test_csv_file_created_and_content():
    assert os.path.isfile(CSV_PATH), f"CSV file {CSV_PATH} is missing."

    # Derive expected content from JSON
    assert os.path.isfile(JSON_PATH), f"Original JSON file {JSON_PATH} is missing."
    with open(JSON_PATH, 'r') as f:
        data = json.load(f)

    expected_lines = [f"{k},{data[k]}" for k in sorted(data.keys())]

    with open(CSV_PATH, 'r') as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]

    assert actual_lines == expected_lines, f"CSV content in {CSV_PATH} does not match expected sorted key-value pairs."

def test_symlink_created_and_target():
    assert os.path.islink(SYMLINK_PATH), f"Symlink {SYMLINK_PATH} is missing or is not a symlink."
    target = os.readlink(SYMLINK_PATH)
    assert target == CSV_PATH, f"Symlink {SYMLINK_PATH} points to {target}, expected {CSV_PATH}."

def test_xml_log_file_created_and_content():
    assert os.path.isfile(XML_PATH), f"XML log file {XML_PATH} is missing."

    with open(JSON_PATH, 'r') as f:
        data = json.load(f)
    num_keys = len(data)

    try:
        tree = ET.parse(XML_PATH)
        root = tree.getroot()
    except ET.ParseError:
        pytest.fail(f"File {XML_PATH} does not contain valid XML.")

    assert root.tag == "deployment", f"XML root tag is {root.tag}, expected 'deployment'."

    version_elem = root.find("version")
    assert version_elem is not None, "XML is missing <version> element."
    assert version_elem.text.strip() == "v2_update", f"XML <version> text is {version_elem.text}, expected 'v2_update'."

    keys_elem = root.find("keys")
    assert keys_elem is not None, "XML is missing <keys> element."
    assert keys_elem.text.strip() == str(num_keys), f"XML <keys> text is {keys_elem.text}, expected '{num_keys}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

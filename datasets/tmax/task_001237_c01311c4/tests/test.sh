#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

def test_output_file_exists():
    assert os.path.isfile("/home/user/output/tech_summary.json"), "The output file /home/user/output/tech_summary.json is missing."

def test_output_json_content():
    try:
        with open("/home/user/output/tech_summary.json", "r") as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail("The output file /home/user/output/tech_summary.json is not valid JSON.")

    assert isinstance(data, list), "The JSON root must be an array."

    expected_data = [
        {
            "company_name": "DataWorks",
            "tech_list": [
                "MongoDB",
                "Redis"
            ],
            "total_techs": 2
        },
        {
            "company_name": "TechCorp",
            "tech_list": [
                "PostgreSQL",
                "React"
            ],
            "total_techs": 2
        }
    ]

    # Check length
    assert len(data) == len(expected_data), f"Expected {len(expected_data)} companies in the output, but found {len(data)}."

    # Check sorting by company_name
    company_names = [item.get("company_name") for item in data]
    assert company_names == sorted(company_names), "The JSON array must be sorted alphabetically by company_name."

    # Check individual records
    for actual, expected in zip(data, expected_data):
        assert actual.get("company_name") == expected["company_name"], f"Expected company name {expected['company_name']}, got {actual.get('company_name')}."
        assert actual.get("total_techs") == expected["total_techs"], f"Expected total_techs {expected['total_techs']} for {expected['company_name']}, got {actual.get('total_techs')}."

        actual_tech_list = actual.get("tech_list", [])
        assert isinstance(actual_tech_list, list), f"tech_list for {expected['company_name']} must be an array."
        assert actual_tech_list == sorted(actual_tech_list), f"tech_list for {expected['company_name']} must be sorted alphabetically."
        assert actual_tech_list == expected["tech_list"], f"Expected tech_list {expected['tech_list']} for {expected['company_name']}, got {actual_tech_list}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

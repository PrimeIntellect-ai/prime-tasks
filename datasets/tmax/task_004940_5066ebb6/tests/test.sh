#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_report_exists():
    report_path = "/home/user/report.txt"
    assert os.path.isfile(report_path), f"The file {report_path} does not exist."

def test_report_contents():
    report_path = "/home/user/report.txt"
    secret_file = "/tests/.secret_bad_commit"

    assert os.path.isfile(report_path), f"Cannot test contents, {report_path} is missing."
    assert os.path.isfile(secret_file), f"Test setup error: {secret_file} is missing."

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    report_dict = {}
    for line in lines:
        if "=" in line:
            key, val = line.split("=", 1)
            report_dict[key.strip()] = val.strip()

    assert "API_KEY" in report_dict, "API_KEY is missing from report.txt."
    expected_api_key = "AKIA-TREASURE-778899"
    assert report_dict["API_KEY"] == expected_api_key, f"Incorrect API_KEY in report.txt. Expected {expected_api_key}, got {report_dict['API_KEY']}."

    assert "BAD_COMMIT" in report_dict, "BAD_COMMIT is missing from report.txt."

    with open(secret_file, "r") as f:
        expected_bad_commit = f.read().strip()

    assert report_dict["BAD_COMMIT"] == expected_bad_commit, f"Incorrect BAD_COMMIT in report.txt. Expected {expected_bad_commit}, got {report_dict['BAD_COMMIT']}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

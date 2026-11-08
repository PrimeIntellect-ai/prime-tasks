#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os


def test_etl_report_exists():
    """Test that the output file etl_report.csv exists."""
    file_path = "/home/user/etl_report.csv"
    assert os.path.isfile(file_path), f"The output file '{file_path}' is missing."
    assert os.path.getsize(file_path) > 0, f"The output file '{file_path}' is empty."


def test_etl_report_content():
    """Test that the output file etl_report.csv matches the expected truth."""
    report_path = "/home/user/etl_report.csv"
    truth_path = "/tests/.truth.csv"

    assert os.path.isfile(report_path), f"The output file '{report_path}' is missing."
    assert os.path.isfile(truth_path), f"The truth file '{truth_path}' is missing."

    with open(report_path, "r") as f:
        report_content = f.read().strip().replace(" ", "")

    with open(truth_path, "r") as f:
        truth_content = f.read().strip().replace(" ", "")

    assert report_content == truth_content, (
        f"The contents of '{report_path}' do not match the expected values.\n"
        f"Expected: {truth_content}\n"
        f"Got:      {report_content}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

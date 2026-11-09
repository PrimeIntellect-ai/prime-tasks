#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os

def test_final_report_exists_and_content_correct():
    report_path = '/home/user/final_report.md'
    assert os.path.isfile(report_path), f"The final report file {report_path} does not exist."

    with open(report_path, 'r') as f:
        content = f.read()

    expected_content = """# Sensor Report

## Sensor S1
Latest 3-point Rolling Avg: 12.0

## Sensor S2
Latest 3-point Rolling Avg: 7.0

## Sensor S3
Latest 3-point Rolling Avg: 16.0
"""

    assert content.strip() == expected_content.strip(), (
        f"The content of {report_path} does not match the expected output.\n"
        f"Expected:\n{expected_content}\n"
        f"Actual:\n{content}"
    )

def test_no_placeholders_left():
    report_path = '/home/user/final_report.md'
    if os.path.isfile(report_path):
        with open(report_path, 'r') as f:
            content = f.read()
        assert "{{" not in content and "}}" not in content, (
            "The final report still contains unreplaced placeholders."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

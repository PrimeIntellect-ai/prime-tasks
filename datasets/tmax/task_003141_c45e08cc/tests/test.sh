#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import pytest

EXPECTED_OUTPUT = """time,device,value,status,rolling_avg
101,TX1,10,OK,10.0
102,TX1,14,OK,12.0
103,TX2,20,HOT_°C,20.0
105,TX1,15,OK,13.0
106,TX1,19,HOT_°C,16.0
"""

def test_processed_file_exists():
    assert os.path.isfile("/home/user/processed.csv"), "The file /home/user/processed.csv does not exist."

def test_processed_file_content():
    filepath = "/home/user/processed.csv"

    try:
        with open(filepath, "rb") as f:
            raw_content = f.read()
            content = raw_content.decode("utf-8")
    except UnicodeDecodeError:
        pytest.fail("The file /home/user/processed.csv is not valid UTF-8.")

    # Normalize line endings for comparison
    actual_lines = [line.strip() for line in content.strip().splitlines()]
    expected_lines = [line.strip() for line in EXPECTED_OUTPUT.strip().splitlines()]

    assert actual_lines == expected_lines, (
        "The content of /home/user/processed.csv does not match the expected output.\n"
        f"Expected:\n{EXPECTED_OUTPUT}\n"
        f"Actual:\n{content}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

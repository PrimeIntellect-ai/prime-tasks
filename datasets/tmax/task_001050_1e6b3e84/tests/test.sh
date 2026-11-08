#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_report_exists():
    report_path = "/home/user/report.md"
    assert os.path.isfile(report_path), f"Error: The file {report_path} does not exist."

def test_report_content():
    report_path = "/home/user/report.md"

    expected_content = """# Category A
* c***@domain.org computed 21
* b***@test.com computed 18

# Category B
* f***@hello.net computed 30
* d***@xyz.com computed 25.0

# Category C
* g***@mail.com computed 25
* i***@mail.com computed 24"""

    with open(report_path, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, (
        f"Error: The content of {report_path} does not match the expected output.\n"
        f"Expected:\n{expected_content}\n\nActual:\n{actual_content}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

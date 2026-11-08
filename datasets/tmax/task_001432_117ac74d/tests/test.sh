#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import pytest

def test_report_csv_content():
    report_path = "/home/user/report.csv"
    assert os.path.isfile(report_path), f"Expected file {report_path} does not exist."

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) >= 3, "report.csv does not contain enough lines (header + 2 data rows expected)."
    assert lines[0] == "bucket,ERROR,WARNING", f"Incorrect header in report.csv: {lines[0]}"

    expected_rows = [
        "2023-10-12 10:00,2,1",
        "2023-10-12 10:15,0,1"
    ]

    assert lines[1] == expected_rows[0], f"Expected row 1 to be '{expected_rows[0]}', got '{lines[1]}'"
    assert lines[2] == expected_rows[1], f"Expected row 2 to be '{expected_rows[1]}', got '{lines[2]}'"

def test_cron_txt_content():
    cron_path = "/home/user/cron.txt"
    assert os.path.isfile(cron_path), f"Expected file {cron_path} does not exist."

    with open(cron_path, "r") as f:
        content = f.read().strip()

    # Match either '0 * * * * /home/user/process.sh' or '@hourly /home/user/process.sh'
    # with possible multiple spaces/tabs
    pattern = r"^(0\s+\*\s+\*\s+\*\s+\*|@hourly)\s+/home/user/process\.sh$"

    assert re.match(pattern, content), f"cron.txt does not contain a valid top-of-the-hour schedule for /home/user/process.sh. Got: '{content}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

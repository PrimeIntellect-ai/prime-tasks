#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

LOOPS_LOG_PATH = "/home/user/loops.log"
REPORT_CSV_PATH = "/home/user/report.csv"

def test_loops_log_exists_and_correct():
    assert os.path.isfile(LOOPS_LOG_PATH), f"File missing: {LOOPS_LOG_PATH}"

    with open(LOOPS_LOG_PATH, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_loops = [
        "/home/user/config_tree/links/loop1",
        "/home/user/config_tree/links/loop2a",
        "/home/user/config_tree/links/loop2b"
    ]

    assert lines == expected_loops, f"Contents of {LOOPS_LOG_PATH} do not match the expected sorted loop paths."

def test_report_csv_exists_and_correct():
    assert os.path.isfile(REPORT_CSV_PATH), f"File missing: {REPORT_CSV_PATH}"

    with open(REPORT_CSV_PATH, 'r', newline='') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, f"{REPORT_CSV_PATH} is empty."

    header = rows[0]
    expected_header = ["filepath", "type", "app_name", "version"]
    assert header == expected_header, f"Header of {REPORT_CSV_PATH} is incorrect. Expected {expected_header}, got {header}."

    data_rows = rows[1:]

    expected_data = [
        ["/home/user/config_tree/app1/lb.state", "BINARY", "LoadBalancer", "12"],
        ["/home/user/config_tree/app1/settings.conf", "TEXT", "NginxServer", "1.18.0"],
        ["/home/user/config_tree/app1/settings.conf", "TEXT", "NginxServer", "1.18.0"],
        ["/home/user/config_tree/app2/module/service.txt", "TEXT", "DatabaseWorker", "9.4"],
        ["/home/user/config_tree/legacy/cache.bin", "BINARY", "CacheNode", "3"]
    ]

    # Check that data rows match expected exactly (including sort order)
    assert data_rows == expected_data, f"Data rows in {REPORT_CSV_PATH} do not match expected output or are not sorted correctly."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

REPORT_PATH = "/home/user/report.txt"

def test_report_file_exists():
    assert os.path.isfile(REPORT_PATH), f"Report file {REPORT_PATH} is missing. The task requires creating this file."

def test_report_content_txn_id():
    with open(REPORT_PATH, "r") as f:
        content = f.read()

    expected_txn_line = "TXN_ID: TXN-9432"
    assert expected_txn_line in content, f"Report file does not contain the correct TXN_ID line. Expected to find '{expected_txn_line}'."

def test_report_content_wal_file():
    with open(REPORT_PATH, "r") as f:
        content = f.read()

    expected_wal_line = "WAL_FILE: /home/user/wal/wal_042.dat"
    assert expected_wal_line in content, f"Report file does not contain the correct WAL_FILE line. Expected to find '{expected_wal_line}'."

def test_report_exact_format():
    with open(REPORT_PATH, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    assert len(lines) >= 2, "Report file should contain at least two lines for TXN_ID and WAL_FILE."

    txn_found = False
    wal_found = False
    for line in lines:
        if line == "TXN_ID: TXN-9432":
            txn_found = True
        elif line == "WAL_FILE: /home/user/wal/wal_042.dat":
            wal_found = True

    assert txn_found, "The exact string 'TXN_ID: TXN-9432' was not found as a line in the report."
    assert wal_found, "The exact string 'WAL_FILE: /home/user/wal/wal_042.dat' was not found as a line in the report."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

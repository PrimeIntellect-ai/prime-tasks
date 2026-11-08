#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

def test_audit_report_exists():
    report_path = "/home/user/audit_report.csv"
    assert os.path.exists(report_path), f"Audit report not found at {report_path}"
    assert os.path.isfile(report_path), f"{report_path} is not a file"

def test_audit_report_content():
    report_path = "/home/user/audit_report.csv"

    expected_rows = [
        ["/home/user/app_configs/base.ini", "regular", "1.0.0"],
        ["/home/user/app_configs/serviceA/config.ini", "symlink", "1.0.0"],
        ["/home/user/app_configs/serviceB/config.ini", "hardlink", "1.1.5"],
        ["/home/user/app_configs/serviceC/broken.ini", "regular", "UNKNOWN"],
        ["/home/user/app_configs/serviceC/config.ini", "regular", "2.0-beta"],
        ["/home/user/app_configs/serviceD/nested/config.ini", "symlink", "1.1.5"],
        ["/home/user/app_configs/shared.ini", "hardlink", "1.1.5"]
    ]

    with open(report_path, "r", newline="") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "Audit report is empty"

    header = rows[0]
    assert header == ["FilePath", "LinkType", "Version"], f"Incorrect CSV header: {header}"

    data_rows = rows[1:]
    assert len(data_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows, but got {len(data_rows)}"

    for i, (expected, actual) in enumerate(zip(expected_rows, data_rows)):
        assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, got {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

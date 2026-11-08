#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import zipfile
import csv

def test_config_summary_zip_exists():
    zip_path = "/home/user/config_summary.zip"
    assert os.path.isfile(zip_path), f"Expected zip file '{zip_path}' does not exist."

def test_config_summary_zip_contents():
    zip_path = "/home/user/config_summary.zip"
    assert os.path.isfile(zip_path), f"Cannot check contents, '{zip_path}' is missing."

    with zipfile.ZipFile(zip_path, 'r') as zf:
        namelist = zf.namelist()
        assert "config_summary.csv" in namelist, "Zip archive does not contain 'config_summary.csv'."
        assert len(namelist) == 1, f"Zip archive should contain exactly one file without directory paths. Found: {namelist}"

def test_config_summary_csv_content():
    zip_path = "/home/user/config_summary.zip"
    assert os.path.isfile(zip_path), f"Cannot check CSV, '{zip_path}' is missing."

    expected_rows = [
        ["component", "key", "value"],
        ["cache", "backend", "redis"],
        ["cache", "port", "6379"],
        ["database", "host", "db-prod-1"],
        ["database", "port", "5432"]
    ]

    with zipfile.ZipFile(zip_path, 'r') as zf:
        with zf.open("config_summary.csv") as f:
            content = f.read().decode('utf-8').splitlines()

    reader = list(csv.reader(content))

    assert reader == expected_rows, f"CSV contents do not match expected rows. Found: {reader}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

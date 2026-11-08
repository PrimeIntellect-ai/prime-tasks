#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import filecmp
import pytest

def test_incoming_directory_copied():
    remote_dir = "/home/user/remote_configs"
    incoming_dir = "/home/user/incoming"

    assert os.path.isdir(incoming_dir), f"Directory {incoming_dir} does not exist. Files were not copied."

    remote_files = sorted(os.listdir(remote_dir))
    incoming_files = sorted(os.listdir(incoming_dir))

    assert remote_files == incoming_files, f"Files in {incoming_dir} do not match files in {remote_dir}."

    for filename in remote_files:
        remote_path = os.path.join(remote_dir, filename)
        incoming_path = os.path.join(incoming_dir, filename)
        assert filecmp.cmp(remote_path, incoming_path, shallow=False), f"File content of {filename} in {incoming_dir} does not match the remote original."

def test_config_drift_report_exists_and_correct():
    report_path = "/home/user/config_drift_report.csv"
    assert os.path.isfile(report_path), f"Report file {report_path} does not exist."

    local_dir = "/home/user/local_configs"
    incoming_dir = "/home/user/incoming"

    expected_rows = []

    # Recompute expected results based on the files
    app_files = sorted(os.listdir(local_dir))
    for filename in app_files:
        if not filename.endswith('.json'):
            continue
        app_name = filename[:-5]

        local_path = os.path.join(local_dir, filename)
        incoming_path = os.path.join(incoming_dir, filename)

        local_valid = True
        incoming_valid = True
        local_keys = set()
        incoming_keys = set()

        try:
            with open(local_path, 'r') as lf:
                local_data = json.load(lf)
                if isinstance(local_data, dict):
                    local_keys = set(local_data.keys())
        except Exception:
            local_valid = False

        try:
            with open(incoming_path, 'r') as inf:
                incoming_data = json.load(inf)
                if isinstance(incoming_data, dict):
                    incoming_keys = set(incoming_data.keys())
        except Exception:
            incoming_valid = False

        if not local_valid:
            status = "INVALID_LOCAL"
            score = "0.00"
        elif not incoming_valid:
            status = "INVALID_INCOMING"
            score = "0.00"
        else:
            status = "VALID"
            intersection = len(local_keys.intersection(incoming_keys))
            union = len(local_keys.union(incoming_keys))
            score_val = intersection / union if union > 0 else 0.0
            score = f"{score_val:.2f}"

        expected_rows.append([app_name, status, score])

    expected_rows.sort(key=lambda x: x[0])

    with open(report_path, 'r', newline='') as csvfile:
        reader = csv.reader(csvfile)
        rows = list(reader)

    assert len(rows) > 0, "CSV report is empty."
    assert rows[0] == ['app_name', 'status', 'similarity_score'], "CSV header is incorrect or missing."

    actual_data_rows = rows[1:]
    assert len(actual_data_rows) == len(expected_rows), f"Expected {len(expected_rows)} data rows, but found {len(actual_data_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_data_rows, expected_rows)):
        assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, got {actual}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

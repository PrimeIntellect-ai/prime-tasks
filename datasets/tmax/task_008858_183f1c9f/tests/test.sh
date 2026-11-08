#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import glob
import math
from collections import defaultdict

def test_pipeline_files_exist_and_executable():
    assert os.path.isfile("/home/user/run_pipeline.sh"), "run_pipeline.sh is missing"
    assert os.access("/home/user/run_pipeline.sh", os.X_OK), "run_pipeline.sh is not executable"

    assert os.path.isfile("/home/user/etl.c"), "etl.c is missing"
    assert os.path.isfile("/home/user/etl_processor"), "etl_processor is missing"
    assert os.access("/home/user/etl_processor", os.X_OK), "etl_processor is not executable"

def test_pipeline_success_file():
    success_file = "/home/user/output/pipeline.SUCCESS"
    assert os.path.isfile(success_file), f"{success_file} is missing"
    with open(success_file, "r") as f:
        content = f.read().strip()
    assert content == "PIPELINE_OK", f"Expected 'PIPELINE_OK' in {success_file}, got '{content}'"

def test_files_moved_to_incoming():
    remote_drop_csvs = glob.glob("/home/user/remote_drop/*.csv")
    assert len(remote_drop_csvs) == 0, "CSV files were not moved out of /home/user/remote_drop/"

    incoming_csvs = glob.glob("/home/user/incoming/*.csv")
    assert len(incoming_csvs) > 0, "No CSV files found in /home/user/incoming/"

def test_rolling_drift_output():
    baseline_path = "/home/user/baseline.csv"
    assert os.path.isfile(baseline_path), f"{baseline_path} is missing"

    baseline = {}
    with open(baseline_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(",")
            if len(parts) == 3:
                srv, metric, expected = parts
                baseline[(srv, metric)] = float(expected)

    incoming_csvs = glob.glob("/home/user/incoming/*.csv")
    assert len(incoming_csvs) > 0, "Cannot compute expected output, no incoming CSVs."

    unique_rows = set()
    for csv_file in incoming_csvs:
        with open(csv_file, "r") as f:
            for line in f:
                line = line.strip()
                if line:
                    unique_rows.add(line)

    # report_id -> {server_id, timestamp, total_drift}
    reports = {}
    for row in unique_rows:
        parts = row.split(",")
        if len(parts) == 5:
            report_id, server_id, timestamp, metric_id, actual_value_str = parts
            timestamp = int(timestamp)
            actual_value = float(actual_value_str)

            expected_value = baseline.get((server_id, metric_id))
            if expected_value is not None:
                drift = abs(expected_value - actual_value)
                if report_id not in reports:
                    reports[report_id] = {
                        "server_id": server_id,
                        "timestamp": timestamp,
                        "total_drift": 0.0
                    }
                reports[report_id]["total_drift"] += drift

    # Group by server_id
    server_reports = defaultdict(list)
    for rep_id, data in reports.items():
        server_reports[data["server_id"]].append((data["timestamp"], data["total_drift"]))

    expected_output_lines = []
    for server_id in sorted(server_reports.keys()):
        # Sort by timestamp
        sorted_reps = sorted(server_reports[server_id], key=lambda x: x[0])

        for i in range(len(sorted_reps)):
            ts = sorted_reps[i][0]
            if i == 0:
                rolling_avg = sorted_reps[i][1]
            else:
                rolling_avg = (sorted_reps[i][1] + sorted_reps[i-1][1]) / 2.0

            expected_output_lines.append(f"{server_id},{ts},{rolling_avg:.1f}")

    output_file = "/home/user/output/rolling_drift.csv"
    assert os.path.isfile(output_file), f"{output_file} is missing"

    with open(output_file, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert len(actual_lines) == len(expected_output_lines), f"Expected {len(expected_output_lines)} lines in output, got {len(actual_lines)}"

    for expected, actual in zip(expected_output_lines, actual_lines):
        assert actual == expected, f"Mismatch in output. Expected: '{expected}', Got: '{actual}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

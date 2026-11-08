#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv

def compute_expected_anomaly():
    file_path = "/home/user/config_updates.tsv"

    # Dictionary to hold total length and count of MOTD for each day
    day_stats = {}

    with open(file_path, "r", encoding="utf-8") as f:
        reader = csv.reader(f, delimiter="\t")
        for row in reader:
            if len(row) < 4:
                continue
            date, server_id, config_key, config_val = row[:4]
            if config_key == "MOTD":
                char_len = len(config_val)
                if date not in day_stats:
                    day_stats[date] = {"total_len": 0, "count": 0}
                day_stats[date]["total_len"] += char_len
                day_stats[date]["count"] += 1

    # Calculate averages
    averages = {}
    for date, stats in day_stats.items():
        if stats["count"] > 0:
            averages[date] = stats["total_len"] / stats["count"]

    # Sort dates chronologically
    sorted_dates = sorted(averages.keys())

    max_diff = -1
    anomaly_date = None

    # Calculate differences
    for i in range(1, len(sorted_dates)):
        prev_date = sorted_dates[i-1]
        curr_date = sorted_dates[i]
        diff = abs(averages[curr_date] - averages[prev_date])
        if diff > max_diff:
            max_diff = diff
            anomaly_date = curr_date

    if anomaly_date is None:
        return ""

    return f"{anomaly_date},{max_diff:.2f}"

def test_anomaly_report_exists():
    """Check that the anomaly report file exists."""
    report_path = "/home/user/anomaly_report.txt"
    assert os.path.exists(report_path), f"Expected file {report_path} does not exist."
    assert os.path.isfile(report_path), f"Expected {report_path} to be a file."

def test_anomaly_report_content():
    """Verify the content of the anomaly report matches the expected changepoint."""
    report_path = "/home/user/anomaly_report.txt"
    assert os.path.exists(report_path), f"File {report_path} is missing."

    expected_content = compute_expected_anomaly()

    with open(report_path, "r", encoding="utf-8") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, (
        f"Incorrect anomaly report content.\n"
        f"Expected: '{expected_content}'\n"
        f"Actual:   '{actual_content}'"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

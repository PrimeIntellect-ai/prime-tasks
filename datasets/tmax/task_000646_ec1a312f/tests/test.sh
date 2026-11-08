#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import re
from collections import defaultdict

LOG_FILE_PATH = "/home/user/auth_gateway.log"
CSV_FILE_PATH = "/home/user/top_anomalies.csv"

def get_expected_top_anomalies():
    """Parse the log file and compute the expected top 5 anomalous IPs."""
    anomaly_counts = defaultdict(int)

    if not os.path.exists(LOG_FILE_PATH):
        return []

    with open(LOG_FILE_PATH, 'r') as f:
        for line in f:
            # Extract IP, status, and resp_time using regex
            ip_match = re.search(r'IP:(\S+)', line)
            status_match = re.search(r'status:(\S+)', line)
            time_match = re.search(r'resp_time:(\d+)ms', line)

            if ip_match and status_match and time_match:
                ip = ip_match.group(1)
                status = status_match.group(1)
                resp_time = int(time_match.group(1))

                if status == 'failed' and resp_time > 300:
                    anomaly_counts[ip] += 1

    # Sort by count descending, then IP ascending
    sorted_anomalies = sorted(anomaly_counts.items(), key=lambda x: (-x[1], x[0]))

    # Return top 5
    return sorted_anomalies[:5]

def test_csv_file_exists():
    """Test that the output CSV file exists."""
    assert os.path.exists(CSV_FILE_PATH), f"The output file {CSV_FILE_PATH} does not exist."
    assert os.path.isfile(CSV_FILE_PATH), f"The path {CSV_FILE_PATH} exists but is not a file."

def test_csv_header_and_row_count():
    """Test that the CSV has the correct header and exactly 5 data rows."""
    assert os.path.exists(CSV_FILE_PATH), "CSV file missing."

    with open(CSV_FILE_PATH, 'r') as f:
        reader = list(csv.reader(f))

    assert len(reader) > 0, "The CSV file is empty."

    header = reader[0]
    assert header == ["IP", "AnomalyCount"], f"CSV header is incorrect. Expected ['IP', 'AnomalyCount'], got {header}"

    data_rows = reader[1:]
    assert len(data_rows) == 5, f"Expected exactly 5 data rows, but found {len(data_rows)}."

def test_csv_content_matches_expected():
    """Test that the CSV content matches the expected top 5 anomalies derived from the log."""
    assert os.path.exists(CSV_FILE_PATH), "CSV file missing."

    expected_top_5 = get_expected_top_anomalies()
    assert len(expected_top_5) == 5, "Could not compute 5 expected anomalies from the log file."

    with open(CSV_FILE_PATH, 'r') as f:
        reader = list(csv.DictReader(f))

    assert len(reader) == 5, "CSV does not contain 5 data rows."

    for i, row in enumerate(reader):
        expected_ip, expected_count = expected_top_5[i]

        actual_ip = row.get("IP")
        actual_count_str = row.get("AnomalyCount")

        assert actual_ip == expected_ip, f"Row {i+1}: Expected IP '{expected_ip}', got '{actual_ip}'."

        try:
            actual_count = int(actual_count_str)
        except (ValueError, TypeError):
            pytest.fail(f"Row {i+1}: AnomalyCount '{actual_count_str}' is not a valid integer.")

        assert actual_count == expected_count, f"Row {i+1}: Expected AnomalyCount {expected_count} for IP {expected_ip}, got {actual_count}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

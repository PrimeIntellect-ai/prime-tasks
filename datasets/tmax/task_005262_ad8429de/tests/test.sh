#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
from collections import defaultdict

def test_minute_stats_csv_exists():
    csv_path = "/home/user/minute_stats.csv"
    assert os.path.exists(csv_path), f"File {csv_path} not found."
    assert os.path.isfile(csv_path), f"{csv_path} is not a valid file."

def test_minute_stats_csv_content():
    log_path = "/home/user/app_access.log"
    assert os.path.exists(log_path), f"Source file {log_path} is missing, cannot verify."

    # Recompute the expected aggregations directly from the source file
    stats = defaultdict(lambda: {"total_bytes": 0, "ips": set(), "max_bytes": 0})

    with open(log_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            data = json.loads(line)

            # Extract the minute window: "YYYY-MM-DDTHH:MM" is the first 16 characters of the timestamp
            window = data["timestamp"][:16]
            bytes_val = int(data["bytes"])
            ip = data["ip"]

            stats[window]["total_bytes"] += bytes_val
            stats[window]["ips"].add(ip)
            if bytes_val > stats[window]["max_bytes"]:
                stats[window]["max_bytes"] = bytes_val

    expected_rows = []
    for window in sorted(stats.keys()):
        expected_rows.append([
            window,
            str(stats[window]["total_bytes"]),
            str(len(stats[window]["ips"])),
            str(stats[window]["max_bytes"])
        ])

    csv_path = "/home/user/minute_stats.csv"
    with open(csv_path, "r", newline='') as f:
        reader = csv.reader(f)
        actual_rows = list(reader)

    assert len(actual_rows) > 0, f"The file {csv_path} is empty."

    expected_header = ["window", "total_bytes", "distinct_ips", "max_bytes"]
    assert actual_rows[0] == expected_header, (
        f"CSV header is incorrect.\nExpected: {expected_header}\nActual: {actual_rows[0]}"
    )

    actual_data = actual_rows[1:]
    assert len(actual_data) == len(expected_rows), (
        f"Row count mismatch.\nExpected {len(expected_rows)} data rows, got {len(actual_data)}."
    )

    for i, (expected, actual) in enumerate(zip(expected_rows, actual_data)):
        assert expected == actual, (
            f"Row {i+1} mismatch.\nExpected: {expected}\nActual: {actual}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

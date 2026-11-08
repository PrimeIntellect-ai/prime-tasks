#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
from datetime import datetime, timedelta

def test_clean_configs_csv():
    raw_log_path = "/home/user/raw_configs.log"
    clean_csv_path = "/home/user/clean_configs.csv"

    assert os.path.exists(raw_log_path), f"Raw log file missing: {raw_log_path}"
    assert os.path.exists(clean_csv_path), f"Output CSV file missing: {clean_csv_path}"

    # Parse the raw log to compute the expected state
    log_pattern = re.compile(r"\[(?P<timestamp>\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\].*?target_server=(?P<server>\S+).*?snapshot_hash=(?P<hash>\S+)")

    server_data = {}

    with open(raw_log_path, "r") as f:
        for line in f:
            match = log_pattern.search(line)
            if match:
                dt = datetime.strptime(match.group("timestamp"), "%Y-%m-%d %H:%M:%S")
                date_str = dt.strftime("%Y-%m-%d")
                server = match.group("server")
                hash_val = match.group("hash")

                if server not in server_data:
                    server_data[server] = {}

                # Keep latest timestamp per day
                if date_str not in server_data[server] or server_data[server][date_str]['dt'] < dt:
                    server_data[server][date_str] = {'dt': dt, 'hash': hash_val}

    expected_records = []

    for server, days in server_data.items():
        sorted_dates = sorted(days.keys())
        if not sorted_dates:
            continue

        start_date = datetime.strptime(sorted_dates[0], "%Y-%m-%d")
        end_date = datetime.strptime(sorted_dates[-1], "%Y-%m-%d")

        current_date = start_date
        last_hash = None

        while current_date <= end_date:
            d_str = current_date.strftime("%Y-%m-%d")
            if d_str in days:
                last_hash = days[d_str]['hash']

            expected_records.append((d_str, server, last_hash))
            current_date += timedelta(days=1)

    # Sort chronologically, then by server alphabetically
    expected_records.sort(key=lambda x: (x[0], x[1]))

    expected_csv_lines = ["date,server,hash"]
    for rec in expected_records:
        expected_csv_lines.append(f"{rec[0]},{rec[1]},{rec[2]}")

    expected_csv_content = "\n".join(expected_csv_lines).strip()

    with open(clean_csv_path, "r") as f:
        actual_csv_content = f.read().strip()

    assert actual_csv_content == expected_csv_content, (
        f"The content of {clean_csv_path} does not match the expected output.\n"
        f"Expected:\n{expected_csv_content}\n\nActual:\n{actual_csv_content}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

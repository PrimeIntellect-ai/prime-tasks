#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import sqlite3
from datetime import datetime, timedelta

def get_expected_anomalies():
    raw_logs_path = '/home/user/raw_logs.csv'
    assert os.path.exists(raw_logs_path), f"Raw logs file {raw_logs_path} is missing."

    records = []
    with open(raw_logs_path, 'r', encoding='utf-8') as f:
        reader = csv.DictReader(f)
        for row in reader:
            t = datetime.strptime(row['timestamp'], "%Y-%m-%d %H:%M:%S")
            is_error = 1 if int(row['status_code']) >= 400 else 0
            records.append({
                'timestamp': t,
                'timestamp_str': row['timestamp'],
                'ip_address': row['ip_address'],
                'endpoint': row['endpoint'],
                'status_code': int(row['status_code']),
                'response_time_ms': int(row['response_time_ms']),
                'is_error': is_error
            })

    # Ensure chronologically sorted
    records.sort(key=lambda x: x['timestamp'])

    anomalies = []
    for i, current in enumerate(records):
        window_start = current['timestamp'] - timedelta(minutes=5)

        window_errors = 0
        window_count = 0

        # Match pandas time-based rolling's default right-closed window:
        # include the current timestamp and exclude exactly current - 5 minutes.
        for j in range(i, -1, -1):
            if records[j]['timestamp'] > window_start:
                window_count += 1
                window_errors += records[j]['is_error']
            else:
                break

        error_rate = window_errors / window_count

        if error_rate > 0.15:
            # Mask IP address
            parts = current['ip_address'].split('.')
            parts[-1] = '0'
            masked_ip = '.'.join(parts)

            anomalies.append({
                'timestamp': current['timestamp_str'],
                'masked_ip': masked_ip,
                'endpoint': current['endpoint'],
                'status_code': current['status_code'],
                'response_time_ms': current['response_time_ms'],
                'rolling_error_rate': round(error_rate, 4)
            })

    return anomalies

def test_database_export_and_anomalies():
    db_path = '/home/user/anomalies.db'
    assert os.path.exists(db_path), f"Database file {db_path} was not created."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Check if table exists
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='anomalous_logs'")
    table_exists = cursor.fetchone()
    assert table_exists is not None, "Table 'anomalous_logs' does not exist in the database."

    # Check column definitions
    cursor.execute("PRAGMA table_info(anomalous_logs)")
    columns_info = cursor.fetchall()
    actual_columns = [col[1] for col in columns_info]
    expected_columns = ['timestamp', 'masked_ip', 'endpoint', 'status_code', 'response_time_ms', 'rolling_error_rate']

    assert actual_columns == expected_columns, (
        f"Database columns do not match the expected schema.\n"
        f"Expected: {expected_columns}\n"
        f"Got: {actual_columns}"
    )

    # Fetch all rows from the database
    cursor.execute("SELECT * FROM anomalous_logs ORDER BY timestamp")
    db_rows = cursor.fetchall()

    expected_anomalies = get_expected_anomalies()

    assert len(db_rows) == len(expected_anomalies), (
        f"Row count mismatch in 'anomalous_logs'. "
        f"Expected {len(expected_anomalies)} rows, but got {len(db_rows)}."
    )

    # Verify exact contents of each row
    for db_row, exp_row in zip(db_rows, expected_anomalies):
        assert db_row[0] == exp_row['timestamp'], f"Timestamp mismatch: expected {exp_row['timestamp']}, got {db_row[0]}"
        assert db_row[1] == exp_row['masked_ip'], f"Masked IP mismatch: expected {exp_row['masked_ip']}, got {db_row[1]}"
        assert db_row[2] == exp_row['endpoint'], f"Endpoint mismatch: expected {exp_row['endpoint']}, got {db_row[2]}"
        assert int(db_row[3]) == exp_row['status_code'], f"Status code mismatch: expected {exp_row['status_code']}, got {db_row[3]}"
        assert int(db_row[4]) == exp_row['response_time_ms'], f"Response time mismatch: expected {exp_row['response_time_ms']}, got {db_row[4]}"

        # Check rolling error rate rounded to 4 decimal places
        db_error_rate = round(float(db_row[5]), 4)
        assert db_error_rate == exp_row['rolling_error_rate'], (
            f"Rolling error rate mismatch for {exp_row['timestamp']}: "
            f"expected {exp_row['rolling_error_rate']}, got {db_error_rate}"
        )

    conn.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

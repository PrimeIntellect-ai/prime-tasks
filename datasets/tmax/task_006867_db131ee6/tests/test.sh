#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import hashlib
import pytest

LOG_DIR = "/home/user/logs"
EN_LOG = os.path.join(LOG_DIR, "en_log.csv")
JP_LOG = os.path.join(LOG_DIR, "jp_log.csv")
DE_LOG = os.path.join(LOG_DIR, "de_log.csv")
REPORT_FILE = "/home/user/anomaly_report.json"

def compute_expected_results():
    records = []

    # Read files
    files_to_read = [
        (EN_LOG, 'utf-8'),
        (JP_LOG, 'utf-16le'),
        (DE_LOG, 'iso-8859-1')
    ]

    seen_hashes = set()
    unique_records = []

    for filepath, encoding in files_to_read:
        if not os.path.isfile(filepath):
            continue
        with open(filepath, 'r', encoding=encoding) as f:
            for line in f:
                line = line.strip()
                if not line:
                    continue
                parts = line.split(',', 2)
                if len(parts) == 3:
                    timestamp, metric_str, message = parts
                    metric_value = float(metric_str)

                    # Deduplication
                    hash_input = f"{timestamp}{message}".encode('utf-8')
                    row_hash = hashlib.sha256(hash_input).hexdigest()

                    if row_hash not in seen_hashes:
                        seen_hashes.add(row_hash)
                        unique_records.append({
                            'timestamp': timestamp,
                            'metric_value': metric_value,
                            'message': message
                        })

    # Sort chronologically
    unique_records.sort(key=lambda x: x['timestamp'])

    anomaly_timestamp = None
    anomaly_moving_avg = None

    for i in range(len(unique_records)):
        start_idx = max(0, i - 2)
        window = unique_records[start_idx:i+1]
        moving_avg = sum(r['metric_value'] for r in window) / len(window)

        if moving_avg > 50.0:
            anomaly_timestamp = unique_records[i]['timestamp']
            anomaly_moving_avg = round(moving_avg, 2)
            break

    return {
        "total_unique_records": len(unique_records),
        "anomaly_timestamp": anomaly_timestamp,
        "anomaly_moving_avg": anomaly_moving_avg
    }

def test_anomaly_report_exists():
    assert os.path.isfile(REPORT_FILE), f"Report file {REPORT_FILE} is missing. Did you save it to the correct path?"

def test_anomaly_report_contents():
    expected = compute_expected_results()

    with open(REPORT_FILE, 'r', encoding='utf-8') as f:
        try:
            actual = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{REPORT_FILE} does not contain valid JSON.")

    assert "total_unique_records" in actual, "Missing 'total_unique_records' in report."
    assert "anomaly_timestamp" in actual, "Missing 'anomaly_timestamp' in report."
    assert "anomaly_moving_avg" in actual, "Missing 'anomaly_moving_avg' in report."

    assert actual["total_unique_records"] == expected["total_unique_records"], \
        f"Expected {expected['total_unique_records']} unique records, got {actual['total_unique_records']}."

    assert actual["anomaly_timestamp"] == expected["anomaly_timestamp"], \
        f"Expected anomaly timestamp {expected['anomaly_timestamp']}, got {actual['anomaly_timestamp']}."

    if expected["anomaly_moving_avg"] is not None:
        assert abs(actual["anomaly_moving_avg"] - expected["anomaly_moving_avg"]) < 0.01, \
            f"Expected moving average {expected['anomaly_moving_avg']}, got {actual['anomaly_moving_avg']}."
    else:
        assert actual["anomaly_moving_avg"] is None, "Expected no anomaly, but got one."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

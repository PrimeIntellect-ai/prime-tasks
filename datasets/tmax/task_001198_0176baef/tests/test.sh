#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import sqlite3
import math
from collections import deque, defaultdict
import pytest

LOG_FILE = "/home/user/server_logs.log"
PIPELINE_LOG = "/home/user/pipeline.log"
ANOMALIES_CSV = "/home/user/anomalies.csv"
DB_FILE = "/home/user/ip_summary.db"

@pytest.fixture(scope="session")
def truth_data():
    if not os.path.exists(LOG_FILE):
        pytest.fail(f"Source log file {LOG_FILE} not found. Setup may have failed.")

    window = deque(maxlen=500)
    anomalies = []
    ip_stats = defaultdict(lambda: {"total_requests": 0, "total_errors": 0, "sum_resp_time": 0})

    with open(LOG_FILE, "r") as f:
        for i, line in enumerate(f):
            parts = line.strip().split()
            if len(parts) != 6:
                continue
            timestamp, ip, method, url, status, resp_time = parts
            status = int(status)
            resp_time = int(resp_time)

            # Update IP stats
            ip_stats[ip]["total_requests"] += 1
            if status >= 400:
                ip_stats[ip]["total_errors"] += 1
            ip_stats[ip]["sum_resp_time"] += resp_time

            # Update window
            window.append(resp_time)

            # Check anomaly (from 501st line onwards, which is index 500)
            if i >= 500:
                avg = sum(window) / 500.0
                if avg > 800.0:
                    anomalies.append((timestamp, round(avg, 2)))

    # Finalize IP stats
    final_ip_stats = {}
    for ip, stats in ip_stats.items():
        avg_resp = stats["sum_resp_time"] / stats["total_requests"]
        final_ip_stats[ip] = {
            "total_requests": stats["total_requests"],
            "total_errors": stats["total_errors"],
            "avg_resp_time": avg_resp
        }

    return {
        "anomalies": anomalies,
        "ip_stats": final_ip_stats,
        "line_count": i + 1
    }

def test_pipeline_log_created_and_contains_expected_entries():
    assert os.path.exists(PIPELINE_LOG), f"{PIPELINE_LOG} was not created."
    with open(PIPELINE_LOG, "r") as f:
        content = f.read()

    assert "Pipeline started" in content, "Missing 'Pipeline started' in pipeline.log"
    assert "Processed 5000 lines" in content, "Missing 'Processed 5000 lines' in pipeline.log"
    assert "Processed 10000 lines" in content, "Missing 'Processed 10000 lines' in pipeline.log"
    assert "Processed 15000 lines" in content, "Missing 'Processed 15000 lines' in pipeline.log"
    assert "Pipeline finished" in content, "Missing 'Pipeline finished' in pipeline.log"

def test_anomalies_csv_content(truth_data):
    assert os.path.exists(ANOMALIES_CSV), f"{ANOMALIES_CSV} was not created."
    with open(ANOMALIES_CSV, "r") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, f"{ANOMALIES_CSV} is empty."
    assert rows[0] == ["timestamp", "rolling_avg"], f"Incorrect header in {ANOMALIES_CSV}: {rows[0]}"

    actual_anomalies = rows[1:]
    expected_anomalies = truth_data["anomalies"]

    assert len(actual_anomalies) == len(expected_anomalies), f"Expected {len(expected_anomalies)} anomalies, but found {len(actual_anomalies)}."

    for i, (actual, expected) in enumerate(zip(actual_anomalies, expected_anomalies)):
        assert actual[0] == expected[0], f"Timestamp mismatch at row {i+1}: expected {expected[0]}, got {actual[0]}"
        expected_val_str = f"{expected[1]:.2f}"
        assert actual[1] == expected_val_str, f"Rolling average mismatch at row {i+1}: expected {expected_val_str}, got {actual[1]}"

def test_ip_summary_db_content(truth_data):
    assert os.path.exists(DB_FILE), f"{DB_FILE} was not created."
    conn = sqlite3.connect(DB_FILE)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='ip_stats';")
    assert cursor.fetchone() is not None, "Table 'ip_stats' does not exist in the database."

    cursor.execute("SELECT ip, total_requests, total_errors, avg_resp_time FROM ip_stats;")
    db_rows = cursor.fetchall()
    conn.close()

    expected_stats = truth_data["ip_stats"]
    assert len(db_rows) == len(expected_stats), f"Expected {len(expected_stats)} rows in ip_stats, found {len(db_rows)}."

    for row in db_rows:
        ip, total_req, total_err, avg_resp = row
        assert ip in expected_stats, f"Unexpected IP {ip} found in database."
        exp = expected_stats[ip]
        assert total_req == exp["total_requests"], f"Total requests mismatch for IP {ip}: expected {exp['total_requests']}, got {total_req}"
        assert total_err == exp["total_errors"], f"Total errors mismatch for IP {ip}: expected {exp['total_errors']}, got {total_err}"
        assert math.isclose(avg_resp, exp["avg_resp_time"], rel_tol=1e-5), f"Average response time mismatch for IP {ip}: expected {exp['avg_resp_time']}, got {avg_resp}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

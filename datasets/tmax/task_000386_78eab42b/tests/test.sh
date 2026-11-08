#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import hashlib
import pytest
from datetime import datetime, timezone

RAW_DATA_PATH = "/home/user/raw_data/retried_logs.json"
CLEAN_LOGS_PATH = "/home/user/clean_logs.jsonl"
REPORT_PATH = "/home/user/report.txt"

def normalize_timestamp(ts):
    if isinstance(ts, (int, float)):
        dt = datetime.fromtimestamp(ts, tz=timezone.utc)
    elif isinstance(ts, str):
        if ts.isdigit():
            dt = datetime.fromtimestamp(int(ts), tz=timezone.utc)
        elif "T" in ts:
            ts = ts.replace("Z", "+00:00")
            dt = datetime.fromisoformat(ts)
        else:
            dt = datetime.strptime(ts, "%Y/%m/%d %H:%M:%S").replace(tzinfo=timezone.utc)
    else:
        raise ValueError(f"Unknown timestamp format: {ts}")
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")

def compute_hash(user, action, norm_ts):
    raw_str = f"{user}|{action}|{norm_ts}"
    return hashlib.sha256(raw_str.encode('utf-8')).hexdigest()

@pytest.fixture(scope="module")
def expected_data():
    if not os.path.exists(RAW_DATA_PATH):
        pytest.fail(f"Input file missing: {RAW_DATA_PATH}")

    with open(RAW_DATA_PATH, 'r') as f:
        raw_logs = json.load(f)

    seen_hashes = set()
    unique_logs = []
    user_counts = {}

    for log in raw_logs:
        norm_ts = normalize_timestamp(log['timestamp'])
        h = compute_hash(log['user'], log['action'], norm_ts)

        if h not in seen_hashes:
            seen_hashes.add(h)
            unique_logs.append({
                "event_hash": h,
                "timestamp": norm_ts,
                "user": log['user'],
                "action": log['action']
            })
            user_counts[log['user']] = user_counts.get(log['user'], 0) + 1

    unique_logs.sort(key=lambda x: x['timestamp'])

    most_active_user = sorted(user_counts.items(), key=lambda x: (-x[1], x[0]))[0][0]

    return {
        "total_raw": len(raw_logs),
        "total_unique": len(unique_logs),
        "total_dupes": len(raw_logs) - len(unique_logs),
        "most_active_user": most_active_user,
        "clean_logs": unique_logs
    }

def test_clean_logs_exists():
    assert os.path.isfile(CLEAN_LOGS_PATH), f"File {CLEAN_LOGS_PATH} does not exist"

def test_report_exists():
    assert os.path.isfile(REPORT_PATH), f"File {REPORT_PATH} does not exist"

def test_clean_logs_content(expected_data):
    actual_logs = []
    with open(CLEAN_LOGS_PATH, 'r') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                actual_logs.append(json.loads(line))
            except json.JSONDecodeError:
                pytest.fail(f"Line {line_num} in {CLEAN_LOGS_PATH} is not valid JSON")

    assert len(actual_logs) == expected_data["total_unique"], \
        f"Expected {expected_data['total_unique']} records in clean_logs.jsonl, found {len(actual_logs)}"

    for i, (actual, expected) in enumerate(zip(actual_logs, expected_data["clean_logs"])):
        assert actual == expected, \
            f"Record {i} mismatch. Expected: {expected}, Actual: {actual}"

def test_report_content(expected_data):
    with open(REPORT_PATH, 'r') as f:
        content = f.read()

    expected_report = (
        "ETL Log Processing Report\n"
        "=========================\n"
        f"Total raw records processed: {expected_data['total_raw']}\n"
        f"Total unique records retained: {expected_data['total_unique']}\n"
        f"Total duplicates removed: {expected_data['total_dupes']}\n"
        f"Most active user (by unique records): {expected_data['most_active_user']}\n"
    )

    assert content.strip() == expected_report.strip(), \
        f"Report content does not match expected format and values.\nExpected:\n{expected_report}\nActual:\n{content}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

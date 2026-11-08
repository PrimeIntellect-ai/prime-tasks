#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import re
from datetime import datetime, timezone
from collections import defaultdict

def test_processed_logs_exists():
    out_path = "/home/user/processed_logs.jsonl"
    assert os.path.isfile(out_path), f"Output file {out_path} is missing."

def test_processed_logs_content():
    raw_path = "/home/user/raw_chat.log"
    out_path = "/home/user/processed_logs.jsonl"

    assert os.path.isfile(raw_path), f"Raw log file {raw_path} is missing."
    assert os.path.isfile(out_path), f"Processed log file {out_path} is missing."

    # Derive expected state from the raw file
    windows = defaultdict(list)

    with open(raw_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            parts = line.split(' | ', 2)
            if len(parts) != 3:
                continue

            ts_str, uid, msg = parts

            # Parse timestamp: DD-MMM-YYYY HH:MM:SS OFFSET
            dt = datetime.strptime(ts_str, "%d-%b-%Y %H:%M:%S %z")
            dt_utc = dt.astimezone(timezone.utc)
            window_start = dt_utc.replace(minute=0, second=0, microsecond=0)
            window_str = window_start.strftime("%Y-%m-%dT%H:00:00Z")

            # Masking
            # 1. Email masking: replace local part before '@' with '***'
            msg = re.sub(r'([a-zA-Z0-9_.+-]+)@([a-zA-Z0-9-]+\.[a-zA-Z0-9-.]+)', r'***@\2', msg)

            # 2. US Phone masking: replace first two groups with 'XXX'
            msg = re.sub(r'\b\d{3}-\d{3}-(\d{4})\b', r'XXX-XXX-\1', msg)

            windows[window_str].append((dt_utc, uid, msg))

    expected_results = []
    for w_start in sorted(windows.keys()):
        events = sorted(windows[w_start], key=lambda event: event[0])
        uids = set(e[1] for e in events)
        msgs = [e[2] for e in events]
        expected_results.append({
            "window_start": w_start,
            "total_messages": len(events),
            "unique_users": len(uids),
            "messages": msgs
        })

    actual_results = []
    with open(out_path, 'r') as f:
        for line in f:
            line = line.strip()
            if line:
                try:
                    actual_results.append(json.loads(line))
                except json.JSONDecodeError:
                    assert False, f"Line in {out_path} is not valid JSON: {line}"

    assert len(actual_results) == len(expected_results), f"Expected {len(expected_results)} windows, got {len(actual_results)}"

    for actual, expected in zip(actual_results, expected_results):
        assert "window_start" in actual, "Missing 'window_start' in output JSON"
        assert actual["window_start"] == expected["window_start"], f"Expected window {expected['window_start']}, got {actual['window_start']}"

        assert "total_messages" in actual, "Missing 'total_messages' in output JSON"
        assert actual["total_messages"] == expected["total_messages"], f"Window {expected['window_start']}: expected {expected['total_messages']} messages, got {actual['total_messages']}"

        assert "unique_users" in actual, "Missing 'unique_users' in output JSON"
        assert actual["unique_users"] == expected["unique_users"], f"Window {expected['window_start']}: expected {expected['unique_users']} unique users, got {actual['unique_users']}"

        assert "messages" in actual, "Missing 'messages' in output JSON"
        assert actual["messages"] == expected["messages"], f"Window {expected['window_start']}: expected messages {expected['messages']}, got {actual['messages']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

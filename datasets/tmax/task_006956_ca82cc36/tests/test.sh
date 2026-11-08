#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import json
from datetime import datetime, timezone

def parse_timestamp(ts_str):
    if "T" in ts_str:
        dt = datetime.strptime(ts_str, "%Y-%m-%dT%H:%M:%SZ")
        dt = dt.replace(tzinfo=timezone.utc)
        return int(dt.timestamp())
    else:
        return int(ts_str)

def compute_expected_metrics(input_file):
    with open(input_file, "r", newline="") as f:
        reader = csv.DictReader(f)
        events = list(reader)

    parsed_events = []
    for row in events:
        ts = parse_timestamp(row["raw_ts"])
        usr = row["usr"]
        req_path = row["req_path"].lower().rstrip("/")
        bytes_val = int(row["bytes"])
        parsed_events.append({
            "ts": ts,
            "usr": usr,
            "req_path": req_path,
            "bytes": bytes_val
        })

    # Sort chronologically
    parsed_events.sort(key=lambda x: x["ts"])

    # Deduplicate
    kept_events = []
    last_seen = {}  # (usr, req_path) -> ts
    for ev in parsed_events:
        key = (ev["usr"], ev["req_path"])
        if key in last_seen:
            prev_ts = last_seen[key]
            if ev["ts"] - prev_ts <= 5:
                continue  # Drop
        last_seen[key] = ev["ts"]
        kept_events.append(ev)

    # Rolling statistics
    final_events = []
    for i, ev in enumerate(kept_events):
        current_ts = ev["ts"]
        rolling_sum = 0
        for j in range(i, -1, -1):
            if current_ts - kept_events[j]["ts"] <= 60:
                rolling_sum += kept_events[j]["bytes"]
            else:
                break
        final_events.append({
            "ts": ev["ts"],
            "usr": ev["usr"],
            "req_path": ev["req_path"],
            "bytes": ev["bytes"],
            "rolling_bytes_60s": rolling_sum
        })

    return final_events

def test_clean_metrics_exists():
    """Test that the output file exists."""
    output_file = "/home/user/clean_metrics.jsonl"
    assert os.path.isfile(output_file), f"Output file {output_file} is missing."

def test_clean_metrics_content():
    """Test that the output file has the correct processed data."""
    input_file = "/home/user/raw_events.csv"
    output_file = "/home/user/clean_metrics.jsonl"

    expected = compute_expected_metrics(input_file)

    actual = []
    with open(output_file, "r") as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
                actual.append(record)
            except json.JSONDecodeError:
                assert False, f"Line {line_num} in {output_file} is not valid JSON."

    assert len(actual) == len(expected), f"Expected {len(expected)} records, but found {len(actual)} in {output_file}."

    for i, (act, exp) in enumerate(zip(actual, expected)):
        assert act == exp, f"Record at index {i} does not match.\nExpected: {exp}\nActual: {act}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

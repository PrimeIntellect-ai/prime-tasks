#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
from datetime import datetime, timedelta
from collections import defaultdict
import math

INPUT_FILE = "/home/user/raw_server_logs.csv"
OUTPUT_FILE = "/home/user/rolling_metrics.csv"

def get_interval_start(dt):
    minute = (dt.minute // 15) * 15
    return dt.replace(minute=minute, second=0, microsecond=0)

def compute_expected_data():
    if not os.path.exists(INPUT_FILE):
        return []

    with open(INPUT_FILE, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    if not rows:
        return []

    # Parse timestamps
    parsed_rows = []
    for r in rows:
        dt = datetime.strptime(r["timestamp"], "%Y-%m-%d %H:%M:%S")
        parsed_rows.append((dt, r))

    min_dt = min(r[0] for r in parsed_rows)
    max_dt = max(r[0] for r in parsed_rows)

    start_interval = get_interval_start(min_dt)
    end_interval = get_interval_start(max_dt)

    intervals = []
    curr = start_interval
    while curr <= end_interval:
        intervals.append(curr)
        curr += timedelta(minutes=15)

    languages = ["en", "es", "ru", "zh"]

    # Count messages
    counts = {lang: {iv: 0 for iv in intervals} for lang in languages}

    for dt, r in parsed_rows:
        iv = get_interval_start(dt)
        for lang in languages:
            msg = r.get(f"msg_{lang}", "").strip()
            if msg:
                counts[lang][iv] += 1

    expected_output = []

    for lang in sorted(languages):
        lang_counts = [counts[lang][iv] for iv in intervals]
        rolling_avgs = []
        for i in range(len(lang_counts)):
            window = lang_counts[max(0, i-2):i+1]
            avg = sum(window) / len(window)
            rolling_avgs.append(round(avg, 2))

        for iv, count, avg in zip(intervals, lang_counts, rolling_avgs):
            expected_output.append({
                "timestamp": iv.strftime("%Y-%m-%d %H:%M:%S"),
                "language": lang,
                "message_count": float(count),
                "rolling_avg": float(avg)
            })

    return expected_output

def test_output_file_exists():
    assert os.path.isfile(OUTPUT_FILE), f"Output file {OUTPUT_FILE} does not exist."

def test_output_file_format_and_content():
    expected_data = compute_expected_data()
    assert expected_data, "Expected data could not be computed. Check input file."

    with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        actual_rows = list(reader)

    assert reader.fieldnames == ["timestamp", "language", "message_count", "rolling_avg"], \
        f"Unexpected columns: {reader.fieldnames}"

    assert len(actual_rows) == len(expected_data), \
        f"Expected {len(expected_data)} rows, got {len(actual_rows)}"

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_data)):
        assert actual["timestamp"] == expected["timestamp"], \
            f"Row {i}: Expected timestamp {expected['timestamp']}, got {actual['timestamp']}"
        assert actual["language"] == expected["language"], \
            f"Row {i}: Expected language {expected['language']}, got {actual['language']}"

        try:
            actual_count = float(actual["message_count"])
        except ValueError:
            assert False, f"Row {i}: message_count '{actual['message_count']}' is not a valid float"

        assert math.isclose(actual_count, expected["message_count"]), \
            f"Row {i}: Expected message_count {expected['message_count']}, got {actual_count}"

        try:
            actual_avg = float(actual["rolling_avg"])
        except ValueError:
            assert False, f"Row {i}: rolling_avg '{actual['rolling_avg']}' is not a valid float"

        assert math.isclose(actual_avg, expected["rolling_avg"], abs_tol=0.011), \
            f"Row {i}: Expected rolling_avg {expected['rolling_avg']}, got {actual_avg}"

def test_output_sorting():
    with open(OUTPUT_FILE, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        actual_rows = list(reader)

    if not actual_rows:
        return

    # Check sorting: first by language, then by timestamp
    for i in range(1, len(actual_rows)):
        prev = actual_rows[i-1]
        curr = actual_rows[i]

        if prev["language"] == curr["language"]:
            assert prev["timestamp"] < curr["timestamp"], \
                f"Rows not sorted by timestamp for language {curr['language']}: {prev['timestamp']} came before {curr['timestamp']}"
        else:
            assert prev["language"] < curr["language"], \
                f"Rows not sorted by language: {prev['language']} came before {curr['language']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

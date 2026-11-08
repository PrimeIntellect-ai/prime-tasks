#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import subprocess
import pytest
from datetime import datetime, timezone

SUMMARY_CSV = "/home/user/output/user_summary.csv"
LOGS_PARQUET = "/home/user/output/cleaned_logs.parquet"


def get_parquet_data(filepath):
    code = f"""
import pandas as pd
import json
try:
    df = pd.read_parquet('{filepath}')
    df['timestamp'] = df['timestamp'].astype(str)
    print(df.to_json(orient='records'))
except Exception as e:
    import sys
    sys.exit(str(e))
"""
    result = subprocess.run(['python3', '-c', code], capture_output=True, text=True)
    if result.returncode != 0:
        pytest.fail(f"Failed to read parquet file {filepath}. Error: {result.stderr.strip() or result.stdout.strip()}")

    try:
        return json.loads(result.stdout)
    except json.JSONDecodeError:
        pytest.fail(f"Could not parse parquet data as JSON. Output was: {result.stdout}")


def canonical_timestamp(value):
    text = str(value).replace("Z", "+00:00")
    try:
        parsed = datetime.fromisoformat(text)
    except ValueError:
        pytest.fail(f"Invalid timestamp value: {value!r}")
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def test_output_directories_exist():
    assert os.path.exists("/home/user/output"), "Output directory /home/user/output does not exist."


def test_user_summary_csv():
    assert os.path.isfile(SUMMARY_CSV), f"Summary file {SUMMARY_CSV} is missing."

    with open(SUMMARY_CSV, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        rows = list(reader)

    assert reader.fieldnames is not None, "Summary CSV must have a header."

    expected_cols = {"user_id", "app", "email"}
    actual_cols = set(reader.fieldnames)
    assert expected_cols.issubset(actual_cols), f"Summary CSV missing expected columns. Found: {actual_cols}"
    assert reader.fieldnames == ["user_id", "app", "email"], (
        f"Summary CSV must have exactly the columns user_id, app, email in that order. Found: {reader.fieldnames}"
    )

    summary_map = {row["user_id"]: row for row in rows}
    assert len(rows) == 3, f"Expected exactly 3 rows in summary, found {len(rows)}."
    assert len(summary_map) == 3, f"Expected 3 unique users in summary, found {len(summary_map)}."

    assert "U100" in summary_map, "User U100 missing from summary."
    assert int(summary_map["U100"]["app"]) == 3, "U100 app count should be 3."
    assert int(summary_map["U100"]["email"]) == 1, "U100 email count should be 1."

    assert "U101" in summary_map, "User U101 missing from summary."
    assert int(summary_map["U101"]["app"]) == 0, "U101 app count should be 0."
    assert int(summary_map["U101"]["email"]) == 2, "U101 email count should be 2."

    assert "U102" in summary_map, "User U102 missing from summary."
    assert int(summary_map["U102"]["app"]) == 1, "U102 app count should be 1."
    assert int(summary_map["U102"]["email"]) == 0, "U102 email count should be 0."

    user_ids = [row["user_id"] for row in rows]
    assert user_ids == sorted(user_ids), "Summary CSV must be sorted ascending by user_id."


def test_cleaned_logs_parquet():
    assert os.path.isfile(LOGS_PARQUET), f"Parquet file {LOGS_PARQUET} is missing."

    data = get_parquet_data(LOGS_PARQUET)
    assert len(data) == 7, f"Expected 7 total logs in parquet file, found {len(data)}."

    expected_cols = {"timestamp", "user_id", "text", "source", "normalized_text", "rolling_msg_1h"}
    if data:
        actual_cols = set(data[0].keys())
        assert expected_cols.issubset(actual_cols), f"Parquet missing expected columns. Found: {actual_cols}"
    for row in data:
        assert expected_cols.issubset(set(row.keys())), f"Parquet row missing expected columns: {row}"

    for i in range(1, len(data)):
        prev, curr = data[i-1], data[i]
        assert prev["user_id"] <= curr["user_id"], "Parquet data not sorted by user_id ascending."
        if prev["user_id"] == curr["user_id"]:
            assert canonical_timestamp(prev["timestamp"]) <= canonical_timestamp(curr["timestamp"]), (
                "Parquet data not sorted by timestamp ascending within user_id."
            )

    u100_logs = [row for row in data if row["user_id"] == "U100"]
    assert len(u100_logs) == 4, f"Expected 4 logs for U100, found {len(u100_logs)}"

    rolling_vals = [int(row["rolling_msg_1h"]) for row in u100_logs]
    assert rolling_vals == [1, 2, 3, 3], f"Rolling values for U100 incorrect. Expected [1, 2, 3, 3], got {rolling_vals}"

    norm_text_0 = u100_logs[0]["normalized_text"]
    assert norm_text_0 == "hello my order failed", f"Normalization incorrect for first U100 log. Got: '{norm_text_0}'"

    u101_logs = [row for row in data if row["user_id"] == "U101"]
    assert len(u101_logs) == 2, f"Expected 2 logs for U101, found {len(u101_logs)}"
    rolling_vals_101 = [int(row["rolling_msg_1h"]) for row in u101_logs]
    assert rolling_vals_101 == [1, 1], f"Rolling values for U101 incorrect. Expected [1, 1], got {rolling_vals_101}"

    u102_logs = [row for row in data if row["user_id"] == "U102"]
    assert len(u102_logs) == 1, f"Expected 1 log for U102, found {len(u102_logs)}"
    assert int(u102_logs[0]["rolling_msg_1h"]) == 1, "Rolling value for U102 incorrect."

    expected_rows = [
        ("U100", "2023-10-01T10:00:00Z", "Hello, my order failed!!", "app", "hello my order failed", 1),
        ("U100", "2023-10-01T10:15:00Z", "Can you check order #992?", "app", "can you check order 992", 2),
        ("U100", "2023-10-01T10:30:00Z", "I also emailed about order #992. Thx.", "email", "i also emailed about order 992 thx", 3),
        ("U100", "2023-10-01T11:05:00Z", "Any updates?", "app", "any updates", 3),
        ("U101", "2023-10-01T08:00:00Z", "Where is my package?", "email", "where is my package", 1),
        ("U101", "2023-10-01T12:00:00Z", "Refund requested for item A.", "email", "refund requested for item a", 1),
        ("U102", "2023-10-01T09:30:00Z", "Reset password pls.", "app", "reset password pls", 1),
    ]

    for row, expected in zip(data, expected_rows):
        user_id, timestamp, text, source, normalized_text, rolling = expected
        assert row["user_id"] == user_id
        assert canonical_timestamp(row["timestamp"]) == timestamp
        assert row["text"] == text
        assert row["source"] == source
        assert row["normalized_text"] == normalized_text
        assert int(row["rolling_msg_1h"]) == rolling
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

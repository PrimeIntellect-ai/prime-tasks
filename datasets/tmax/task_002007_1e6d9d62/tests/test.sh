#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
from datetime import datetime, timezone
from collections import defaultdict


def parse_iso8601(time_str):
    try:
        dt = datetime.fromisoformat(time_str)
    except ValueError:
        dt = datetime.strptime(time_str, "%Y-%m-%dT%H:%M:%S%z")
    return dt.astimezone(timezone.utc)


def build_summary(europe_data, asia_data):
    counts = defaultdict(lambda: defaultdict(lambda: defaultdict(int)))

    for row in europe_data:
        dt = parse_iso8601(row["time"])
        bucket = dt.strftime("%Y-%m-%dT%H:00:00Z")
        counts[bucket][row["locale"]][row["msg_id"]] += 1

    for row in asia_data:
        dt = datetime.fromtimestamp(int(row["timestamp"]), tz=timezone.utc)
        bucket = dt.strftime("%Y-%m-%dT%H:00:00Z")
        counts[bucket][row["locale"]][row["msg_id"]] += 1

    summary = []
    for bucket in sorted(counts.keys()):
        for locale in sorted(counts[bucket].keys()):
            msg_counts = counts[bucket][locale]
            top_msg_id = sorted(msg_counts.items(), key=lambda x: (-x[1], x[0]))[0]
            summary.append({
                "hour": bucket,
                "locale": locale,
                "top_msg_id": top_msg_id[0],
                "count": top_msg_id[1]
            })
    return summary


def compute_expected_summary():
    europe_file = "/home/user/locales/europe_logs.json"
    asia_file = "/home/user/locales/asia_logs.csv"

    europe_data = []
    asia_data = []

    if os.path.exists(europe_file):
        with open(europe_file, "r") as f:
            europe_data = json.load(f)

    if os.path.exists(asia_file):
        with open(asia_file, "r") as f:
            asia_data = list(csv.DictReader(f))

    return build_summary(europe_data, asia_data)


def compute_expected_from_supplied_data():
    europe_data = [
        {"time": "2023-10-25T14:30:00+02:00", "locale": "fr-FR", "msg_id": "ERR_TIMEOUT"},
        {"time": "2023-10-25T14:45:00+02:00", "locale": "fr-FR", "msg_id": "ERR_TIMEOUT"},
        {"time": "2023-10-25T14:50:00+02:00", "locale": "fr-FR", "msg_id": "BTN_CANCEL"},
        {"time": "2023-10-25T15:10:00+02:00", "locale": "de-DE", "msg_id": "LBL_TITLE"},
        {"time": "2023-10-25T15:20:00+02:00", "locale": "de-DE", "msg_id": "LBL_TITLE"},
        {"time": "2023-10-25T15:30:00+02:00", "locale": "de-DE", "msg_id": "ERR_DB"}
    ]
    asia_data = [
        {"timestamp": 1698237000, "locale": "ja-JP", "msg_id": "BTN_SUBMIT"},
        {"timestamp": 1698237100, "locale": "ja-JP", "msg_id": "BTN_SUBMIT"},
        {"timestamp": 1698237200, "locale": "ja-JP", "msg_id": "ERR_TIMEOUT"},
        {"timestamp": 1698240600, "locale": "ko-KR", "msg_id": "MENU_HELP"},
        {"timestamp": 1698240650, "locale": "ko-KR", "msg_id": "MENU_HELP"},
        {"timestamp": 1698240650, "locale": "ko-KR", "msg_id": "MENU_HELP"}
    ]
    return build_summary(europe_data, asia_data)


def assert_summary_matches(actual_data, expected_data):
    assert isinstance(actual_data, list), "Output must be a JSON array."
    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} items, got {len(actual_data)}."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual.get("hour") == expected["hour"], f"Item {i}: expected hour {expected['hour']}, got {actual.get('hour')}"
        assert actual.get("locale") == expected["locale"], f"Item {i}: expected locale {expected['locale']}, got {actual.get('locale')}"
        assert actual.get("top_msg_id") == expected["top_msg_id"], f"Item {i}: expected top_msg_id {expected['top_msg_id']}, got {actual.get('top_msg_id')}"
        assert actual.get("count") == expected["count"], f"Item {i}: expected count {expected['count']}, got {actual.get('count')}"


def test_output_file_exists():
    assert os.path.isfile("/home/user/locales/hourly_summary.json"), "Output file /home/user/locales/hourly_summary.json is missing."


def test_output_content_is_correct():
    output_file = "/home/user/locales/hourly_summary.json"
    assert os.path.isfile(output_file), "Cannot test content because output file is missing."

    with open(output_file, "r") as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            assert False, "Output file is not valid JSON."

    # Preserve the original check against the current input files.
    assert_summary_matches(actual_data, compute_expected_summary())

    # Also check against an immutable reconstruction of the supplied inputs so
    # deleting or replacing those writable files cannot make an empty result pass.
    assert_summary_matches(actual_data, compute_expected_from_supplied_data())
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

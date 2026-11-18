#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import datetime as dt
import json
import os
import random
import string
import subprocess
import time
import urllib.error
import urllib.request

import pandas as pd
from pandas.testing import assert_frame_equal

SCRIPT = "/home/user/process_logs.py"
RAW = "/home/user/raw_chat_logs.csv"
JSON_PATH = "/home/user/hourly_region_counts.json"
PARQUET_PATH = "/home/user/hourly_region_counts.parquet"
URL = "http://localhost:8080/hourly_region_counts.json"


def load_json():
    assert os.path.exists(JSON_PATH), f"JSON file missing at {JSON_PATH}"
    with open(JSON_PATH, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {JSON_PATH} is not valid JSON."
    assert isinstance(data, list), "JSON output must be a list of dictionaries."
    assert all(isinstance(row, dict) for row in data), "Every JSON row must be a dictionary."
    return data


def load_and_validate_parquet(json_data):
    assert os.path.exists(PARQUET_PATH), f"Parquet file missing at {PARQUET_PATH}"
    with open(PARQUET_PATH, "rb") as f:
        magic = f.read(4)
        assert magic == b"PAR1", f"File {PARQUET_PATH} is not a valid Parquet file (missing PAR1 magic bytes)."

    parquet_df = pd.read_parquet(PARQUET_PATH).reset_index(drop=True)
    json_df = pd.DataFrame(json_data).reset_index(drop=True)
    assert list(parquet_df.columns) == list(json_df.columns), \
        "Parquet and JSON outputs do not have the same columns in the same order."
    assert_frame_equal(parquet_df, json_df, check_dtype=False, check_names=True)
    return parquet_df


def fetch_json_bytes(timeout=2):
    try:
        req = urllib.request.Request(URL)
        with urllib.request.urlopen(req, timeout=timeout) as response:
            assert response.status == 200, f"Expected HTTP status 200, got {response.status}"
            content = response.read()
            assert len(content) > 0, "Downloaded file is empty."
            return content
    except urllib.error.URLError as e:
        assert False, f"Failed to connect to HTTP server on port 8080: {e}"


def canonical(data):
    return [dict(sorted(row.items())) for row in data]


def derive_expected_from_csv(path):
    counts = {}
    regions = set()
    with open(path, "r", encoding="utf-16le", newline="") as f:
        for row in csv.DictReader(f):
            if row["message"] == "":
                continue
            stamp = dt.datetime.strptime(row["timestamp"], "%Y-%m-%d %H:%M:%S")
            hour = stamp.replace(minute=0, second=0).strftime("%Y-%m-%d %H:00")
            region = row["region"]
            regions.add(region)
            counts[(hour, region)] = counts.get((hour, region), 0) + 1

    ordered_regions = sorted(regions)
    expected = []
    for hour in sorted({key[0] for key in counts}):
        record = {"hour": hour}
        record.update({region: counts.get((hour, region), 0) for region in ordered_regions})
        expected.append(record)
    return expected


def assert_exact_dataset(actual, expected):
    assert len(actual) == len(expected), f"Expected {len(expected)} rows, got {len(actual)}"
    expected_keys = {"hour"} | ({k for row in expected for k in row} - {"hour"})
    for row in actual:
        assert set(row) == expected_keys, f"Unexpected JSON columns: {set(row)}; expected {expected_keys}"
    assert canonical(actual) == canonical(expected), f"Output data differs from expected data: {actual}"


def test_original_outputs_and_serving():
    data = load_json()
    expected = [
        {"hour": "2023-10-24 14:00", "ASIA": 1, "EU": 2, "US": 0},
        {"hour": "2023-10-24 15:00", "ASIA": 0, "EU": 1, "US": 1},
        {"hour": "2023-10-24 16:00", "ASIA": 0, "EU": 0, "US": 1}
    ]

    assert len(data) == len(expected), f"Expected {len(expected)} rows, got {len(data)}"
    for d, e in zip(data, expected):
        assert d.get("hour") == e["hour"], f"Expected hour {e['hour']}, got {d.get('hour')}"
        assert int(d.get("ASIA", 0)) == e["ASIA"], f"Expected ASIA count {e['ASIA']} for hour {e['hour']}"
        assert int(d.get("EU", 0)) == e["EU"], f"Expected EU count {e['EU']} for hour {e['hour']}"
        assert int(d.get("US", 0)) == e["US"], f"Expected US count {e['US']} for hour {e['hour']}"

    load_and_validate_parquet(data)
    served = fetch_json_bytes()
    with open(JSON_PATH, "rb") as f:
        on_disk = f.read()
    assert served == on_disk, "HTTP server did not serve the generated JSON file."


def test_script_processes_utf16_csv_dynamically():
    assert os.path.isfile(SCRIPT), f"Required script missing at {SCRIPT}"
    assert not os.path.islink(SCRIPT), "process_logs.py must be a real script, not a symlink."
    assert os.path.getsize(SCRIPT) > 0, "process_logs.py is empty."

    token = ''.join(random.SystemRandom().choice(string.ascii_uppercase) for _ in range(7))
    regions = [f"NORTH_{token}", f"SOUTH_{token}", f"WEST_{token}"]
    day = random.SystemRandom().randint(10, 20)
    rows = [
        ["timestamp", "user_id", "region", "message"],
        [f"2024-07-{day:02d} 09:03:00", "201", regions[0], "first line\nsecond line"],
        [f"2024-07-{day:02d} 09:21:00", "202", regions[1], "alpha"],
        [f"2024-07-{day:02d} 09:59:59", "203", regions[0], "three\nembedded\nlines"],
        [f"2024-07-{day:02d} 10:05:00", "204", regions[2], ""],
        [f"2024-07-{day:02d} 10:17:00", "205", regions[2], "Unicode café 日本語"],
        [f"2024-07-{day:02d} 11:00:00", "206", regions[1], "valid"],
        [f"2024-07-{day:02d} 11:35:00", "207", regions[2], "another"],
        [f"2024-07-{day:02d} 11:58:00", "208", regions[1], "tail\nline"]
    ]
    with open(RAW, "w", encoding="utf-16le", newline="") as f:
        csv.writer(f).writerows(rows)

    expected = derive_expected_from_csv(RAW)
    completed = subprocess.run(
        ["python3", SCRIPT],
        cwd="/home/user",
        stdin=subprocess.DEVNULL,
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
        timeout=20,
        check=False,
    )
    assert completed.returncode == 0, f"process_logs.py exited with status {completed.returncode}"

    data = load_json()
    assert_exact_dataset(data, expected)
    load_and_validate_parquet(data)

    deadline = time.time() + 5
    last_error = None
    while time.time() < deadline:
        try:
            served = fetch_json_bytes(timeout=1)
            with open(JSON_PATH, "rb") as f:
                assert served == f.read(), "HTTP server returned content different from the generated JSON file."
            assert json.loads(served.decode("utf-8")) == data
            break
        except (AssertionError, urllib.error.URLError, TimeoutError) as exc:
            last_error = exc
            time.sleep(0.2)
    else:
        assert False, f"Generated JSON was not served correctly on port 8080: {last_error}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

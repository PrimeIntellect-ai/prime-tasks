#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import stat
import subprocess
import sys
from collections import defaultdict
from datetime import datetime, timedelta, timezone

SCRIPT = "/home/user/process_logs.py"
LOGS = "/home/user/app_logs.csv"
META = "/home/user/server_meta.json"
OUTPUT = "/home/user/rolling_stats.json"

ORIGINAL_EXPECTED = [
    {"window_start": "2023-10-01T10:00:00Z", "region": "eu-west-1", "total_logs": 1, "error_count": 0, "rolling_3h_error_avg": 0.0},
    {"window_start": "2023-10-01T11:00:00Z", "region": "eu-west-1", "total_logs": 1, "error_count": 1, "rolling_3h_error_avg": 0.33},
    {"window_start": "2023-10-01T08:00:00Z", "region": "us-east-1", "total_logs": 1, "error_count": 0, "rolling_3h_error_avg": 0.0},
    {"window_start": "2023-10-01T09:00:00Z", "region": "us-east-1", "total_logs": 1, "error_count": 1, "rolling_3h_error_avg": 0.33},
    {"window_start": "2023-10-01T10:00:00Z", "region": "us-east-1", "total_logs": 2, "error_count": 2, "rolling_3h_error_avg": 1.0},
    {"window_start": "2023-10-01T11:00:00Z", "region": "us-east-1", "total_logs": 1, "error_count": 1, "rolling_3h_error_avg": 1.33},
]


def run_script():
    if os.path.exists(OUTPUT):
        os.unlink(OUTPUT)
    result = subprocess.run(
        [sys.executable, SCRIPT],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, f"process_logs.py failed:\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    assert os.path.exists(OUTPUT), f"Output file {OUTPUT} is missing."
    with open(OUTPUT, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as exc:
            assert False, f"File {OUTPUT} is not valid JSON: {exc}"
    assert isinstance(data, list), f"Expected the JSON in {OUTPUT} to be a list, but got {type(data).__name__}."
    return data


def assert_original_data(data):
    expected_data = ORIGINAL_EXPECTED
    assert len(data) == len(expected_data), f"Expected {len(expected_data)} records, but got {len(data)}."
    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        expected_keys = set(expected.keys())
        actual_keys = set(actual.keys())
        assert actual_keys == expected_keys, f"Record {i} keys mismatch. Expected {expected_keys}, got {actual_keys}."
        assert actual["window_start"] == expected["window_start"], f"Record {i} window_start mismatch. Expected {expected['window_start']}, got {actual['window_start']}."
        assert actual["region"] == expected["region"], f"Record {i} region mismatch. Expected {expected['region']}, got {actual['region']}."
        assert actual["total_logs"] == expected["total_logs"], f"Record {i} total_logs mismatch. Expected {expected['total_logs']}, got {actual['total_logs']}."
        assert actual["error_count"] == expected["error_count"], f"Record {i} error_count mismatch. Expected {expected['error_count']}, got {actual['error_count']}."
        assert abs(actual["rolling_3h_error_avg"] - expected["rolling_3h_error_avg"]) < 0.001, f"Record {i} rolling_3h_error_avg mismatch. Expected {expected['rolling_3h_error_avg']}, got {actual['rolling_3h_error_avg']}."


def write_varied_inputs():
    token = secrets.token_hex(5)
    regions = [f"a-region-{token}", f"m-region-{token}", f"z-region-{token}"]
    servers = [f"node-{token}-{i}" for i in range(4)]
    unknown = f"unknown-{token}"
    metadata = [
        {"server_id": servers[0], "region": regions[0], "tier": "web"},
        {"server_id": servers[1], "region": regions[0], "tier": "db"},
        {"server_id": servers[2], "region": regions[1], "tier": "worker"},
        {"server_id": servers[3], "region": regions[2], "tier": "cache"},
    ]
    base = datetime(
        2021 + secrets.randbelow(5),
        1 + secrets.randbelow(11),
        2 + secrets.randbelow(18),
        2 + secrets.randbelow(14),
        tzinfo=timezone.utc,
    )

    def ts(hours, minutes):
        return (base + timedelta(hours=hours, minutes=minutes)).strftime("%Y-%m-%dT%H:%M:%SZ")

    records = [
        (ts(3, 44), servers[1], "ERROR", f"second error, {token}"),
        (ts(1, 7), servers[2], "error", "lowercase is not an exact ERROR"),
        (ts(0, 5), servers[0], "INFO", f"multiline start\ntrace {token}, with comma"),
        (ts(4, 29), servers[2], "ERROR", "late error"),
        (ts(0, 52), servers[3], "ERROR", "isolated region error"),
        (ts(2, 11), servers[2], "ERROR", f"quoted \"failure\"\nstack line {token}"),
        (ts(1, 31), servers[0], "ERROR", "first exact error"),
        (ts(3, 2), servers[0], "ERROR", "sparse-window error"),
        (ts(2, 48), unknown, "ERROR", "must be dropped after metadata join"),
    ]

    with open(META, "w", encoding="utf-8") as f:
        json.dump(metadata, f)
    with open(LOGS, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["timestamp", "server_id", "log_level", "message"])
        writer.writerows(records)
    return metadata, records


def derive_expected(metadata, records):
    server_regions = {item["server_id"]: item["region"] for item in metadata}
    grouped = defaultdict(lambda: [0, 0])
    for timestamp, server_id, level, _message in records:
        if server_id not in server_regions:
            continue
        dt = datetime.strptime(timestamp, "%Y-%m-%dT%H:%M:%SZ").replace(tzinfo=timezone.utc)
        window = dt.replace(minute=0, second=0, microsecond=0)
        key = (server_regions[server_id], window)
        grouped[key][0] += 1
        grouped[key][1] += int(level == "ERROR")

    expected = []
    for region, window in sorted(grouped, key=lambda key: (key[0], key[1])):
        total, errors = grouped[(region, window)]
        rolling_sum = sum(grouped.get((region, window - timedelta(hours=i)), [0, 0])[1] for i in range(3))
        expected.append({
            "window_start": window.strftime("%Y-%m-%dT%H:00:00Z"),
            "region": region,
            "total_logs": total,
            "error_count": errors,
            "rolling_3h_error_avg": round(rolling_sum / 3, 2),
        })
    return expected


def assert_varied_data(actual, expected):
    assert len(actual) == len(expected), f"Varied-input record count mismatch: expected {len(expected)}, got {len(actual)}."
    required_keys = {"window_start", "region", "total_logs", "error_count", "rolling_3h_error_avg"}
    for i, (got, want) in enumerate(zip(actual, expected)):
        assert isinstance(got, dict), f"Varied-input record {i} is not an object."
        assert set(got) == required_keys, f"Varied-input record {i} has incorrect keys: {set(got)}."
        assert isinstance(got["window_start"], str)
        assert isinstance(got["region"], str)
        assert type(got["total_logs"]) is int
        assert type(got["error_count"]) is int
        assert type(got["rolling_3h_error_avg"]) is float
        assert got["window_start"] == want["window_start"], f"Varied-input record {i} window mismatch: expected {want}, got {got}."
        assert got["region"] == want["region"], f"Varied-input record {i} region mismatch: expected {want}, got {got}."
        assert got["total_logs"] == want["total_logs"], f"Varied-input record {i} total mismatch: expected {want}, got {got}."
        assert got["error_count"] == want["error_count"], f"Varied-input record {i} error count mismatch: expected {want}, got {got}."
        assert abs(got["rolling_3h_error_avg"] - want["rolling_3h_error_avg"]) < 0.001, f"Varied-input record {i} rolling average mismatch: expected {want}, got {got}."


def test_rolling_stats_json_exists_and_correct():
    assert os.path.lexists(SCRIPT), f"Required script {SCRIPT} is missing."
    assert stat.S_ISREG(os.lstat(SCRIPT).st_mode), f"{SCRIPT} must be a regular file."

    originals = {}
    for path in (LOGS, META, OUTPUT):
        originals[path] = open(path, "rb").read() if os.path.exists(path) else None

    try:
        original_data = run_script()
        assert_original_data(original_data)

        metadata, records = write_varied_inputs()
        expected = derive_expected(metadata, records)
        varied_data = run_script()
        assert_varied_data(varied_data, expected)
    finally:
        for path, content in originals.items():
            if content is None:
                if os.path.exists(path):
                    os.unlink(path)
            else:
                with open(path, "wb") as f:
                    f.write(content)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

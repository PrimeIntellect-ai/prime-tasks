#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import secrets
import subprocess
from pathlib import Path

SCRIPT = Path("/home/user/run_pipeline.sh")
RAW = Path("/home/user/raw_events.jsonl")
SUMMARY = Path("/home/user/summary.csv")

CANONICAL_EVENTS = [
    {"event_id": 1, "timestamp": 1600000000, "user_id": "user_a", "ip_address": "192.168.1.10", "duration_sec": 10, "event_type": "login"},
    {"event_id": 2, "timestamp": 1600000010, "user_id": "user_a", "ip_address": "192.168.1.10", "duration_sec": 20, "event_type": "click"},
    {"event_id": 3, "timestamp": 1600000020, "user_id": "user_a", "ip_address": "192.168.1.15", "duration_sec": 30, "event_type": "click"},
    {"event_id": 4, "timestamp": 1600000030, "user_id": "user_a", "ip_address": "192.168.1.15", "duration_sec": 40, "event_type": "logout"},
    {"event_id": 5, "timestamp": 1600000040, "user_id": "user_b", "ip_address": "10.0.0.5", "duration_sec": 5, "event_type": "login"},
    {"event_id": 6, "timestamp": 1600000050, "user_id": "user_b", "ip_address": "10.0.0.5", "duration_sec": 100, "event_type": "system_ping"},
    {"event_id": 7, "timestamp": 1600000060, "user_id": "user_b", "ip_address": "10.0.0.6", "duration_sec": 15, "event_type": "click"},
    {"event_id": 8, "timestamp": 1600000070, "user_id": "user_c", "ip_address": "172.16.254.1", "duration_sec": 50, "event_type": "login"},
]


def write_events(events):
    with RAW.open("w") as f:
        for event in events:
            f.write(json.dumps(event, separators=(",", ":")) + "\n")


def execute_pipeline(events):
    write_events(events)
    if SUMMARY.exists():
        SUMMARY.unlink()
    result = subprocess.run(
        [str(SCRIPT)],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"Pipeline exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert SUMMARY.exists(), "Pipeline did not create /home/user/summary.csv"
    assert SUMMARY.is_file(), "Expected /home/user/summary.csv to be a file"


def expected_for(events):
    grouped = {}
    for event in events:
        if event["event_type"] == "system_ping":
            continue
        grouped.setdefault(event["user_id"], []).append(event)

    expected = {}
    for user_id, user_events in grouped.items():
        user_events.sort(key=lambda event: event["timestamp"])
        rolling = []
        for index in range(len(user_events)):
            window = user_events[max(0, index - 2):index + 1]
            rolling.append(sum(event["duration_sec"] for event in window) / len(window))
        masked_ips = sorted({
            event["ip_address"].rsplit(".", 1)[0] + ".xxx"
            for event in user_events
        })
        expected[user_id] = [
            user_id,
            str(len(user_events)),
            f"{max(rolling):.1f}",
            ";".join(masked_ips),
        ]
    return expected


def read_and_check_summary(expected):
    with SUMMARY.open("r", newline="") as f:
        rows = list(csv.reader(f))

    expected_header = ["user_id", "total_valid_events", "max_rolling_avg", "unique_masked_ips"]
    assert len(rows) > 0, f"File {SUMMARY} is empty."
    assert rows[0] == expected_header, f"Expected header {expected_header}, but got {rows[0]}"

    data_rows = rows[1:]
    assert len(data_rows) == len(expected), (
        f"Expected {len(expected)} data rows, but got {len(data_rows)}"
    )

    actual = {}
    for row in data_rows:
        assert len(row) == 4, f"Row does not have 4 columns: {row}"
        assert row[0] not in actual, f"Duplicate data row for user: {row[0]}"
        actual[row[0]] = row

    for user_id, expected_row in expected.items():
        assert user_id in actual, f"Missing data for user: {user_id}"
        assert actual[user_id] == expected_row, (
            f"Incorrect data for {user_id}. Expected {expected_row}, got {actual[user_id]}"
        )


def test_run_pipeline_script_exists_and_executable():
    """Test that the run_pipeline.sh script exists and is executable."""
    assert SCRIPT.exists(), f"Missing script: {SCRIPT}"
    assert SCRIPT.is_file(), f"Expected {SCRIPT} to be a file."
    assert os.access(SCRIPT, os.X_OK), f"Script {SCRIPT} is not executable."


def test_summary_csv_exists():
    """Test that the summary.csv file exists."""
    assert SUMMARY.exists(), f"Missing output file: {SUMMARY}"
    assert SUMMARY.is_file(), f"Expected {SUMMARY} to be a file."


def test_summary_csv_contents_after_execution():
    """Execute the pipeline and retain the original fixed-fixture assertions."""
    execute_pipeline(CANONICAL_EVENTS)
    expected_rows = {
        "user_a": ["user_a", "4", "30.0", "192.168.1.xxx"],
        "user_b": ["user_b", "2", "10.0", "10.0.0.xxx"],
        "user_c": ["user_c", "1", "50.0", "172.16.254.xxx"],
    }
    read_and_check_summary(expected_rows)


def test_pipeline_on_unseen_fixture():
    """Exercise filtering, timestamp ordering, masking, and rolling aggregation."""
    token = secrets.token_hex(5)
    users = [f"alpha_{token}", f"beta_{token}", f"gamma_{token}"]
    base = 1700000000 + secrets.randbelow(100000)
    bump = secrets.randbelow(7)
    prefix_a = f"10.{secrets.randbelow(200)}.7"
    prefix_b = f"172.{16 + secrets.randbelow(16)}.9"
    prefix_c = f"192.168.{secrets.randbelow(200)}"

    events = [
        {"timestamp": base + 10, "user_id": users[0], "ip_address": prefix_a + ".11", "duration_sec": 10 + bump, "event_type": "login"},
        {"timestamp": base + 20, "user_id": users[0], "ip_address": prefix_a + ".99", "duration_sec": 9999, "event_type": "system_ping"},
        {"timestamp": base + 30, "user_id": users[0], "ip_address": prefix_b + ".3", "duration_sec": 20 + bump, "event_type": "click"},
        {"timestamp": base + 40, "user_id": users[0], "ip_address": prefix_a + ".42", "duration_sec": 90 + bump, "event_type": "click"},
        {"timestamp": base + 50, "user_id": users[0], "ip_address": prefix_b + ".8", "duration_sec": 90 + bump, "event_type": "logout"},
        {"timestamp": base + 12, "user_id": users[1], "ip_address": prefix_c + ".1", "duration_sec": 30 + bump, "event_type": "login"},
        {"timestamp": base + 22, "user_id": users[1], "ip_address": prefix_c + ".2", "duration_sec": 5000, "event_type": "system_ping"},
        {"timestamp": base + 32, "user_id": users[1], "ip_address": prefix_b + ".77", "duration_sec": 80 + bump, "event_type": "click"},
        {"timestamp": base + 14, "user_id": users[2], "ip_address": prefix_c + ".5", "duration_sec": 60 + bump, "event_type": "login"},
        {"timestamp": base + 24, "user_id": users[2], "ip_address": prefix_c + ".6", "duration_sec": 5 + bump, "event_type": "system_ping "},
        {"timestamp": base + 34, "user_id": users[2], "ip_address": prefix_a + ".7", "duration_sec": 5 + bump, "event_type": "click"},
        {"timestamp": base + 44, "user_id": users[2], "ip_address": prefix_a + ".8", "duration_sec": 100 + bump, "event_type": "logout"},
    ]
    for event_id, event in enumerate(events, 1001):
        event["event_id"] = event_id

    random.SystemRandom().shuffle(events)
    expected = expected_for(events)
    execute_pipeline(events)
    read_and_check_summary(expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

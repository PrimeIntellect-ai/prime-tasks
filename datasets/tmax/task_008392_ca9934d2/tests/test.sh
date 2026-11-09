#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import stat
import subprocess
import uuid
from datetime import datetime, timedelta, timezone

import pytest

PROCESS_PATH = "/home/user/process.go"
INPUT_PATH = "/home/user/input/events.csv"
OUTPUT_PATH = "/home/user/output.jsonl"


def run_process():
    result = subprocess.run(
        [
            "runuser", "-u", "user", "--",
            "env", "HOME=/home/user", "GOCACHE=/tmp/verifier-go-cache", "GO111MODULE=off",
            "go", "run", PROCESS_PATH,
        ],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert result.returncode == 0, (
        f"process.go failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


@pytest.fixture(scope="session", autouse=True)
def execute_process_on_original_input():
    assert os.path.lexists(PROCESS_PATH), f"The Go script {PROCESS_PATH} does not exist."
    assert not os.path.islink(PROCESS_PATH), f"{PROCESS_PATH} must be a Go source file, not a symlink."
    assert stat.S_ISREG(os.stat(PROCESS_PATH).st_mode), f"{PROCESS_PATH} is not a regular file."

    os.makedirs("/tmp/verifier-go-cache", exist_ok=True)
    os.chmod("/tmp/verifier-go-cache", 0o777)
    if os.path.lexists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    run_process()


def test_output_file_exists():
    output_path = "/home/user/output.jsonl"
    assert os.path.isfile(output_path), f"The output file {output_path} does not exist."


def test_output_content_and_format():
    output_path = "/home/user/output.jsonl"
    with open(output_path, "r") as f:
        lines = f.read().strip().split("\n")

    assert len(lines) == 4, f"Expected 4 JSON lines in the output, but found {len(lines)}."

    parsed_lines = []
    for i, line in enumerate(lines):
        try:
            parsed_lines.append(json.loads(line))
        except json.JSONDecodeError:
            pytest.fail(f"Line {i+1} is not valid JSON: {line}")

    expected_data = [
        {
            "interval": "2023-11-01T08:00:00Z",
            "event_id": "EVT-001",
            "severity": "INFO",
            "message": "Service started successfully"
        },
        {
            "interval": "2023-11-01T08:00:00Z",
            "event_id": "EVT-002",
            "severity": "WARN",
            "message": "Memory usage high\nConsider upgrading instance"
        },
        {
            "interval": "2023-11-01T09:00:00Z",
            "event_id": "EVT-004",
            "severity": "ERROR",
            "message": "Database connection lost\nRetrying in 5 seconds..."
        },
        {
            "interval": "2023-11-01T09:00:00Z",
            "event_id": "EVT-006",
            "severity": "INFO",
            "message": "User logged in"
        }
    ]

    for i, (actual, expected) in enumerate(zip(parsed_lines, expected_data)):
        assert actual == expected, f"Mismatch at line {i+1}.\nExpected: {expected}\nActual: {actual}"


def reference_output(path):
    seen = set()
    selected = {}

    with open(path, "r", newline="", encoding="utf-8") as f:
        for row in csv.DictReader(f):
            event_id = row["event_id"]
            if event_id in seen:
                continue
            seen.add(event_id)

            timestamp = datetime.fromisoformat(row["timestamp"].replace("Z", "+00:00"))
            interval_dt = timestamp.replace(minute=0, second=0, microsecond=0)
            interval = interval_dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:00:00Z")
            key = (interval, row["severity"])
            candidate = (timestamp, {
                "interval": interval,
                "event_id": event_id,
                "severity": row["severity"],
                "message": row["message"],
            })
            if key not in selected or timestamp < selected[key][0]:
                selected[key] = candidate

    return [selected[key][1] for key in sorted(selected)]


def test_process_handles_unseen_multiline_dedup_bucketing_and_sampling_case():
    with open(INPUT_PATH, "rb") as f:
        original_input = f.read()
    with open(OUTPUT_PATH, "rb") as f:
        original_output = f.read()

    rng = random.SystemRandom()
    base = datetime(2024, 1, 1, rng.randrange(0, 22), tzinfo=timezone.utc) + timedelta(days=rng.randrange(0, 300))
    ids = [f"VERIFY-{uuid.uuid4()}" for _ in range(7)]
    token = uuid.uuid4().hex

    def ts(hour_offset, minute, second=0, micros=0):
        value = base + timedelta(hours=hour_offset, minutes=minute, seconds=second, microseconds=micros)
        if micros:
            return value.strftime("%Y-%m-%dT%H:%M:%S.%fZ")
        return value.strftime("%Y-%m-%dT%H:%M:%SZ")

    rows = [
        [ts(0, 40), ids[0], "INFO", f"late info {token}\nsecond line, with comma and a \"quote\""],
        [ts(0, 1), ids[0], "ERROR", "duplicate ID must be ignored even though earlier"],
        [ts(0, 5, micros=123000), ids[1], "INFO", f"earliest info {token}"],
        [ts(0, 20), ids[2], "WARN", "later warning"],
        [ts(0, 10), ids[3], "WARN", "earliest warning\ncontinued"],
        [ts(1, 0), ids[1], "CRITICAL", "cross-bucket duplicate must be ignored"],
        [ts(1, 50), ids[4], "ERROR", "later error"],
        [ts(1, 2), ids[5], "ERROR", f"earliest error, {token}"],
        [ts(1, 3), ids[6], "INFO", "only info in second bucket"],
    ]

    try:
        with open(INPUT_PATH, "w", newline="", encoding="utf-8") as f:
            writer = csv.writer(f, lineterminator="\r\n")
            writer.writerow(["timestamp", "event_id", "severity", "message"])
            writer.writerows(rows)

        expected = reference_output(INPUT_PATH)
        if os.path.lexists(OUTPUT_PATH):
            os.remove(OUTPUT_PATH)
        run_process()

        assert os.path.isfile(OUTPUT_PATH), "process.go did not create output.jsonl"
        with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
            output_lines = f.read().splitlines()

        assert len(output_lines) == len(expected), (
            f"Expected {len(expected)} JSON lines for generated input, found {len(output_lines)}."
        )
        actual = []
        for i, line in enumerate(output_lines):
            assert line.strip(), f"Output line {i + 1} is blank."
            try:
                value = json.loads(line)
            except json.JSONDecodeError as exc:
                pytest.fail(f"Generated-case output line {i + 1} is invalid JSON: {exc}")
            assert set(value) == {"interval", "event_id", "severity", "message"}, (
                f"Output line {i + 1} has incorrect keys: {set(value)}"
            )
            actual.append(value)

        assert actual == expected, f"Generated-case output mismatch.\nExpected: {expected}\nActual: {actual}"
    finally:
        with open(INPUT_PATH, "wb") as f:
            f.write(original_input)
        with open(OUTPUT_PATH, "wb") as f:
            f.write(original_output)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

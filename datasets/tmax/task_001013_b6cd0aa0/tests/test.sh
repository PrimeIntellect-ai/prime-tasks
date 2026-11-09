#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import secrets
import subprocess
from datetime import datetime, timezone

SCRIPT_PATH = "/home/user/parser.go"
INPUT_PATH = "/home/user/legacy.log"
OUTPUT_PATH = "/home/user/normalized_alerts.jsonl"


def test_go_script_exists():
    script_path = "/home/user/parser.go"
    assert os.path.isfile(script_path), f"Go script {script_path} does not exist."


def test_normalized_alerts_jsonl():
    output_path = "/home/user/normalized_alerts.jsonl"
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."

    expected_data = [
        {"time": "2023-10-24T14:25:01Z", "level": "ERROR", "user": "USR-099", "msg": "Connection timeout in region us-east."},
        {"time": "2023-10-24T14:26:15Z", "level": "WARN", "user": "USR-442", "msg": "Disk usage high on /dev/sda1"},
        {"time": "2023-10-25T09:00:00Z", "level": "ERROR", "user": "USR-102", "msg": "Database lock acquisition failed."},
        {"time": "2024-01-01T00:00:01Z", "level": "WARN", "user": "USR-007", "msg": "Unexpected payload size: 4096 bytes"}
    ]

    with open(output_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(expected_data), f"Expected {len(expected_data)} lines in {output_path}, but found {len(lines)}."

    for i, (line, expected) in enumerate(zip(lines, expected_data)):
        try:
            parsed = json.loads(line)
        except json.JSONDecodeError:
            assert False, f"Line {i+1} is not valid JSON: {line}"

        assert parsed == expected, f"Line {i+1} JSON content mismatch.\nExpected: {expected}\nGot: {parsed}"


def test_go_program_on_fresh_input():
    rng = secrets.SystemRandom()
    token = secrets.token_hex(8)
    ids = [str(rng.randrange(100000, 999999)) for _ in range(3)]
    dates = [
        datetime(rng.randrange(2026, 2036), 2, rng.randrange(1, 28), rng.randrange(24), rng.randrange(60), rng.randrange(60), tzinfo=timezone.utc),
        datetime(rng.randrange(2026, 2036), 7, rng.randrange(1, 29), rng.randrange(24), rng.randrange(60), rng.randrange(60), tzinfo=timezone.utc),
        datetime(rng.randrange(2026, 2036), 11, rng.randrange(1, 29), rng.randrange(24), rng.randrange(60), rng.randrange(60), tzinfo=timezone.utc),
    ]
    levels = ["ERROR", "WARN", "ERROR"]
    messages = [
        f"Generated connection failure {token}",
        f"Generated disk warning {token}",
        f"Generated payload alert {token}",
    ]
    stamps = [
        dates[0].strftime("%Y/%m/%d-%H:%M:%S"),
        dates[1].strftime("%m-%d-%Y %H:%M:%S"),
        dates[2].strftime("%Y.%m.%d %H:%M:%S"),
    ]

    input_lines = [
        f"{dates[0].strftime('%Y/%m/%d-%H:%M:%S')} INFO [USR-{ids[0]}] ignored info {token}",
        f"{stamps[0]} {levels[0]} [USR-{ids[0]}]   {messages[0]}   ",
        f"{dates[1].strftime('%m-%d-%Y %H:%M:%S')} ERROR [SYS-001] ignored system {token}",
        f"{stamps[1]} {levels[1]} [USR-{ids[1]}] {messages[1]}",
        f"{dates[2].strftime('%Y.%m.%d %H:%M:%S')} WARN [USR-12A] ignored malformed user {token}",
        f"{stamps[2]} {levels[2]} [USR-{ids[2]}]  {messages[2]}  ",
    ]
    expected = [
        {
            "time": dt.strftime("%Y-%m-%dT%H:%M:%SZ"),
            "level": level,
            "user": f"USR-{uid}",
            "msg": msg,
        }
        for dt, level, uid, msg in zip(dates, levels, ids, messages)
    ]

    with open(INPUT_PATH, "w", encoding="utf-8") as f:
        f.write("\n".join(input_lines) + "\n")
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)

    result = subprocess.run(
        ["go", "run", SCRIPT_PATH],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, f"Go program failed.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    assert os.path.isfile(OUTPUT_PATH), f"Program did not create {OUTPUT_PATH}."

    with open(OUTPUT_PATH, "r", encoding="utf-8") as f:
        raw_lines = [line.strip() for line in f if line.strip()]
    assert len(raw_lines) == len(expected), f"Expected {len(expected)} generated records, got {len(raw_lines)}."

    actual = []
    for i, line in enumerate(raw_lines, 1):
        try:
            record = json.loads(line)
        except json.JSONDecodeError as exc:
            assert False, f"Generated line {i} is not valid JSON: {exc}"
        assert set(record.keys()) == {"time", "level", "user", "msg"}, f"Generated line {i} has incorrect keys: {record}"
        actual.append(record)

    assert actual == expected, f"Fresh-input output mismatch.\nExpected: {expected}\nGot: {actual}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

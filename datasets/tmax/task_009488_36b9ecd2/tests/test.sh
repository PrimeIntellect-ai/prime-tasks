#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import subprocess
from pathlib import Path

import pytest


def test_process_script_exists():
    script_path = "/home/user/process.sh"
    assert os.path.exists(script_path), f"The script file {script_path} does not exist. You must create it."
    assert os.path.isfile(script_path), f"{script_path} is not a regular file."


def test_alerts_jsonl_exists_and_content():
    alerts_path = "/home/user/alerts.jsonl"
    assert os.path.exists(alerts_path), f"The output file {alerts_path} does not exist."
    assert os.path.isfile(alerts_path), f"{alerts_path} is not a regular file."

    expected_data = [
        {"alert_type": "HighTemp", "timestamp": "2023-10-12T08:02:00Z", "sensor": "S-303", "reading": 91.5},
        {"alert_type": "HighTemp", "timestamp": "2023-10-12T08:04:00Z", "sensor": "S-505", "reading": 90.1},
        {"alert_type": "HighTemp", "timestamp": "2023-10-12T08:07:00Z", "sensor": "S-808", "reading": 105.3}
    ]

    actual_data = []
    with open(alerts_path, "r") as f:
        for line_num, line in enumerate(f, start=1):
            line = line.strip()
            if not line:
                continue
            try:
                parsed = json.loads(line)
                actual_data.append(parsed)
            except json.JSONDecodeError:
                pytest.fail(f"Line {line_num} in {alerts_path} is not valid JSON: {line}")

    assert len(actual_data) == len(expected_data), (
        f"Expected {len(expected_data)} alerts, but found {len(actual_data)} in {alerts_path}."
    )

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual == expected, (
            f"Alert at line {i+1} does not match expected output.\n"
            f"Expected: {expected}\n"
            f"Actual:   {actual}"
        )


def test_process_script_filters_fresh_input_when_executed():
    script_path = Path("/home/user/process.sh")
    sensor_path = Path("/home/user/sensor_data.log")
    alerts_path = Path("/home/user/alerts.jsonl")

    original_sensor = sensor_path.read_bytes()
    original_alerts = alerts_path.read_bytes()

    token = secrets.token_hex(5).upper()
    hot1 = f"{9101 + secrets.randbelow(300):d}"
    hot1 = hot1[:-2] + "." + hot1[-2:]
    hot2 = f"{10001 + secrets.randbelow(500):d}"
    hot2 = hot2[:-2] + "." + hot2[-2:]
    ts1 = f"2026-09-12T10:00:{secrets.randbelow(30):02d}Z"
    ts2 = f"2026-09-12T10:01:{30 + secrets.randbelow(30):02d}Z"
    sensor1 = f"S-{token}-A"
    sensor2 = f"S-{token}-B"

    fresh_input = "\n".join([
        f"2026-09-12T09:59:00Z | S-{token}-LOW | EU-CENTRAL | 89.99 | 41.0",
        f"  {ts1}  |\t{sensor1}\t|   EU-CENTRAL   |  {hot1}  | 42.1",
        f"2026-09-12T10:00:30Z | S-{token}-EDGE | EU-CENTRAL | 90.0 | 43.2",
        f"2026-09-12T10:00:45Z | S-{token}-OTHER | NA-WEST | 123.45 | 44.3",
        f"2026-09-12T10:00:50Z | S-{token}-NEAR | EU-CENTRAL-X | 150.00 | 45.4",
        f"\t{ts2}\t| {sensor2} |\tEU-CENTRAL\t|\t{hot2}\t| 46.5",
    ]) + "\n"

    expected_lines = [
        f'{{"alert_type": "HighTemp", "timestamp": "{ts1}", "sensor": "{sensor1}", "reading": {hot1}}}',
        f'{{"alert_type": "HighTemp", "timestamp": "{ts2}", "sensor": "{sensor2}", "reading": {hot2}}}',
    ]

    try:
        sensor_path.write_text(fresh_input)
        alerts_path.unlink()

        result = subprocess.run(
            ["bash", str(script_path)],
            cwd="/home/user",
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=15,
        )
        assert result.returncode == 0, (
            f"Executing {script_path} failed with status {result.returncode}.\n"
            f"stdout: {result.stdout}\nstderr: {result.stderr}"
        )
        assert alerts_path.exists(), "The script did not create /home/user/alerts.jsonl."
        assert alerts_path.is_file(), "/home/user/alerts.jsonl is not a regular file after execution."

        actual_lines = alerts_path.read_text().splitlines()
        assert actual_lines == expected_lines, (
            "The script did not produce the exact alerts for a fresh sensor stream.\n"
            f"Expected: {expected_lines}\nActual:   {actual_lines}"
        )
    finally:
        sensor_path.write_bytes(original_sensor)
        alerts_path.write_bytes(original_alerts)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

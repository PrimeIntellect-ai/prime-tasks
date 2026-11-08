#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import stat
import subprocess
import uuid
from collections import defaultdict

import pytest

SCRIPT_PATH = "/home/user/process_configs.py"
INPUT_PATH = "/home/user/config_events.jsonl"
SUMMARY_PATH = "/home/user/hourly_summary.json"
QUARANTINE_PATH = "/home/user/quarantine.jsonl"


def remove_outputs():
    for path in (SUMMARY_PATH, QUARANTINE_PATH):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass


def run_script():
    result = subprocess.run(
        ["python3", SCRIPT_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f"{SCRIPT_PATH} exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def test_script_executes_and_original_outputs_are_correct():
    assert os.path.exists(SCRIPT_PATH), f"Required script {SCRIPT_PATH} is missing."
    assert stat.S_ISREG(os.lstat(SCRIPT_PATH).st_mode), f"{SCRIPT_PATH} is not a regular file."

    remove_outputs()
    run_script()

    summary_path = "/home/user/hourly_summary.json"
    assert os.path.isfile(summary_path), f"Output file {summary_path} is missing."

    with open(summary_path, 'r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{summary_path} is not a valid JSON file.")

    expected_data = {
        "2023-10-25T14:00:00Z": {
            "web": 2
        },
        "2023-10-25T15:00:00Z": {
            "db": 1,
            "web": 1
        },
        "2023-10-26T09:00:00Z": {
            "db": 1
        }
    }

    assert data == expected_data, f"Content of {summary_path} does not match expected aggregation."

    quarantine_path = "/home/user/quarantine.jsonl"
    assert os.path.isfile(quarantine_path), f"Output file {quarantine_path} is missing."

    with open(quarantine_path, 'r', encoding='utf-8') as f:
        lines = f.read().splitlines()

    expected_lines = [
        r'{"timestamp": "2023-10-25T14:50:00Z", "service": "api", "action": "update", "details": "corrupted unicode \u12X4 error"}',
        r'{"timestamp": "2023-10-25T15:42:00Z", "service": "api", "action": "restart", "details": "bad escape \uZZZZ crash"}'
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in {quarantine_path}, found {len(lines)}."

    for i, expected_line in enumerate(expected_lines):
        assert lines[i] == expected_line, f"Line {i+1} in {quarantine_path} does not match the expected raw string."


def test_pipeline_on_fresh_unpredictable_input():
    with open(INPUT_PATH, "rb") as f:
        original_input = f.read()

    token = uuid.uuid4().hex
    service_a = "frontend_" + token[:10]
    service_b = "worker_" + token[10:20]
    valid_events = [
        {"timestamp": "2041-07-08T03:01:02Z", "service": service_a, "action": "update", "details": token},
        {"timestamp": "2041-07-08T03:59:58Z", "service": service_a, "action": "restart", "details": "second " + token},
        {"timestamp": "2041-07-08T03:30:00Z", "service": service_b, "action": "update", "details": "third " + token},
        {"timestamp": "2041-07-08T04:00:01Z", "service": service_b, "action": "backup", "details": "fourth " + token},
        {"timestamp": "2041-07-09T22:17:43Z", "service": service_a, "action": "update", "details": "fifth " + token},
    ]

    slash = chr(92)
    malformed_one = '{"timestamp": "2041-07-08T03:40:00Z", "service": "bad_' + token + '", "action": "update", "details": "broken ' + slash + 'u12X4 ' + token + '"}'
    malformed_two = '{"timestamp": "2041-07-08T04:40:00Z", "service": "bad2_' + token + '", "action": "restart", "details": "broken ' + slash + 'uZZZZ ' + token + '"}'

    input_lines = [
        json.dumps(valid_events[0]),
        malformed_one,
        json.dumps(valid_events[1]),
        json.dumps(valid_events[2]),
        json.dumps(valid_events[3]),
        malformed_two,
        json.dumps(valid_events[4]),
    ]

    expected = defaultdict(lambda: defaultdict(int))
    for event in valid_events:
        hour = event["timestamp"][:13] + ":00:00Z"
        expected[hour][event["service"]] += 1
    expected = {hour: dict(counts) for hour, counts in expected.items()}

    try:
        with open(INPUT_PATH, "w", encoding="utf-8", newline="") as f:
            f.write("\n".join(input_lines) + "\n")
        remove_outputs()
        run_script()

        assert os.path.isfile(SUMMARY_PATH), f"Output file {SUMMARY_PATH} is missing."
        with open(SUMMARY_PATH, "r", encoding="utf-8") as f:
            actual_summary = json.load(f)
        assert actual_summary == expected, "The script did not aggregate the fresh input correctly."

        assert os.path.isfile(QUARANTINE_PATH), f"Output file {QUARANTINE_PATH} is missing."
        with open(QUARANTINE_PATH, "r", encoding="utf-8", newline="") as f:
            actual_quarantine = f.read()
        assert actual_quarantine == malformed_one + "\n" + malformed_two + "\n", (
            "Malformed input lines were not quarantined raw and in input order."
        )
    finally:
        with open(INPUT_PATH, "wb") as f:
            f.write(original_input)
        remove_outputs()
        subprocess.run(
            ["python3", SCRIPT_PATH],
            cwd="/home/user",
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=20,
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

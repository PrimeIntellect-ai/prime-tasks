#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import subprocess
import sys
import uuid
from collections import Counter

import pytest


def test_video_data_long_csv():
    csv_path = "/home/user/video_data_long.csv"
    assert os.path.isfile(csv_path), f"File {csv_path} does not exist."

    with open(csv_path, "r", newline="") as f:
        reader = csv.reader(f)
        header = next(reader, None)
        assert header == ["second_offset", "sensor_name", "state"], f"Incorrect CSV header: {header}"
        rows = list(reader)

    assert len(rows) == 15, f"Expected 15 rows in CSV, found {len(rows)}"

    expected_states = {
        0: {"red": 1, "green": 0, "blue": 0},
        1: {"red": 1, "green": 1, "blue": 0},
        2: {"red": 0, "green": 1, "blue": 1},
        3: {"red": 0, "green": 0, "blue": 1},
        4: {"red": 1, "green": 1, "blue": 1},
    }

    parsed_rows = []
    for row in rows:
        assert len(row) == 3, f"Invalid row length: {row}"
        offset = int(row[0])
        sensor = row[1]
        state = int(row[2])
        parsed_rows.append((offset, sensor, state))

    sorted_rows = sorted(parsed_rows, key=lambda x: (x[0], x[1]))
    assert parsed_rows == sorted_rows, "CSV rows are not sorted by second_offset then sensor_name."

    expected_pairs = {
        (offset, sensor)
        for offset in expected_states
        for sensor in ("red", "green", "blue")
    }
    actual_pairs = [(offset, sensor) for offset, sensor, _ in parsed_rows]
    assert len(set(actual_pairs)) == 15, "CSV contains duplicate (second_offset, sensor_name) pairs."
    assert set(actual_pairs) == expected_pairs, "CSV does not contain every required (second_offset, sensor_name) pair exactly once."

    for offset, sensor, state in parsed_rows:
        assert expected_states[offset][sensor] == state, f"Incorrect state for second {offset}, sensor {sensor}: expected {expected_states[offset][sensor]}, got {state}"


def test_validator_script():
    script_path = "/home/user/validator.py"
    assert os.path.isfile(script_path), f"Validator script {script_path} does not exist."

    clean_dir = "/app/corpus/clean/"
    clean_files = [f for f in os.listdir(clean_dir) if f.endswith(".json")]

    result_clean = subprocess.run([sys.executable, script_path, clean_dir], capture_output=True, text=True)
    assert result_clean.returncode == 0, f"Validator script failed on clean corpus with error: {result_clean.stderr}"

    clean_output = result_clean.stdout.strip().split("\n")
    clean_output = [line.strip() for line in clean_output if line.strip()]

    rejected_clean = []
    for f in clean_files:
        expected_line = f"ACCEPT: {f}"
        if expected_line not in clean_output:
            rejected_clean.append(f)

    evil_dir = "/app/corpus/evil/"
    evil_files = [f for f in os.listdir(evil_dir) if f.endswith(".json")]

    result_evil = subprocess.run([sys.executable, script_path, evil_dir], capture_output=True, text=True)
    assert result_evil.returncode == 0, f"Validator script failed on evil corpus with error: {result_evil.stderr}"

    evil_output = result_evil.stdout.strip().split("\n")
    evil_output = [line.strip() for line in evil_output if line.strip()]

    accepted_evil = []
    for f in evil_files:
        expected_line = f"REJECT: {f}"
        if expected_line not in evil_output:
            accepted_evil.append(f)

    error_msgs = []
    if rejected_clean:
        error_msgs.append(f"{len(rejected_clean)} of {len(clean_files)} clean files modified/rejected: {', '.join(rejected_clean)}")
    if accepted_evil:
        error_msgs.append(f"{len(accepted_evil)} of {len(evil_files)} evil files bypassed/accepted: {', '.join(accepted_evil)}")

    if error_msgs:
        pytest.fail(" | ".join(error_msgs))


def test_validator_generated_hidden_suite(tmp_path):
    script_path = "/home/user/validator.py"
    assert os.path.isfile(script_path), f"Validator script {script_path} does not exist."

    rng = random.SystemRandom()
    valid_temp = round(rng.uniform(0.01, 149.99), 4)
    valid_pressure = round(rng.uniform(10.01, 19.99), 4)
    second = rng.randrange(0, 60)
    timestamp = f"2031-07-19T08:23:{second:02d}Z"

    cases = [
        (True, {"timestamp": timestamp, "temp": valid_temp, "pressure": valid_pressure}),
        (True, {"timestamp": "2000-01-01T00:00:00Z", "temp": 0, "pressure": 10}),
        (True, {"timestamp": "2099-12-31T23:59:59Z", "temp": 150.0, "pressure": 20.0}),
        (False, {"timestamp": timestamp, "temp": valid_temp}),
        (False, {"timestamp": timestamp, "temp": valid_temp, "pressure": valid_pressure, "extra": 1}),
        (False, {"timestamp": timestamp, "temp": str(valid_temp), "pressure": valid_pressure}),
        (False, {"timestamp": timestamp, "temp": valid_temp, "pressure": str(valid_pressure)}),
        (False, {"timestamp": timestamp, "temp": True, "pressure": valid_pressure}),
        (False, {"timestamp": timestamp, "temp": valid_temp, "pressure": False}),
        (False, {"timestamp": timestamp, "temp": None, "pressure": valid_pressure}),
        (False, {"timestamp": timestamp, "temp": -rng.uniform(0.1, 50), "pressure": valid_pressure}),
        (False, {"timestamp": timestamp, "temp": 150 + rng.uniform(0.1, 50), "pressure": valid_pressure}),
        (False, {"timestamp": timestamp, "temp": valid_temp, "pressure": 10 - rng.uniform(0.1, 5)}),
        (False, {"timestamp": timestamp, "temp": valid_temp, "pressure": 20 + rng.uniform(0.1, 5)}),
        (False, {"timestamp": "2031-07-19 08:23:45", "temp": valid_temp, "pressure": valid_pressure}),
        (False, {"timestamp": "2031-7-19T08:23:45Z", "temp": valid_temp, "pressure": valid_pressure}),
        (False, {"timestamp": "2031-07-19T08:23:45+00:00", "temp": valid_temp, "pressure": valid_pressure}),
        (False, {"timestamp": 20310719, "temp": valid_temp, "pressure": valid_pressure}),
        (False, "__MALFORMED__"),
    ]
    rng.shuffle(cases)

    expected = []
    for should_accept, payload in cases:
        filename = f"sample_{uuid.uuid4().hex}.json"
        path = tmp_path / filename
        if payload == "__MALFORMED__":
            path.write_text('{"timestamp": ', encoding="utf-8")
        else:
            path.write_text(json.dumps(payload), encoding="utf-8")
        decision = "ACCEPT" if should_accept else "REJECT"
        expected.append(f"{decision}: {filename}")

    (tmp_path / f"ignored_{uuid.uuid4().hex}.txt").write_text("not json", encoding="utf-8")

    result = subprocess.run(
        [sys.executable, script_path, str(tmp_path)],
        capture_output=True,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, f"Validator failed on generated suite: {result.stderr}"

    actual_lines = result.stdout.splitlines()
    assert Counter(actual_lines) == Counter(expected), (
        "Validator must print exactly one correct ACCEPT/REJECT line for every generated .json file.\n"
        f"Expected: {sorted(expected)}\nGot: {sorted(actual_lines)}"
    )


def test_report_txt():
    report_path = "/home/user/report.txt"
    assert os.path.isfile(report_path), f"Report file {report_path} does not exist."

    with open(report_path, "r") as f:
        content = f.read().strip()

    expected_content = """FACTORY ETL REPORT
Total seconds recorded: 5
Red sensor ON duration: 3 seconds
Green sensor ON duration: 3 seconds
Blue sensor ON duration: 3 seconds"""

    assert content == expected_content, f"Report content mismatch.\nExpected:\n{expected_content}\n\nGot:\n{content}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
